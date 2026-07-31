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
///
/// ## Known limitation: display changes while Mission Control is open
///
/// `didChangeScreenParametersNotification` clears `probeAtRestOrigin` so the
/// baseline gets re-latched, but re-latching just adopts whatever origin the
/// next `tick()` observes. If a display reconfiguration happens *while*
/// Mission Control is open, that tick latches the **displaced** position as
/// "at rest". Mission Control then exits, the probe returns to its true
/// resting position, and the detector reads that as displacement — a
/// false-positive `isActive` that persists until the next display change.
/// This is much narrower than the Step 1 bug (which never re-latched at
/// all, so it stayed wedged forever), but it's real and worth knowing about.
/// The likely root fix is to stop sampling a baseline entirely and instead
/// compare the probe window's actual bounds against its own AppKit
/// `frame.origin`, which per this type's own premise never moves under
/// Mission Control. That requires a coordinate-space conversion —
/// `Bridging.getWindowBounds` is top-left origin (window server/Core
/// Graphics), `NSWindow.frame` is bottom-left origin (AppKit) — and can't be
/// validated without running the app, so it's out of scope here.
@MainActor
@Observable
final class MissionControlDetector {
    /// The polling interval used while nothing suggests Mission Control
    /// might be starting or ending.
    ///
    /// This is the term that bounds how long it takes to *notice*
    /// displacement has started at all — no step-up signal can help here,
    /// since Mission Control does not change the active space and so does
    /// not fire `activeSpaceDidChangeNotification`. Combined with the 0.1s
    /// confirmation debounce in `tick()`, the worst-case time to flip
    /// `isActive` to `true` from a cold idle state is roughly
    /// `idleInterval + 0.1`. Kept close to the old fixed 10 Hz rate's
    /// ~0.2s detection latency rather than trading detection speed for
    /// idle-cost savings; the bulk of the win in this type is already
    /// banked by going from one probe per panel to one for the whole app.
    static let idleInterval: TimeInterval = 0.2

    /// The polling interval used while `isActive` is `true`, or for
    /// `activeSignalWindow` seconds after a step-up signal. Matches the
    /// fixed rate of the per-panel timer this detector replaces, which
    /// comfortably tracked Mission Control's enter/exit animation without
    /// visible lag.
    static let activeInterval: TimeInterval = 0.1

    /// How long after a step-up signal the probe keeps running at
    /// `activeInterval` before it's allowed to fall back to `idleInterval`.
    /// Step-up signals are `activeSpaceDidChangeNotification` (helps for
    /// Exposé/space-switch cases, but does not fire for a plain Mission
    /// Control activation) and the moment `tick()` first observes
    /// displacement (see `tick()` — this is what actually keeps Mission
    /// Control's confirmation tick and its exit fast, independent of
    /// `idleInterval`).
    static let activeSignalWindow: TimeInterval = 2.0

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

    /// The time of the most recent step-up signal — a notification that
    /// Mission Control might be about to start or end. Drives the adaptive
    /// poll rate; see `nextInterval(isActive:lastStepUpSignal:now:)`.
    private var lastStepUpSignal: Date?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The currently scheduled poll task.
    private var pollTask: Task<Void, Never>?

    /// A Boolean value that indicates whether the detector is currently
    /// running (has an active probe window and poll loop).
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

        // Re-latch the probe's at-rest baseline after a display
        // configuration change (resolution, menu bar height, arrangement).
        // The old baseline no longer reflects the probe window's correct
        // resting position; a stale baseline can wedge the probe into a
        // false-positive "Mission Control active" state that never clears.
        // Also treat it as a step-up signal, since a display change is a
        // reasonable moment to want a quick, accurate re-read.
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

    /// Runs the poll loop, re-scheduling itself with an interval chosen by
    /// `nextInterval(isActive:lastStepUpSignal:now:)` after every tick.
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

    /// Chooses the next polling interval given the current state.
    ///
    /// Pulled out as a pure function (no access to instance state) so the
    /// rate-selection logic can be unit-tested without a live probe window
    /// or task.
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
                // The displacement itself is the best possible step-up
                // signal — better than waiting for an external notification
                // that may never come (Mission Control doesn't change the
                // active space). This gets the confirming tick 0.1s later
                // instead of waiting out a full idleInterval.
                lastStepUpSignal = now
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
