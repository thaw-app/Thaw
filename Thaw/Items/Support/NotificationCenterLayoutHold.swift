//
//  NotificationCenterLayoutHold.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Whether layout work is held because Notification Center is being opened, and which settle
/// may lift the hold.
///
/// Opening Notification Center releases concealment for a moment, and the bar it leaves behind
/// is not one to repair or publish. The hold starts when the bridge opens and ends once a
/// settle has waited the bar out. Each begin issues a new token, so a settle that was started
/// for an earlier begin cannot lift a hold a later one took.
nonisolated struct NotificationCenterLayoutHold {
    private var token: UUID?
    private var settleTask: Task<Void, Never>?

    var isHeld: Bool { token != nil }

    /// Whether a settle has been started and has not yet lifted the hold or been superseded.
    var isSettling: Bool { settleTask != nil }

    /// Takes the hold, or renews it, and cancels any settle that was waiting to lift it.
    /// Returns true when nothing was held before.
    @discardableResult
    mutating func begin() -> Bool {
        settleTask?.cancel()
        settleTask = nil
        let wasHeld = isHeld
        token = UUID()
        return !wasHeld
    }

    /// Replaces any waiting settle with the one start returns. start is handed the token of
    /// the hold as it stands, to pass to release(ifCurrent:) once the wait is over.
    mutating func settle(_ start: (UUID?) -> Task<Void, Never>) -> Task<Void, Never> {
        let token = token
        settleTask?.cancel()
        let task = start(token)
        settleTask = task
        return task
    }

    /// Lifts the hold if the token is still the current one, and reports whether it did.
    @discardableResult
    mutating func release(ifCurrent token: UUID?) -> Bool {
        guard let token, self.token == token else { return false }
        self.token = nil
        settleTask = nil
        return true
    }
}
