//
//  ActiveMenuBarDisplayWatcher.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Reports when the active menu bar moves to another display. macOS sends no notification for the move,
/// so app, Space, display and click events ask, and a one-second check catches the rest.
@MainActor
final class ActiveMenuBarDisplayWatcher {
    var onChange: (() -> Void)?
    /// Whether anything depends on the active display right now; the
    /// one-second check skips its read while nothing does.
    var isNeeded: () -> Bool = { true }

    /// How long a throttled check trusts the last answer. The pointer stream
    /// asks on every move, and each read is a round trip to the window server.
    static let throttleInterval: Duration = .milliseconds(100)

    private let readDisplayID: () -> CGDirectDisplayID?
    private var lastDisplayID: CGDirectDisplayID?
    private var lastCheck: ContinuousClock.Instant?
    /// Set by start(), in the +Live file.
    var observers: [any NSObjectProtocol] = []
    var timer: Timer?

    init(readDisplayID: @escaping () -> CGDirectDisplayID? = { Bridging.getActiveMenuBarDisplayID() }) {
        self.readDisplayID = readDisplayID
    }

    /// Reads the active display and reports a change from the last known one.
    /// A throttled check, from the pointer stream, skips the read while the
    /// last one is younger than throttleInterval.
    func check(throttled: Bool = false, now: ContinuousClock.Instant = .now) {
        if throttled, let lastCheck, now - lastCheck < Self.throttleInterval {
            return
        }
        lastCheck = now
        guard let displayID = readDisplayID() else { return }
        defer { lastDisplayID = displayID }
        if let lastDisplayID, lastDisplayID != displayID {
            onChange?()
        }
    }

    /// Reports a display change even on the same display, since a new resolution changes its width.
    func screenParametersChanged() {
        guard let displayID = readDisplayID() else { return }
        lastDisplayID = displayID
        onChange?()
    }
}
