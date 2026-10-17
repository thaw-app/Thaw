//
//  LayoutBatchMoveTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Parsing and checking thaw://move-item without a menu bar.
@Suite("Move item URL command")
struct LayoutBatchMoveTests {
    typealias Entry = LayoutBatchMoveSnapshot.Entry

    private func parse(_ string: String) throws -> Result<LayoutBatchMove, LayoutBatchMoveError> {
        try LayoutBatchMove.parse(#require(URL(string: string)))
    }

    private func command(_ string: String) throws -> LayoutBatchMove {
        try parse(string).get()
    }

    private func error(_ string: String) throws -> LayoutBatchMoveError? {
        guard case let .failure(error) = try parse(string) else { return nil }
        return error
    }

    static func entry(
        _ id: String,
        control: Bool = false,
        grouped: Bool = false,
        assignable: Set<MenuBarSectionName> = Set(MenuBarSectionName.allCases),
        reordersInVisible: Bool = true
    ) -> Entry {
        Entry(
            id: id,
            isControlItem: control,
            isGrouped: grouped,
            assignableSections: assignable,
            reordersInVisible: reordersInVisible
        )
    }

    /// Visible holds a, b, c; Hidden holds h1, h2; Always Hidden holds x.
    static let snapshot = LayoutBatchMoveSnapshot(sections: [
        .visible: ["a", "b", "c"].map { entry($0) },
        .hidden: ["h1", "h2"].map { entry($0) },
        .alwaysHidden: [entry("x")],
    ])

    @Test("A single item, a section and an anchor parse")
    func parsesAllParameters() throws {
        let parsed = try command("thaw://move-item?item=com.example.app:Item-0&section=hidden&after=com.example.other:Item-0")
        #expect(parsed.itemIDs == ["com.example.app:Item-0"])
        #expect(parsed.section == .hidden)
        #expect(parsed.afterID == "com.example.other:Item-0")
    }

    @Test("Repeated items keep the order given")
    func repeatedItemsKeepTheirOrder() throws {
        let parsed = try command("thaw://move-item?item=z&item=x&item=y&section=visible")
        #expect(parsed.itemIDs == ["z", "x", "y"])
        #expect(parsed.afterID == nil)
    }

    @Test("Percent-encoded identifiers with colons and spaces are decoded")
    func decodesEncodedIdentifiers() throws {
        let parsed = try command("thaw://move-item?item=com.example.app%3AMy%20Item&section=alwaysHidden&after=com.apple.x%3AWi-Fi%20Menu")
        #expect(parsed.itemIDs == ["com.example.app:My Item"])
        #expect(parsed.section == .alwaysHidden)
        #expect(parsed.afterID == "com.apple.x:Wi-Fi Menu")
    }

    @Test("The section name is matched case-insensitively")
    func sectionCaseIsIgnored() throws {
        #expect(try command("thaw://move-item?item=a&section=AlwaysHidden").section == .alwaysHidden)
    }

    @Test("An empty anchor counts as absent")
    func emptyAnchorIsAbsent() throws {
        #expect(try command("thaw://move-item?item=a&section=visible&after=").afterID == nil)
    }

    @Test("Missing or malformed parameters are refused with the reason")
    func malformedRequestsAreRefused() throws {
        #expect(try error("thaw://move-item?section=visible") == .missingItem)
        #expect(try error("thaw://move-item?item=&section=visible") == .missingItem)
        #expect(try error("thaw://move-item?item=a") == .missingSection)
        #expect(try error("thaw://move-item?item=a&section=") == .missingSection)
        #expect(try error("thaw://move-item?item=a&section=top") == .unknownSection("top"))
        #expect(try error("thaw://move-item?item=a&item=b&item=a&section=visible") == .duplicateItem("a"))
        #expect(try error("thaw://move-item?item=a&item=b&section=visible&after=b") == .anchorIsMovedItem("b"))
    }

    @Test("Every refusal has a stable code and names what is at fault", arguments: [
        (LayoutBatchMoveError.missingItem, "invalidRequest", "item="),
        (.missingSection, "invalidRequest", "section="),
        (.unknownSection("top"), "invalidRequest", "top"),
        (.duplicateItem("a"), "invalidRequest", "a"),
        (.anchorIsMovedItem("a"), "invalidRequest", "a"),
        (.sectionDisabled(.alwaysHidden), "sectionDisabled", "alwaysHidden"),
        (.unknownItem("a"), "itemUnavailable", "a"),
        (.controlItem("a"), "itemNotMovable", "control"),
        (.groupedItem("a"), "itemNotMovable", "group"),
        (.notMovable("a", .hidden), "itemNotMovable", "hidden"),
        (.unknownAnchor("w"), "anchorUnavailable", "w"),
        (.moveRefused, "moveRefused", "declined"),
    ])
    func refusalsDescribeThemselves(error: LayoutBatchMoveError, code: String, mention: String) {
        #expect(error.code == code)
        #expect(error.details.contains(mention))
    }

    @Test("A move without an anchor lands at the target's right end")
    func movesToTheEnd() throws {
        let plan = try command("thaw://move-item?item=h1&section=visible").plan(in: Self.snapshot).get()
        #expect(plan.source == .hidden)
        #expect(plan.target == .visible)
        #expect(plan.previousTargetOrder == ["a", "b", "c"])
        #expect(plan.targetOrder == ["a", "b", "c", "h1"])
        #expect(!plan.changesNothing)
    }

    @Test("A move with an anchor lands right after it, to its right in Layout")
    func movesAfterTheAnchor() throws {
        let plan = try command("thaw://move-item?item=h2&section=visible&after=a").plan(in: Self.snapshot).get()
        #expect(plan.targetOrder == ["a", "h2", "b", "c"])
    }

    @Test("Several items from different sections land together in the order given")
    func batchKeepsTheGivenOrder() throws {
        let plan = try command("thaw://move-item?item=x&item=c&item=h1&section=hidden&after=h2")
            .plan(in: Self.snapshot).get()
        #expect(plan.itemIDs == ["x", "c", "h1"])
        #expect(plan.source == .alwaysHidden)
        #expect(plan.target == .hidden)
        #expect(plan.targetOrder == ["h2", "x", "c", "h1"])
    }

    @Test("A reorder inside one section keeps that section as the source")
    func reorderInsideASection() throws {
        let plan = try command("thaw://move-item?item=c&item=a&section=visible").plan(in: Self.snapshot).get()
        #expect(plan.source == .visible)
        #expect(plan.targetOrder == ["b", "c", "a"])
    }

    @Test("A move that leaves everything in place changes nothing")
    func noOpIsRecognised() throws {
        let plan = try command("thaw://move-item?item=c&section=visible&after=b").plan(in: Self.snapshot).get()
        #expect(plan.changesNothing)
    }

    @Test("Unknown items and anchors are refused")
    func unknownIdentifiersAreRefused() throws {
        #expect(throws: LayoutBatchMoveError.unknownItem("nope")) {
            try command("thaw://move-item?item=nope&section=visible").plan(in: Self.snapshot).get()
        }
        #expect(throws: LayoutBatchMoveError.unknownAnchor("h1")) {
            try command("thaw://move-item?item=a&section=visible&after=h1").plan(in: Self.snapshot).get()
        }
    }

    @Test("A turned-off section is refused")
    func disabledSectionIsRefused() throws {
        let snapshot = LayoutBatchMoveSnapshot(sections: [.visible: [Self.entry("a")], .hidden: [Self.entry("h")]])
        #expect(throws: LayoutBatchMoveError.sectionDisabled(.alwaysHidden)) {
            try command("thaw://move-item?item=a&section=alwaysHidden").plan(in: snapshot).get()
        }
    }

    @Test("Control items, grouped items and items that cannot go there are refused")
    func immovableItemsAreRefused() throws {
        let snapshot = LayoutBatchMoveSnapshot(sections: [
            .visible: [
                Self.entry("thaw", control: true),
                Self.entry("clock", assignable: [.visible], reordersInVisible: false),
                Self.entry("member", grouped: true),
                Self.entry("app"),
            ],
            .hidden: [Self.entry("h")],
        ])
        #expect(throws: LayoutBatchMoveError.controlItem("thaw")) {
            try command("thaw://move-item?item=thaw&section=visible&after=app").plan(in: snapshot).get()
        }
        #expect(throws: LayoutBatchMoveError.groupedItem("member")) {
            try command("thaw://move-item?item=member&section=hidden").plan(in: snapshot).get()
        }
        #expect(throws: LayoutBatchMoveError.notMovable("clock", .hidden)) {
            try command("thaw://move-item?item=clock&section=hidden").plan(in: snapshot).get()
        }
        #expect(throws: LayoutBatchMoveError.notMovable("clock", .visible)) {
            try command("thaw://move-item?item=clock&section=visible&after=app").plan(in: snapshot).get()
        }
    }

    @Test("An item macOS keeps in place may still be reordered inside a hidden section")
    func hiddenSectionReorderIgnoresVisibleOrderability() throws {
        let snapshot = LayoutBatchMoveSnapshot(sections: [
            .visible: [],
            .hidden: [Self.entry("h1", reordersInVisible: false), Self.entry("h2")],
        ])
        let plan = try command("thaw://move-item?item=h1&section=hidden").plan(in: snapshot).get()
        #expect(plan.targetOrder == ["h2", "h1"])
    }

    @Test("One invalid item refuses the whole batch and is named")
    func oneInvalidItemRefusesTheBatch() throws {
        #expect(throws: LayoutBatchMoveError.unknownItem("ghost")) {
            try command("thaw://move-item?item=h1&item=ghost&item=x&section=visible").plan(in: Self.snapshot).get()
        }
    }
}
