//
//  RevealCaptureSlot.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import DequeModule
import MenuBarModel

/// The tags one requested capture got a new picture of. Each request owns one.
@MainActor
final class RequestedCaptureTally {
    var tags: Set<MenuBarItemTag> = []
}

/// Lets one concealed prewarm reveal hidden items at a time, since overlapping
/// passes land one's conceal inside the other's screenshot.
@MainActor
final class RevealCaptureSlot {
    /// Whether a prewarm holds the slot.
    private(set) var isHeld = false
    /// The tally of the pass holding the slot. Nil for an automatic pass, so it records nothing.
    private(set) var tally: RequestedCaptureTally?
    /// Prewarms waiting for the running one to finish, first in line first.
    private var waiters = Deque<CheckedContinuation<Void, Never>>()
    /// Runs each time a prewarm takes the slot, so any pass admitted before it goes stale.
    private let onStart: @MainActor () -> Void

    init(onStart: @escaping @MainActor () -> Void = {
        // Nothing to invalidate unless the owner supplies it, as in tests.
    }) {
        self.onStart = onStart
    }

    /// Waits until no other prewarm holds the slot, then takes it and opens its
    /// tally, so a queued request can't touch a running one's. Waiters are resumed in arrival order.
    func begin(tally: RequestedCaptureTally? = nil) async {
        defer {
            self.tally = tally
            onStart()
        }
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the slot straight to the next queued prewarm, so no caller slips in between, or frees it.
    func end() {
        tally = nil
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Whether a recapture pass should skip while Capture Hidden Items runs. Its reveals
    /// count as unhidden, so a pass would crop them while they slide in.
    func standsDown(_ pass: String) -> Bool {
        guard isHeld else { return false }
        MenuBarItemImageCache.diagLog.debug("\(pass): hidden items are being captured; skipping this pass")
        return true
    }
}
