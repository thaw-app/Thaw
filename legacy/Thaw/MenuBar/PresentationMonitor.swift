//
//  PresentationMonitor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Darwin
import Foundation

/// Engages zen mode while the screen is being shown to someone else.
///
/// There's no public API to detect another process recording the screen
/// (`CGDisplayIsCaptured` only reports legacy exclusive capture), so this
/// covers:
///
/// - Mirroring: `CGDisplayIsInMirrorSet`, on screen-parameter changes.
/// - Screen sharing: `screensharingd` running, polled only while enabled.
///
/// Local recording (QuickTime, OBS) isn't guessed from a bundle ID list;
/// engaging for the wrong app is worse than not engaging.
@MainActor
final class PresentationMonitor {
    /// Coarse because sharing sessions last minutes.
    private static let pollInterval = Duration.seconds(5)

    private let diagLog = DiagLog(category: "PresentationMonitor")

    private weak var appState: AppState?

    private var settingTask: Task<Void, Never>?
    private var screenParametersTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var evaluateTask: Task<Void, Never>?

    /// The last evaluated state, kept so a repeated signal doesn't re-log.
    private var isPresenting = false

    func performSetup(with appState: AppState) {
        self.appState = appState
        settingTask = Task { @MainActor [weak self, advanced = appState.settings.advanced] in
            let changes = Observations { advanced.autoZenWhileSharingScreen }
            for await isEnabled in changes {
                guard let self else { return }
                if isEnabled {
                    startObserving()
                } else {
                    stopObserving()
                }
            }
        }
        if appState.settings.advanced.autoZenWhileSharingScreen {
            startObserving()
        }
    }

    private func startObserving() {
        guard screenParametersTask == nil else { return }

        // The task owns the observer token, so nothing non-Sendable is stored.
        let (events, continuation) = AsyncStream<Void>.makeStream()
        screenParametersTask = Task { @MainActor [weak self] in
            let observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in continuation.yield(()) }
            defer { NotificationCenter.default.removeObserver(observer) }
            for await _ in events {
                guard let self else { break }
                evaluate()
            }
        }

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                evaluate()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }

        evaluate()
    }

    private func stopObserving() {
        screenParametersTask?.cancel()
        screenParametersTask = nil
        pollTask?.cancel()
        pollTask = nil
        evaluateTask?.cancel()
        evaluateTask = nil
        // Withdraw anything this monitor engaged; a manual zen mode is left
        // alone by `setAutomaticZenMode`.
        isPresenting = false
        appState?.menuBarManager.setAutomaticZenMode(false)
    }

    private func evaluate() {
        // The process-table walk runs detached, so rounds can land out of
        // order. Cancel the previous one; a cancelled round never applies.
        evaluateTask?.cancel()
        evaluateTask = Task { @MainActor [weak self] in
            // Mirroring is cheap and belongs on the main thread.
            let mirroring = Self.isMirroring()
            let shared = await Task.detached(priority: .utility) {
                Self.isScreenBeingShared()
            }.value
            let presenting = mirroring || shared
            guard !Task.isCancelled, let self else { return }
            defer { self.appState?.menuBarManager.setAutomaticZenMode(presenting) }

            guard presenting != self.isPresenting else { return }
            self.isPresenting = presenting
            self.diagLog.info(presenting
                ? "Screen is being presented or shared — engaging zen mode"
                : "Presentation ended — withdrawing zen mode")
        }
    }

    // MARK: - Signals

    /// Whether any active display is part of a mirror set. Main-actor bound:
    /// it reads `NSScreen.screens`.
    private static func isMirroring() -> Bool {
        NSScreen.screens.contains { CGDisplayIsInMirrorSet($0.displayID) != 0 }
    }

    /// Whether the system's screen-sharing daemon is running.
    ///
    /// `screensharingd` isn't an application, so `NSWorkspace` can't see it.
    private static nonisolated func isScreenBeingShared() -> Bool {
        runningProcessNames().contains("screensharingd")
    }

    /// Every running process's short name.
    ///
    /// Uses `sysctl(KERN_PROC_ALL)` because `proc_name` can't name root
    /// daemons like `screensharingd`. `p_comm` is truncated to 16 characters.
    private static nonisolated func runningProcessNames() -> Set<String> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        // The table can grow between sizing and reading. Retry, since an empty
        // result reads as "not sharing" and would drop zen mode mid-session.
        for _ in 0 ..< 3 {
            guard size > 0 else { return [] }
            let capacity = size / MemoryLayout<kinfo_proc>.stride + 16
            var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var readSize = capacity * MemoryLayout<kinfo_proc>.stride
            if sysctl(&mib, 4, &processes, &readSize, nil, 0) != 0 {
                // Retry with whatever size the kernel reports now; the sizing
                // call above already refreshed it once.
                _ = sysctl(&mib, 4, nil, &size, nil, 0)
                continue
            }

            var names = Set<String>()
            for index in 0 ..< (readSize / MemoryLayout<kinfo_proc>.stride) {
                var process = processes[index].kp_proc
                let name = withUnsafeBytes(of: &process.p_comm) { raw -> String in
                    guard let base = raw.bindMemory(to: CChar.self).baseAddress else {
                        return ""
                    }
                    return String(cString: base)
                }
                if !name.isEmpty {
                    names.insert(name)
                }
            }
            return names
        }
        return []
    }
}
