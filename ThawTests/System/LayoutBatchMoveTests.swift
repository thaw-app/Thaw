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
        group: String? = nil,
        assignable: Set<MenuBarSectionName> = Set(MenuBarSectionName.allCases),
        reordersInVisible: Bool = true
    ) -> Entry {
        Entry(
            id: id,
            isControlItem: control,
            groupID: group,
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
        let parsed = try command("thaw://move-item?item-id=com.example.app:Item-0&section=hidden&after-id=com.example.other:Item-0")
        #expect(parsed.itemIDs == ["com.example.app:Item-0"])
        #expect(parsed.section == .hidden)
        #expect(parsed.afterID == "com.example.other:Item-0")
    }

    @Test("Repeated items keep the order given")
    func repeatedItemsKeepTheirOrder() throws {
        let parsed = try command("thaw://move-item?item-id=z&item-id=x&item-id=y&section=visible")
        #expect(parsed.itemIDs == ["z", "x", "y"])
        #expect(parsed.afterID == nil)
    }

    @Test("Percent-encoded identifiers with colons and spaces are decoded")
    func decodesEncodedIdentifiers() throws {
        let parsed = try command("thaw://move-item?item-id=com.example.app%3AMy%20Item&section=alwaysHidden&after-id=com.apple.x%3AWi-Fi%20Menu")
        #expect(parsed.itemIDs == ["com.example.app:My Item"])
        #expect(parsed.section == .alwaysHidden)
        #expect(parsed.afterID == "com.apple.x:Wi-Fi Menu")
    }

    @Test("The section name is matched case-insensitively")
    func sectionCaseIsIgnored() throws {
        #expect(try command("thaw://move-item?item-id=a&section=AlwaysHidden").section == .alwaysHidden)
    }

    @Test("An empty anchor counts as absent")
    func emptyAnchorIsAbsent() throws {
        #expect(try command("thaw://move-item?item-id=a&section=visible&after-id=").afterID == nil)
    }

    @Test("Missing or malformed parameters are refused with the reason")
    func malformedRequestsAreRefused() throws {
        #expect(try error("thaw://move-item?section=visible") == .missingItem)
        #expect(try error("thaw://move-item?item-id=&section=visible") == .missingItem)
        #expect(try error("thaw://move-item?item-id=a") == .missingSection)
        #expect(try error("thaw://move-item?item-id=a&section=") == .missingSection)
        #expect(try error("thaw://move-item?item-id=a&section=top") == .unknownSection("top"))
        #expect(try error("thaw://move-item?item-id=a&item-id=b&item-id=a&section=visible") == .duplicateItem("a"))
        #expect(try error("thaw://move-item?item-id=a&item-id=b&section=visible&after-id=b") == .anchorIsMovedItem("b"))
    }

    @Test("Every refusal has a stable code and names what is at fault", arguments: [
        (LayoutBatchMoveError.missingItem, "invalidRequest", "item-id="),
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
        let plan = try command("thaw://move-item?item-id=h1&section=visible").plan(in: Self.snapshot).get()
        #expect(plan.source == .hidden)
        #expect(plan.target == .visible)
        #expect(plan.previousTargetOrder == ["a", "b", "c"])
        #expect(plan.targetOrder == ["a", "b", "c", "h1"])
        #expect(!plan.changesNothing)
    }

    @Test("A move with an anchor lands right after it, to its right in Layout")
    func movesAfterTheAnchor() throws {
        let plan = try command("thaw://move-item?item-id=h2&section=visible&after-id=a").plan(in: Self.snapshot).get()
        #expect(plan.targetOrder == ["a", "h2", "b", "c"])
    }

    @Test("Several items from different sections land together in the order given")
    func batchKeepsTheGivenOrder() throws {
        let plan = try command("thaw://move-item?item-id=x&item-id=c&item-id=h1&section=hidden&after-id=h2")
            .plan(in: Self.snapshot).get()
        #expect(plan.itemIDs == ["x", "c", "h1"])
        #expect(plan.source == .alwaysHidden)
        #expect(plan.target == .hidden)
        #expect(plan.targetOrder == ["h2", "x", "c", "h1"])
    }

    @Test("A reorder inside one section keeps that section as the source")
    func reorderInsideASection() throws {
        let plan = try command("thaw://move-item?item-id=c&item-id=a&section=visible").plan(in: Self.snapshot).get()
        #expect(plan.source == .visible)
        #expect(plan.targetOrder == ["b", "c", "a"])
    }

    @Test("A move that leaves everything in place changes nothing")
    func noOpIsRecognised() throws {
        let plan = try command("thaw://move-item?item-id=c&section=visible&after-id=b").plan(in: Self.snapshot).get()
        #expect(plan.changesNothing)
    }

    @Test("Unknown items and anchors are refused")
    func unknownIdentifiersAreRefused() throws {
        #expect(throws: LayoutBatchMoveError.unknownItem("nope")) {
            try command("thaw://move-item?item-id=nope&section=visible").plan(in: Self.snapshot).get()
        }
        #expect(throws: LayoutBatchMoveError.unknownAnchor("h1")) {
            try command("thaw://move-item?item-id=a&section=visible&after-id=h1").plan(in: Self.snapshot).get()
        }
    }

    @Test("A turned-off section is refused")
    func disabledSectionIsRefused() throws {
        let snapshot = LayoutBatchMoveSnapshot(sections: [.visible: [Self.entry("a")], .hidden: [Self.entry("h")]])
        #expect(throws: LayoutBatchMoveError.sectionDisabled(.alwaysHidden)) {
            try command("thaw://move-item?item-id=a&section=alwaysHidden").plan(in: snapshot).get()
        }
    }

    @Test("Control items, grouped items and items that cannot go there are refused")
    func immovableItemsAreRefused() throws {
        let snapshot = LayoutBatchMoveSnapshot(sections: [
            .visible: [
                Self.entry("thaw", control: true),
                Self.entry("clock", assignable: [.visible], reordersInVisible: false),
                Self.entry("member", group: "g"),
                Self.entry("partner", group: "g"),
                Self.entry("app"),
            ],
            .hidden: [Self.entry("h")],
        ])
        #expect(throws: LayoutBatchMoveError.controlItem("thaw")) {
            try command("thaw://move-item?item-id=thaw&section=visible&after-id=app").plan(in: snapshot).get()
        }
        #expect(throws: LayoutBatchMoveError.groupedItem("member")) {
            try command("thaw://move-item?item-id=member&section=hidden").plan(in: snapshot).get()
        }
        #expect(throws: LayoutBatchMoveError.notMovable("clock", .hidden)) {
            try command("thaw://move-item?item-id=clock&section=hidden").plan(in: snapshot).get()
        }
        #expect(throws: LayoutBatchMoveError.notMovable("clock", .visible)) {
            try command("thaw://move-item?item-id=clock&section=visible&after-id=app").plan(in: snapshot).get()
        }
    }

    @Test("An item macOS keeps in place may still be reordered inside a hidden section")
    func hiddenSectionReorderIgnoresVisibleOrderability() throws {
        let snapshot = LayoutBatchMoveSnapshot(sections: [
            .visible: [],
            .hidden: [Self.entry("h1", reordersInVisible: false), Self.entry("h2")],
        ])
        let plan = try command("thaw://move-item?item-id=h1&section=hidden").plan(in: snapshot).get()
        #expect(plan.targetOrder == ["h2", "h1"])
    }

    @Test("One invalid item refuses the whole batch and is named")
    func oneInvalidItemRefusesTheBatch() throws {
        #expect(throws: LayoutBatchMoveError.unknownItem("ghost")) {
            try command("thaw://move-item?item-id=h1&item-id=ghost&item-id=x&section=visible").plan(in: Self.snapshot).get()
        }
    }

    @Test("A move can land at the start of the section; only an after placement names an anchor")
    func placementAtStart() throws {
        let startMove = LayoutBatchMove(itemIDs: ["h1", "x"], section: .visible, placement: .start)
        let plan = try startMove.plan(in: Self.snapshot).get()
        #expect(plan.targetOrder == ["h1", "x", "a", "b", "c"])
        #expect(startMove.afterID == nil)
        #expect(LayoutBatchMove(itemIDs: ["a"], section: .hidden, placement: .after("h1")).afterID == "h1")
        #expect(try command("thaw://move-item?item-id=a&section=hidden").placement == .end)
    }

    @Test("A group moves when every member is listed, and refuses when one is left out")
    func groupsMoveWhole() throws {
        let snapshot = LayoutBatchMoveSnapshot(sections: [
            .visible: [Self.entry("g1", group: "g"), Self.entry("a"), Self.entry("g2", group: "g")],
            .hidden: [Self.entry("h")],
        ])
        let plan = try command("thaw://move-item?item-id=g1&item-id=g2&section=hidden&after-id=h").plan(in: snapshot).get()
        #expect(plan.targetOrder == ["h", "g1", "g2"])
        #expect(snapshot.members(ofGroup: "g") == ["g1", "g2"])
        #expect(throws: LayoutBatchMoveError.groupedItem("g2")) {
            try command("thaw://move-item?item-id=a&item-id=g2&section=hidden").plan(in: snapshot).get()
        }
    }
}
