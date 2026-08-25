//
//  PresentationMonitor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Darwin
import Foundation

/// Engages zen mode for as long as the screen is being shown to someone else,
/// then withdraws it — so a menu bar full of personal status items isn't the
/// first thing an audience sees.
///
/// ## What can and cannot be detected
///
/// macOS 27 exposes no public way to ask whether another process is recording
/// the screen: `CoreGraphics` offers only `CGDisplayIsCaptured`, which reports
/// the legacy exclusive-capture mode rather than a ScreenCaptureKit stream,
/// and ScreenCaptureKit has no observer for other clients. So this monitor
/// covers the two states that *are* observable with public API:
///
/// - **Mirroring** — `CGDisplayIsInMirrorSet`, the projector/TV case. Driven by
///   `didChangeScreenParametersNotification`, so it costs nothing at rest.
/// - **Screen sharing / remote management** — the presence of the system's
///   `screensharingd`. There is no notification for it, so it is polled, and
///   only while the setting is on.
///
/// Local recording by an app such as QuickTime, OBS, or a conferencing client
/// is **not** covered, and deliberately isn't guessed at from a list of known
/// recorder bundle identifiers: that list is wrong the moment it ships, and a
/// zen mode that engages for the wrong app is worse than one that doesn't
/// engage at all.
@MainActor
final class PresentationMonitor {
    /// How often the screen-sharing daemon is looked for. Sharing sessions
    /// last minutes, so a coarse interval is enough and keeps the process
    /// enumeration off the critical path.
    private static let pollInterval = Duration.seconds(5)

    private let diagLog = DiagLog(category: "PresentationMonitor")

    private weak var appState: AppState?

    private var settingTask: Task<Void, Never>?
    private var screenParametersTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

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

        // Same observer-owned-by-the-task shape as `DisplaySettingsManager`:
        // the token is added when the task starts and removed when it ends,
        // so nothing non-Sendable has to be stored on the class.
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
        // Withdraw anything this monitor engaged; a manual zen mode is left
        // alone by `setAutomaticZenMode`.
        isPresenting = false
        appState?.menuBarManager.setAutomaticZenMode(false)
    }

    private func evaluate() {
        let presenting = Self.isMirroring() || Self.isScreenBeingShared()
        defer { appState?.menuBarManager.setAutomaticZenMode(presenting) }

        guard presenting != isPresenting else { return }
        isPresenting = presenting
        diagLog.info(presenting
            ? "Screen is being presented or shared — engaging zen mode"
            : "Presentation ended — withdrawing zen mode")
    }

    // MARK: - Signals

    /// Whether any active display is part of a mirror set.
    private static func isMirroring() -> Bool {
        NSScreen.screens.contains { CGDisplayIsInMirrorSet($0.displayID) != 0 }
    }

    /// Whether the system's screen-sharing daemon is running.
    ///
    /// `screensharingd` is launched on demand for the duration of a session
    /// and is not an application, so it is invisible to `NSWorkspace`; the
    /// process table is the only public place it shows up.
    private static func isScreenBeingShared() -> Bool {
        runningProcessNames().contains("screensharingd")
    }

    /// Every running process's short name.
    ///
    /// Read through `sysctl(KERN_PROC_ALL)` rather than `proc_listallpids` +
    /// `proc_name`: the latter cannot name a process it lacks privileges to
    /// inspect, and on this system that silently hides 212 of 665 pids —
    /// including every root daemon, which is exactly the category
    /// `screensharingd` falls into. `sysctl` returns `p_comm` for all of them.
    ///
    /// `p_comm` is truncated to `MAXCOMLEN` (16) characters; the names matched
    /// here are shorter than that.
    private static func runningProcessNames() -> Set<String> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        // Ask for headroom: the table can grow between sizing and reading.
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 16
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &processes, &size, nil, 0) == 0 else {
            return []
        }

        var names = Set<String>()
        for index in 0 ..< (size / MemoryLayout<kinfo_proc>.stride) {
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
}
