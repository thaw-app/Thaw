//
//  HeldItemReveals.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Items other apps asked to keep shown with thaw://reveal-item?hold=true. An item hides when its last holder
/// lets go, and a module that quits lets go of everything, so a crash can't leave items stuck in view.
@MainActor
final class HeldItemReveals {
    /// The app's held reveals, for the paths that conceal an item on their
    /// own, such as a click from the Thaw Bar, and must leave a held one shown.
    private(set) static weak var current: HeldItemReveals?

    private let reveal: (String) -> Void
    private let conceal: (String) -> Void
    private var holders: [String: Set<String>] = [:]

    init(reveal: @escaping (String) -> Void, conceal: @escaping (String) -> Void) {
        self.reveal = reveal
        self.conceal = conceal
    }

    func isHeld(_ identifier: String) -> Bool {
        holders[identifier] != nil
    }

    /// Whether a path that conceals an item on its own may conceal this one.
    /// No holds at all, as before anything was held, never stand in the way.
    static func mayConceal(_ identifier: String, holds: HeldItemReveals?) -> Bool {
        holds?.isHeld(identifier) != true
    }

    /// Makes these the holds the other conceal paths respect.
    func makeCurrent() {
        Self.current = self
    }

    /// The items held for anyone, so a release can find the one it names.
    var heldIdentifiers: [String] {
        Array(holders.keys)
    }

    /// Shows the item on every hold, not only the first: a click or another
    /// reveal may have hidden it since, and a new hold should bring it back.
    func hold(_ identifier: String, for sender: String) {
        holders[identifier, default: []].insert(sender)
        reveal(identifier)
    }

    func release(_ identifier: String, for sender: String) {
        guard var current = holders[identifier], current.remove(sender) != nil else { return }
        if current.isEmpty {
            holders[identifier] = nil
            conceal(identifier)
        } else {
            holders[identifier] = current
        }
    }

    /// Lets go of every item one sender held, as when the sender quits.
    func releaseAll(for sender: String) {
        for identifier in holders.keys.sorted() where holders[identifier]?.contains(sender) == true {
            release(identifier, for: sender)
        }
    }
}

@MainActor
extension MenuBarSectionControlling {
    /// Conceals a temporarily revealed item now, unless a module holds it
    /// shown with thaw://reveal-item?hold=true.
    func concealTemporarilyRevealedItemUnlessHeld(_ identifier: String, holds: HeldItemReveals? = .current) {
        guard HeldItemReveals.mayConceal(identifier, holds: holds) else { return }
        concealTemporarilyRevealedItem(identifier)
    }

    /// Schedules the re-concealment of a temporarily revealed item, unless a
    /// module holds it shown.
    func scheduleTemporaryItemConcealUnlessHeld(_ identifier: String, holds: HeldItemReveals? = .current) {
        guard HeldItemReveals.mayConceal(identifier, holds: holds) else { return }
        scheduleTemporaryItemConceal(identifier)
    }
}
