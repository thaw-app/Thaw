//
//  MenuBarOverlayProbe.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel

/// Detects Mission Control / App Exposé by watching a tiny probe window.
///
/// The window is not stationary, so Mission Control's grid displaces it from
/// its at-rest origin.
@MainActor
final class MissionControlShieldProbe {
    /// A Boolean value that indicates whether Mission Control or App Expose is
    /// active. Published so the panel can fade in step with it.
    @Published var isActive = false

    /// Answers whether the panel still wants the probe polled.
    var shouldRun: (() -> Bool)?

    private let owningScreen: NSScreen

    /// A tiny invisible window that Mission Control moves.
    private lazy var window: NSPanel = {
        let window = NSPanel(
            contentRect: CGRect(x: owningScreen.frame.midX, y: owningScreen.frame.midY, width: 1, height: 1),
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
        // Not .stationary or .transient, so it can move. These two hide the
        // 'Thaw' label.
        window.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        // Low enough for Mission Control to arrange; centred so both axes move.
        window.level = .floating
        return window
    }()

    /// The origin of the probe window when it is at rest (not in Mission Control).
    private var atRestOrigin: CGPoint?

    /// When the probe was last seen at rest, or nil while displaced or
    /// calibrating. Drives the back-off in tickInterval(atRestFor:).
    private var atRestSince: Date?

    /// The time when the probe window first became displaced.
    private var displacedSince: Date?

    /// When the Exposé shield was last looked for. The scan walks every
    /// on-screen window and reveal-desktop can last indefinitely, so it is rationed.
    private var shieldCheckedAt: Date?

    /// The poll subscription, alive only while shouldRun holds.
    private var cancellable: AnyCancellable?

    /// The least time between two Exposé shield scans while the probe stays
    /// displaced.
    private static let shieldCheckInterval: TimeInterval = 1.0

    /// The rate the probe polls at while its answer might be changing:
    /// displaced, calibrating, or only briefly settled.
    static nonisolated let activeInterval: TimeInterval = 0.1

    /// The rate once the probe has been at rest for restSettleInterval: a fifth
    /// of the wakeups, catching Mission Control within half a second.
    static nonisolated let restInterval: TimeInterval = 0.5

    /// How long the probe must sit exactly at rest before its poll slows from
    /// activeInterval to restInterval.
    static nonisolated let restSettleInterval: TimeInterval = 2.0

    init(owningScreen: NSScreen) {
        self.owningScreen = owningScreen
    }

    /// Orders the probe window on screen so the window server can move it.
    func start() {
        window.orderFrontRegardless()
    }

    /// Clears the calibrated at-rest origin so the next tick re-reads it.
    func reset() {
        atRestOrigin = nil
    }

    /// Stops polling and closes the probe window.
    func close() {
        stopPolling()
        window.close()
    }

    /// Starts or stops the poll to match isWanted.
    ///
    /// Each tick is a window-server round trip, so the poll runs only while a
    /// panel needs it.
    func updatePolling(isWanted: Bool) {
        if isWanted {
            guard cancellable == nil else { return }
            // Start on the active rate: a displacement can follow immediately.
            atRestSince = nil
            cancellable = poll(every: Self.activeInterval)
        } else {
            stopPolling()
        }
    }

    private func stopPolling() {
        // A tick can end its own poll, so cancel on the next main-queue turn
        // rather than release the closure that is still running.
        guard let current = cancellable else { return }
        cancellable = nil
        DispatchQueue.main.async {
            current.cancel()
        }
    }

    /// Watches the probe window for displacement. Each tick may swap itself
    /// for a different rate through restartPolling(at:).
    private func poll(every interval: TimeInterval) -> AnyCancellable {
        Timer.publish(every: interval, tolerance: interval / 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                tick(interval: interval)
            }
    }

    private func tick(interval: TimeInterval) {
        // Covers a tick landing before the deferred cancel takes effect.
        guard shouldRun?() ?? false else { return }
        // Negative while the probe window is not ordered in, and CGWindowID
        // traps on that rather than reporting it.
        guard let windowID = CGWindowID(exactly: window.windowNumber) else { return }
        guard let actualBounds = Bridging.getWindowBounds(for: windowID) else { return }
        let actualOrigin = actualBounds.origin

        if atRestOrigin == nil {
            atRestOrigin = actualOrigin
            return
        }

        guard let atRest = atRestOrigin else { return }

        let isDisplaced = abs(actualOrigin.x - atRest.x) > 1.0 &&
            abs(actualOrigin.y - atRest.y) > 1.0

        let now = Date()
        var restDuration: TimeInterval?

        if isDisplaced {
            atRestSince = nil
            if let displacedSince {
                // "Click wallpaper to reveal desktop" also displaces the probe
                // but raises no Exposé shield, and the bar must keep its look,
                // so confirm the shield before fading. Rechecked at most once a second.
                let shouldCheckShield = !isActive
                    && now.timeIntervalSince(displacedSince) > 0.1
                    && shieldCheckedAt.map {
                        now.timeIntervalSince($0) >= Self.shieldCheckInterval
                    } ?? true
                if shouldCheckShield {
                    shieldCheckedAt = now
                    isActive = Self.isShieldPresent()
                }
            } else {
                self.displacedSince = now
            }
        } else {
            displacedSince = nil
            shieldCheckedAt = nil
            isActive = false
            if let since = atRestSince {
                restDuration = now.timeIntervalSince(since)
            } else {
                atRestSince = now
            }
        }

        let nextInterval = Self.tickInterval(atRestFor: restDuration)
        if nextInterval != interval {
            restartPolling(at: nextInterval)
        }
    }

    /// Swaps the running poll for one ticking at interval.
    ///
    /// The replaced subscription may be the caller, so its cancel is deferred.
    private func restartPolling(at interval: TimeInterval) {
        guard let current = cancellable else { return }
        cancellable = poll(every: interval)
        DispatchQueue.main.async {
            current.cancel()
        }
    }

    /// Whether WindowManager's Exposé shield is on screen. Mission Control
    /// raises one per display; reveal-desktop never does.
    private static func isShieldPresent() -> Bool {
        WindowInfo.createWindows(option: .onScreen).contains { window in
            isShieldWindow(ownerName: window.ownerName, title: window.title)
        }
    }

    /// Pure classification of the Exposé shield window, split out so it can be
    /// unit-tested without a live window server.
    static nonisolated func isShieldWindow(ownerName: String?, title: String?) -> Bool {
        ownerName == "WindowManager" && title == "ExposeShieldWindow"
    }

    /// How often the probe window is read, given how long it has sat exactly
    /// where it was left.
    ///
    /// The active rate until the probe has rested for restSettleInterval; the
    /// cost is noticing Mission Control up to half a second late after that.
    static nonisolated func tickInterval(atRestFor restDuration: TimeInterval?) -> TimeInterval {
        guard let restDuration,
              restDuration >= restSettleInterval
        else {
            return activeInterval
        }
        return restInterval
    }
}
