//
//  MenuBarItemAXProvider+AccessRefusals.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import os.lock
import ThawAXCore

/// Which apps keep refusing this process's Accessibility reads. See AccessRefusalLedger.
nonisolated extension MenuBarItemAXProvider {
    private static let accessRefusals = OSAllocatedUnfairLock(initialState: AccessRefusalLedger())

    /// The raw result of reading an app's extras bar, recorded as a refusal or an answer.
    static func recordedExtrasBarRead(pid: pid_t) -> AXError {
        let result = AXPrimitives.extrasMenuBarReadResult(pid: pid)
        noteAccessAnswer(result, from: pid)
        return result
    }

    /// Records how an app that had menu bar items before answered the read of its extras bar.
    static func noteAccessAnswer(_ result: AXError, from pid: pid_t, now: ContinuousClock.Instant = .now) {
        accessRefusals.withLock { ledger in
            if result == .apiDisabled {
                ledger.refused(pid, at: now)
            } else {
                ledger.answered(pid)
            }
        }
    }

    /// The running apps that have refused for a while and still refuse when asked again now, off the main thread.
    /// The ledger alone can be old: the walk stops reading an app's raw answer once the app gives items.
    static func persistentAccessRefusers(
        running: Set<pid_t>,
        now: ContinuousClock.Instant = .now,
        read: @escaping @Sendable (pid_t) -> AXError = { AXPrimitives.extrasMenuBarReadResult(pid: $0) }
    ) async -> Set<pid_t> {
        let candidates = accessRefusals.withLock { ledger in
            ledger.retain(running: running)
            return ledger.refusers(lasting: AccessRefusalRecovery.minimumDuration, now: now)
        }
        guard candidates.count >= AccessRefusalRecovery.minimumOwners else { return [] }
        let answers = await onReadQueue { candidates.map { ($0, read($0)) } }
        for (pid, result) in answers {
            noteAccessAnswer(result, from: pid, now: now)
        }
        return Set(answers.filter { $0.1 == .apiDisabled }.map(\.0))
    }
}
