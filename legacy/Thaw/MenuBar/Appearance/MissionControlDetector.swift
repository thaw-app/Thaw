//
//  MissionControlDetector.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import Observation

/// Detects whether Mission Control or App Exposé is currently active.
///
/// Polls the on-screen position of a tiny invisible probe window against its
/// at-rest position. The window server moves the window in Mission Control
/// without telling AppKit, so the real bounds come from
/// Bridging.getWindowBounds(for:).
///
/// One probe serves the whole app because Mission Control displaces every
/// window together. Not verified on multiple displays; if displays move
/// independently, probe one window per screen.
///
/// ## Known limitation: display changes while Mission Control is open
///
/// A display change clears the baseline, and the next tick re-latches it. If
/// that happens inside Mission Control, the displaced position becomes "at
/// rest" and isActive stays wrongly true until the next display change. The
/// likely fix is comparing actual bounds (top-left origin) against the
/// AppKit frame (bottom-left origin) instead of sampling a baseline.
@MainActor
@Observable
final class MissionControlDetector {
    /// The polling interval while nothing suggests Mission Control is
    /// starting or ending.
    ///
    /// Bounds detection latency from idle (about idleInterval + 0.1s), since
    /// Mission Control does not fire activeSpaceDidChangeNotification.
    static let idleInterval: TimeInterval = 0.2

    /// The polling interval while isActive is true, or for
    /// activeSignalWindow seconds after a step-up signal. Fast enough to
    /// track the enter/exit animation without visible lag.
    static let activeInterval: TimeInterval = 0.1

    /// How long after a step-up signal the probe stays at activeInterval.
    /// Step-up signals are a space change and tick() first seeing
    /// displacement; a plain Mission Control activation only triggers the
    /// latter.
    static let activeSignalWindow: TimeInterval = 2.0

    /// A Boolean value that indicates whether Mission Control or App
    /// Exposé is currently believed to be active.
    private(set) var isActive = false

    /// nil when the detector is stopped.
    private var probeWindow: NSPanel?

    /// The probe window's origin outside Mission Control.
    private var probeAtRestOrigin: CGPoint?

    private var missionControlDisplacedSince: Date?

    /// The last hint that Mission Control might be starting or ending.
    /// Drives the adaptive poll rate.
    private var lastStepUpSignal: Date?

    private var cancellables = Set<AnyCancellable>()

    private var pollTask: Task<Void, Never>?

    var isRunning: Bool {
        probeWindow != nil
    }

    /// Starts the detector, if not already running.
    ///
    /// - Parameter representativeScreen: The screen for the probe window.
    ///   Any screen works, since Mission Control moves every window.
    func start(representativeScreen: NSScreen) {
        guard probeWindow == nil else {
            return
        }

        let window = Self.makeProbeWindow(on: representativeScreen)
        probeWindow = window
        window.orderFrontRegardless()

        configureCancellables()
        schedulePoll()
    }

    /// Stops the detector and releases the probe window.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        cancellables.removeAll()
        probeWindow?.close()
        probeWindow = nil
        probeAtRestOrigin = nil
        missionControlDisplacedSince = nil
        lastStepUpSignal = nil
        if isActive {
            isActive = false
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Step-up signal: a space change often brackets Mission Control
        // entry/exit, so treat it as a reason to poll fast for a bit.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.lastStepUpSignal = Date()
            }
            .store(in: &c)

        // Re-latch the baseline after a display change; a stale one can
        // wedge isActive true forever. Also a step-up signal.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                probeAtRestOrigin = nil
                missionControlDisplacedSince = nil
                lastStepUpSignal = Date()
            }
            .store(in: &c)

        cancellables = c
    }

    private func schedulePoll() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                let interval = Self.nextInterval(
                    isActive: self.isActive,
                    lastStepUpSignal: self.lastStepUpSignal,
                    now: Date()
                )
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Chooses the next polling interval. Pure so it can be unit-tested.
    static func nextInterval(
        isActive: Bool,
        lastStepUpSignal: Date?,
        now: Date
    ) -> TimeInterval {
        if isActive {
            return activeInterval
        }
        if let lastStepUpSignal, now.timeIntervalSince(lastStepUpSignal) < activeSignalWindow {
            return activeInterval
        }
        return idleInterval
    }

    private func tick() {
        guard let probeWindow else {
            return
        }
        guard let windowID = MenuBarItemManager.windowServerID(
            windowNumber: probeWindow.windowNumber
        ) else {
            return
        }
        guard let actualBounds = Bridging.getWindowBounds(for: windowID) else {
            // Don't keep asserting active without bounds, or every overlay
            // stays suppressed if the query never succeeds again.
            missionControlDisplacedSince = nil
            if isActive {
                isActive = false
            }
            return
        }
        let actualOrigin = actualBounds.origin

        // Capture the "at-rest" origin when we're reasonably sure we're not in Mission Control
        if probeAtRestOrigin == nil {
            probeAtRestOrigin = actualOrigin
            return
        }

        guard let atRest = probeAtRestOrigin else {
            return
        }

        let displaced = abs(actualOrigin.x - atRest.x) > 1.0 &&
            abs(actualOrigin.y - atRest.y) > 1.0

        let now = Date()

        if displaced {
            if let displacedSince = missionControlDisplacedSince {
                if now.timeIntervalSince(displacedSince) > 0.1 {
                    isActive = true
                }
            } else {
                missionControlDisplacedSince = now
                // Step up now so the confirming tick comes 0.1s later, not
                // after a full idleInterval.
                lastStepUpSignal = now
            }
        } else {
            missionControlDisplacedSince = nil
            isActive = false
        }
    }

    /// Creates the probe window. It must not be stationary, so Mission
    /// Control moves it.
    private static func makeProbeWindow(on screen: NSScreen) -> NSPanel {
        let window = NSPanel(
            contentRect: CGRect(x: screen.frame.midX, y: screen.frame.midY, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.alphaValue = 0.0
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        // Specifically NOT .stationary or .transient to allow movement.
        // .ignoresCycle and .fullScreenAuxiliary help hide the 'Thaw' label.
        window.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        // Low enough for Mission Control to arrange (both axes move).
        // Positioned at screen center so MC grid displaces it in both x and y.
        window.level = .floating
        return window
    }
}
