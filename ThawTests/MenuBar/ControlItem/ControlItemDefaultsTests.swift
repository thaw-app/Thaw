//
//  ControlItemDefaultsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// AppKit's per-status-item keys as the control items seed and correct them, in a throwaway suite.
@MainActor
@Suite("Control item defaults", .serialized, .scratchDefaults)
struct ControlItemDefaultsTests {
    private let visible = ControlItemIdentifier.visible.rawValue
    private let hidden = ControlItemIdentifier.hidden.rawValue
    private let alwaysHidden = ControlItemIdentifier.alwaysHidden.rawValue

    @Test("Keys use AppKit's NSStatusItem naming")
    func keyNames() {
        #expect(ControlItemDefaults.Key<CGFloat>.preferredPosition.stringKey(for: "X") == "NSStatusItem Preferred Position X")
        #expect(ControlItemDefaults.Key<Bool>.visible.stringKey(for: "X") == "NSStatusItem Visible X")
        #expect(ControlItemDefaults.Key<Bool>.visibleCC.stringKey(for: "X") == "NSStatusItem VisibleCC X")
        #expect(ControlItemDefaults.Key<CGFloat>.preferredPosition.isPreferredPosition)
        #expect(!ControlItemDefaults.Key<Bool>.visible.isPreferredPosition)
    }

    @Test("Values round-trip, except a placement written for a section divider")
    func subscriptWrites() {
        ControlItemDefaults[.visible, "Other"] = false
        ControlItemDefaults[.preferredPosition, "Other"] = 42
        #expect(ControlItemDefaults[.visible, "Other"] == false)
        #expect(ControlItemDefaults[.preferredPosition, "Other"] == 42)
        #expect(Defaults.store.object(forKey: "NSStatusItem Preferred Position Other") as? CGFloat == 42)

        ControlItemDefaults[.preferredPosition, hidden] = 7
        ControlItemDefaults[.preferredPosition, alwaysHidden] = 7
        #expect(ControlItemDefaults[.preferredPosition, hidden] == nil)
        #expect(ControlItemDefaults[.preferredPosition, alwaysHidden] == nil)

        ControlItemDefaults[.visible, "Other"] = nil
        #expect(ControlItemDefaults[.visible, "Other"] == nil)
    }

    @Test("Only the hidden and always-hidden items are section dividers")
    func dividers() {
        #expect(ControlItemDefaults.isSectionDivider(autosaveName: hidden))
        #expect(ControlItemDefaults.isSectionDivider(autosaveName: alwaysHidden))
        #expect(!ControlItemDefaults.isSectionDivider(autosaveName: visible))
        #expect(!ControlItemDefaults.isSectionDivider(autosaveName: "Other"))
    }

    @Test("Migrating moves a value to the new name and clears the old one")
    func migrate() {
        ControlItemDefaults[.visible, "Old"] = false
        ControlItemDefaults.migrate(key: .visible, from: "Old", to: "New")
        #expect(ControlItemDefaults[.visible, "New"] == false)
        #expect(ControlItemDefaults[.visible, "Old"] == nil)

        ControlItemDefaults.migrate(key: .visible, from: "New", to: "New")
        #expect(ControlItemDefaults[.visible, "New"] == false, "migrating onto the same name keeps the value")
    }

    @Test("The Thaw icon is published and a non-positive placement is handed back to the system")
    func prepareVisible() {
        ControlItemDefaults[.visible, visible] = false
        ControlItemDefaults[.preferredPosition, visible] = 0
        ControlItemDefaults.prepareDefaults(for: .visible)
        #expect(ControlItemDefaults[.visible, visible] == true)
        #expect(ControlItemDefaults[.visibleCC, visible] == true)
        #expect(ControlItemDefaults[.preferredPosition, visible] == nil)

        ControlItemDefaults[.preferredPosition, visible] = 120
        ControlItemDefaults.prepareDefaults(for: .visible)
        #expect(ControlItemDefaults[.preferredPosition, visible] == 120, "a real placement is kept")
    }

    @Test("The hidden divider is published without a stored placement")
    func prepareHidden() {
        ControlItemDefaults[.visible, hidden] = false
        ControlItemDefaults.prepareDefaults(for: .hidden)
        #expect(ControlItemDefaults[.visible, hidden] == true)
        #expect(ControlItemDefaults[.visibleCC, hidden] == true)
        #expect(ControlItemDefaults[.preferredPosition, hidden] == nil)
    }

    @Test("The always-hidden divider is published once, and a later hide is respected")
    func prepareAlwaysHidden() {
        ControlItemDefaults.prepareDefaults(for: .alwaysHidden)
        #expect(ControlItemDefaults[.visible, alwaysHidden] == true)
        #expect(ControlItemDefaults[.visibleCC, alwaysHidden] == true)

        ControlItemDefaults[.visible, alwaysHidden] = false
        ControlItemDefaults.prepareDefaults(for: .alwaysHidden)
        #expect(ControlItemDefaults[.visible, alwaysHidden] == false)
    }
}
