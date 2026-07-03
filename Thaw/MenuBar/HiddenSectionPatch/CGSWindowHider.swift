//
//  CGSWindowHider.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Hides menu-bar items by moving their windows off-screen via private CGS
/// APIs — a per-window, surgical hide that never
/// re-composites the whole menu bar.
///
/// This is a *complement* to ``AssessmentModeBackend``, not a replacement. The
/// assessment-mode assertion is the right tool for Apple system items (Control
/// Center modules, Clock, Siri …), but every (re)activation reflows the entire
/// bar, which leaves dynamic third-party neighbors — iStat above all — as
/// on-band ghosts (frame present, no glyph). Moving a *third-party* item's own
/// window off-screen instead touches only that window, so neighbors keep their
/// glyphs and items the assertion can't attribute (apps run from non-canonical
/// locations) are reachable anyway.
///
/// macOS 27 carries *synthetic* per-item window IDs internally, so this resolves
/// each owning process to its real menu-bar window IDs via
/// ``Bridging/getMenuBarWindowIDs(forProcess:)`` at apply time.
///
/// Safety: every moved window's original origin is remembered and restored when
/// the process leaves the hidden set, and ``restoreAll()`` runs on app
/// termination so a hide never outlives Thaw (a stranded status item would
/// otherwise sit invisibly off-screen until its app relaunched).
@MainActor
final class CGSWindowHider {
    /// Injectable side effects so tests can drive the bookkeeping without a live
    /// window server.
    @MainActor
    struct Environment {
        let menuBarWindowIDs: @MainActor (pid_t) -> [CGWindowID]
        let windowOrigin: @MainActor (CGWindowID) -> CGPoint?
        let moveWindow: @MainActor (CGWindowID, CGPoint) -> Bool

        static var live: Environment {
            Environment(
                menuBarWindowIDs: { Bridging.getMenuBarWindowIDs(forProcess: $0) },
                windowOrigin: { Bridging.getWindowBounds(for: $0)?.origin },
                moveWindow: { Bridging.moveWindow($0, to: $1) }
            )
        }
    }

    /// X coordinate far outside any plausible display arrangement. Items moved
    /// here are off every screen but still valid windows we can move back.
    static let offScreenX: CGFloat = -30000

    private let diagLog = DiagLog(category: "CGSWindowHider")
    private let environment: Environment

    /// Original origin of every window this hider has moved off-screen, keyed by
    /// real window ID. Presence == "currently hidden by us".
    private var hiddenOrigins: [CGWindowID: CGPoint] = [:]

    private var terminationObserver: NSObjectProtocol?

    init(
        environment: Environment = .live,
        notificationCenter: NotificationCenter = .default
    ) {
        self.environment = environment
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreAll() }
        }
    }

    isolated deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    /// Drives the off-screen hide to match `hiddenPIDs`: every menu-bar window of
    /// a listed process is moved off-screen, and any window we previously hid for
    /// a process no longer listed is restored. Safe to call every refresh tick —
    /// it re-applies the off-screen move to windows the system may have reflowed
    /// back on-screen, and is a no-op once everything is settled.
    ///
    /// - Returns: The subset of `hiddenPIDs` for which at least one window was
    ///   resolved and handled. Callers should only strip these PIDs from the
    ///   assertion input; PIDs that had no windows (e.g. macOS 27 where items
    ///   are drawn into shared hosting windows) must fall back to the assertion.
    @discardableResult
    func apply(hiddenPIDs: Set<pid_t>) -> Set<pid_t> {
        // Resolve the live windows that should be hidden right now.
        var desiredHidden = Set<CGWindowID>()
        var handledPIDs = Set<pid_t>()
        for pid in hiddenPIDs {
            let wids = environment.menuBarWindowIDs(pid)
            if !wids.isEmpty {
                handledPIDs.insert(pid)
                desiredHidden.formUnion(wids)
            }
        }

        var changed = false

        // Restore windows that should no longer be hidden.
        for (windowID, origin) in hiddenOrigins where !desiredHidden.contains(windowID) {
            if environment.moveWindow(windowID, origin) {
                changed = true
            }
            hiddenOrigins.removeValue(forKey: windowID)
        }

        // Hide (or re-hide after a reflow) every desired window.
        for windowID in desiredHidden {
            if hiddenOrigins[windowID] == nil {
                // First time hiding this window — remember where it lives so it
                // can be restored exactly. Skip if we can't read its origin
                // (don't move a window we can't put back).
                guard let origin = environment.windowOrigin(windowID) else {
                    diagLog.error("Skipping hide of window \(windowID); origin unavailable")
                    continue
                }
                hiddenOrigins[windowID] = origin
            } else if let origin = environment.windowOrigin(windowID), origin.x > Self.offScreenX / 2 {
                // The window server reflowed it back on-screen; keep the
                // ORIGINAL origin we already stored and just move it off again.
            }
            let target = CGPoint(x: Self.offScreenX, y: hiddenOrigins[windowID]?.y ?? 0)
            if environment.moveWindow(windowID, target) {
                changed = true
            }
        }

        if changed {
            diagLog.debug("apply(hiddenPIDs: \(hiddenPIDs.sorted())): \(hiddenOrigins.count) window(s) off-screen")
        }
        return handledPIDs
    }

    /// Restores every window this hider has moved, used on teardown so no item
    /// is left stranded off-screen.
    func restoreAll() {
        guard !hiddenOrigins.isEmpty else { return }
        for (windowID, origin) in hiddenOrigins {
            environment.moveWindow(windowID, origin)
        }
        diagLog.info("restoreAll: restored \(hiddenOrigins.count) window(s)")
        hiddenOrigins.removeAll()
    }
}
