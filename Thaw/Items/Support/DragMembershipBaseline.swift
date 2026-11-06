//
//  DragMembershipBaseline.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// What the stored weights read as when the user's ⌘-drag started, so the read after the drop adopts only what it moved.
/// Quick successive drags share the first drag's reading, and one read after the last drop covers them all.
@MainActor
final class DragMembershipBaseline<Baseline> {
    /// Reads the stored weights now; nil when they can't be read in order.
    var read: () -> Baseline? = { nil }

    /// Cancels a membership read still waiting from an earlier drag.
    var cancelPendingRead: () -> Void = {
        // Nothing is pending until the owner supplies a read that can be cancelled.
    }

    private(set) var baseline: Baseline?

    /// The items the user grabbed in these drags. A drop shifts the stored weights of
    /// its neighbours too, so only these may change section. Nil once a drag started
    /// on an item that couldn't be named, which leaves every crossing item eligible.
    private(set) var pressed: Set<MenuBarItemTag>? = []

    func dragStarted(pressing tag: MenuBarItemTag? = nil) {
        cancelPendingRead()
        if let tag {
            pressed?.insert(tag)
        } else {
            pressed = nil
        }
        guard baseline == nil else { return }
        baseline = read()
    }

    func clear() {
        baseline = nil
        pressed = []
    }
}
