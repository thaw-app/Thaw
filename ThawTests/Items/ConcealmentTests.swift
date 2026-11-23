//
//  ConcealmentTests.swift
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

    @Test("An item hidden now keeps its saved picture for the stable age, though it was saved while visible")
    func hiddenNowAgesAsStable() {
        let loaded = ConcealedCapturePersistence.loadClassifications(
            [hidden.tagIdentifier: .occasional, visible.tagIdentifier: .occasional],
            hiddenIdentifiers: [hidden.tagIdentifier]
        )
        #expect(loaded[hidden.tagIdentifier] == .stable)
        #expect(loaded[visible.tagIdentifier] == .occasional)
    }

    @Test("An item hidden now with no volatility record still ages as stable")
    func hiddenNowWithoutRecordAgesAsStable() {
        let loaded = ConcealedCapturePersistence.loadClassifications([:], hiddenIdentifiers: [hidden.tagIdentifier])
        #expect(loaded[hidden.tagIdentifier] == .stable)
    }
}

@Suite("Concealed order guard")
struct ConcealedOrderGuardTests {
    /// The table from the report: a Hidden re-space renumbered WiFi, Thaw Space and Widgets past the
    /// Always Hidden divider (439), and the next launch read them as Always Hidden.
    private let before = ["flux": 429, "wifi": 322, "space": 321, "widgets": 295, "passwords": 300, "alwaysHiddenDivider": 439]
    private let after = ["flux": 953, "wifi": 853, "space": 753, "widgets": 453, "passwords": 153, "alwaysHiddenDivider": 439]

    @Test("A write that renumbers another section's items is undone, members included")
    func undoesCrossSectionWrite() throws {
        let restored = try #require(ConcealedOrderGuard.rollback(
            changed: ["flux", "wifi", "space", "widgets", "passwords"],
            memberKeys: ["flux", "passwords"],
            before: before,
            current: after
        ))
        #expect(restored == before)
    }

    @Test("A write that changes only the section's own items stands")
    func keepsMemberOnlyWrite() {
        #expect(ConcealedOrderGuard.rollback(
            changed: ["flux", "passwords"],
            memberKeys: ["flux", "passwords"],
            before: before,
            current: after
        ) == nil)
    }

    @Test("An empty write needs nothing undone")
    func ignoresEmptyWrite() {
        #expect(ConcealedOrderGuard.rollback(changed: [], memberKeys: ["flux"], before: before, current: before) == nil)
    }

    @Test("Undoing keeps keys the write didn't touch as they are now, and removes keys it added")
    func restoresOnlyChangedKeys() throws {
        let current = ["flux": 953, "wifi": 853, "clock": 10, "added": 77]
        let restored = try #require(ConcealedOrderGuard.rollback(
            changed: ["flux", "wifi", "added"],
            memberKeys: ["flux"],
            before: ["flux": 429, "wifi": 322, "clock": 12],
            current: current
        ))
        #expect(restored == ["flux": 429, "wifi": 322, "clock": 10])
    }
}

/// The concealment sets hold canonical keys, so a raw identifier must be canonicalized before the lookup.
@Suite("Item concealment")
struct ItemConcealmentTests {
    private let bundle = "com.bjango.istatmenus-setapp.status"

    @Test("An item whose title ticks is found under its canonical key")
    func dynamicTitleMatchesCanonicalKey() {
        let concealed: Set = ["\(bundle):CPU #%"]
        #expect(ItemConcealment.isConcealed("\(bundle):CPU 42%", in: concealed))
        #expect(ItemConcealment.isConcealed("\(bundle):CPU 43%", in: concealed))
    }

    @Test("An item outside the set is not concealed")
    func otherItemIsNotConcealed() {
        let concealed: Set = ["\(bundle):CPU #%"]
        #expect(!ItemConcealment.isConcealed("com.example.App:Item-0", in: concealed))
        #expect(!ItemConcealment.isConcealed("\(bundle):CPU 42%", in: []))
    }

    @Test("A plain identifier matches itself")
    func plainIdentifierMatches() {
        #expect(ItemConcealment.isConcealed("com.example.App:Item-0", in: ["com.example.App:Item-0"]))
    }
}
