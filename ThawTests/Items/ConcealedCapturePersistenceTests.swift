//
//  ConcealedCapturePersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// A capture of a hidden item is written to disk, so the next launch shows it without a reveal.
@Suite("Concealed capture persistence")
struct ConcealedCapturePersistenceTests {
    private static func tag(_ bundle: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(bundle), title: "Item-0", instanceIndex: 0)
    }

    private let hidden = tag("com.example.hidden")
    private let visible = tag("com.example.visible")

    @Test("A pass that changed a hidden item's image is saved")
    func hiddenChangeSaves() {
        #expect(ConcealedCapturePersistence.shouldSave(
            capturedTags: [visible, hidden], concealedIdentifiers: [hidden.tagIdentifier], imageChanged: { _ in true }
        ))
    }

    @Test("A pass that changed only visible items is not saved, since the live loop refreshes those")
    func visibleChangeDoesNotSave() {
        #expect(!ConcealedCapturePersistence.shouldSave(
            capturedTags: [visible], concealedIdentifiers: [hidden.tagIdentifier], imageChanged: { _ in true }
        ))
    }

    @Test("A pass that changed nothing is not saved")
    func noChangeDoesNotSave() {
        #expect(!ConcealedCapturePersistence.shouldSave(
            capturedTags: [visible, hidden], concealedIdentifiers: [hidden.tagIdentifier], imageChanged: { _ in false }
        ))
    }

    @Test("A hidden item matches by identity, whatever its window ID")
    func matchesIgnoringWindowID() {
        let live = MenuBarItemTag(namespace: .string("com.example.hidden"), title: "Item-0", windowID: 42, instanceIndex: 0)
        #expect(ConcealedCapturePersistence.shouldSave(
            capturedTags: [live], concealedIdentifiers: [hidden.tagIdentifier], imageChanged: { _ in true }
        ))
    }

    @Test("Only hidden items' images are compared, since a comparison can read pixels")
    func comparesOnlyHiddenItems() {
        var compared: [MenuBarItemTag] = []

        _ = ConcealedCapturePersistence.shouldSave(
            capturedTags: [visible, hidden], concealedIdentifiers: [hidden.tagIdentifier],
            imageChanged: { compared.append($0); return false }
        )

        #expect(compared == [hidden])
    }

    @Test("With nothing hidden no image is compared")
    func nothingHiddenComparesNothing() {
        var comparisons = 0

        let saves = ConcealedCapturePersistence.shouldSave(
            capturedTags: [visible, hidden], concealedIdentifiers: [],
            imageChanged: { _ in comparisons += 1; return true }
        )

        #expect(!saves)
        #expect(comparisons == 0)
    }
}
