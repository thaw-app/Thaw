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
