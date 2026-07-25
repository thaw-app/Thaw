//
//  MissionControlDetector.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Cocoa
import Combine
import Observation

/// Detects whether Mission Control or App Exposé is currently active.
///
/// Detection works by polling the on-screen position of a tiny, invisible
/// probe window against the position it was created at ("at rest"). When
/// Mission Control activates, the window server displaces every window on
/// screen — including ours — to arrange it in the Mission Control grid.
/// AppKit's own `frame` does not reflect that displacement (the window
/// server moves the window without telling AppKit), so the actual bounds
/// have to be queried directly through `Bridging.getWindowBounds(for:)`.
///
/// One probe window is enough for the whole app: Mission Control displaces
/// every on-screen window together, so a single representative window is
/// sufficient to detect it for all menu bar overlay panels. This assumption
/// has not been verified against multi-display Mission Control behavior
/// (Steps 4–5 of plan 009 were not run in this environment because they
/// require launching the app). If independent per-display displacement is
/// ever observed, this detector should probe one window per screen instead.
@MainActor
@Observable
final class MissionControlDetector {
    /// The polling interval, in seconds. Matches the fixed rate of the
    /// per-panel timer this detector replaces.
    static let pollInterval: TimeInterval = 0.1

    /// A Boolean value that indicates whether Mission Control or App
    /// Exposé is currently believed to be active.
    private(set) var isActive = false

    /// The probe window used to detect displacement. `nil` when the
    /// detector is stopped (no overlay panels currently need it).
    private var probeWindow: NSPanel?

    /// The origin of the probe window when it is at rest (not in Mission
    /// Control).
    private var probeAtRestOrigin: CGPoint?

    /// The time when the probe window first became displaced.
    private var missionControlDisplacedSince: Date?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// A Boolean value that indicates whether the detector is currently
    /// running (has an active probe window and poll timer).
    var isRunning: Bool {
        probeWindow != nil
    }

    /// Starts the detector, if not already running.
    ///
    /// - Parameter representativeScreen: The screen the probe window is
    ///   created on. Since Mission Control displaces every on-screen window
    ///   together, any screen works — this only affects where the
    ///   (invisible) probe window physically sits.
    func start(representativeScreen: NSScreen) {
        guard probeWindow == nil else {
            return
        }

        let window = Self.makeProbeWindow(on: representativeScreen)
        probeWindow = window
        window.orderFrontRegardless()

        configureCancellables()
    }

    /// Stops the detector and releases the probe window.
    func stop() {
        cancellables.removeAll()
        probeWindow?.close()
        probeWindow = nil
        probeAtRestOrigin = nil
        missionControlDisplacedSince = nil
        if isActive {
            isActive = false
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Poll the mission control probe window to detect if it has moved/scaled.
        Timer.publish(every: Self.pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
            .store(in: &c)

        // Re-latch the probe's at-rest baseline after a display
        // configuration change (resolution, menu bar height, arrangement).
        // The old baseline no longer reflects the probe window's correct
        // resting position; a stale baseline can wedge the probe into a
        // false-positive "Mission Control active" state that never clears.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                probeAtRestOrigin = nil
                missionControlDisplacedSince = nil
            }
            .store(in: &c)

        cancellables = c
    }

    /// Polls the probe window's actual on-screen bounds and updates
    /// `isActive` accordingly.
    private func tick() {
        guard let probeWindow else {
            return
        }
        let windowID = CGWindowID(probeWindow.windowNumber)
        guard let actualBounds = Bridging.getWindowBounds(for: windowID) else {
            // No bounds: we can't observe displacement this tick, so don't
            // keep asserting Mission Control is active — that would
            // suppress every overlay indefinitely if the query never
            // succeeds again.
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
            }
        } else {
            missionControlDisplacedSince = nil
            isActive = false
        }
    }

    /// Creates a tiny, invisible window used to detect Mission Control.
    ///
    /// This window is NOT stationary, so it moves during Mission Control.
    /// By comparing its actual on-screen position with its intended
    /// position, we can reliably detect if Mission Control is active.
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
