//
//  StrandedAlwaysHiddenDividerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// An Always Hidden divider weighted right of the Hidden divider conceals the visible items left of it.
@Suite("A stranded Always Hidden divider goes back left of the Hidden section")
struct StrandedAlwaysHiddenDividerTests {
    private static let alwaysHidden = "status:Thaw::Thaw.ControlItem.AlwaysHidden"
    private static let hidden = "status:Thaw::Thaw.ControlItem.Hidden"

    @Test("The reported weights, Hidden 562 and Always Hidden 469, put the divider left of Hidden")
    func reportedWeights() {
        let weights = StrandedAlwaysHiddenDivider.reseatedWeights(
            dividerKeys: [Self.alwaysHidden],
            alwaysHiddenItemKeys: [],
            hiddenSideKeys: [Self.hidden],
            in: [Self.alwaysHidden: 469, Self.hidden: 562],
            ascending: false
        )
        #expect(weights == [Self.alwaysHidden: 662])
    }

    /// The table from the report. The agent sorts by the display-name key at 469;
    /// the bundle identifier key at 867 is already left of every Hidden item.
    @Test("From the reported table, only the stranded key moves, left of every Hidden item")
    func reportedTable() {
        let staleAlwaysHidden = "status:com.stonerl.Thaw::Thaw.ControlItem.AlwaysHidden"
        let hiddenItems = [
            "status:com.jamf.connect::connectMenu",
            "status:MiddleClick::Item-0",
            "status:com.federicoterzi.espanso::Item-0",
            "status:Alfred::Item-0",
            "status:com.microsoft.Outlook::Item-0",
            "status:com.microsoft.wdav.tray::Menu",
            "status:com.paloaltonetworks.PANotificationUI::Item-0",
            "status:com.microsoft.teams2::Item-0",
        ]
        let positions = [
            "status:Bartender 7::GoldenGateBar": 909,
            staleAlwaysHidden: 867,
            "status:com.jamf.connect::connectMenu": 837,
            "status:MiddleClick::Item-0": 780,
            "status:com.federicoterzi.espanso::Item-0": 777,
            "status:Alfred::Item-0": 695,
            "status:com.microsoft.Outlook::Item-0": 691,
            "status:com.microsoft.wdav.tray::Menu": 687,
            "status:com.paloaltonetworks.PANotificationUI::Item-0": 623,
            "status:com.microsoft.teams2::Item-0": 587,
            Self.hidden: 562,
            "status:OrbStack::Item-0": 550,
            "status:Thaw::Thaw.ControlItem.Visible": 537,
            "status:LinearMouse::Item-0": 494,
            Self.alwaysHidden: 469,
            "status:Claude::Item-0": 454,
        ]

        let weights = StrandedAlwaysHiddenDivider.reseatedWeights(
            dividerKeys: [Self.alwaysHidden, staleAlwaysHidden],
            alwaysHiddenItemKeys: [],
            hiddenSideKeys: hiddenItems + [Self.hidden],
            in: positions,
            ascending: false
        )
        #expect(weights == [Self.alwaysHidden: 937])
    }

    @Test("A divider already left of the Hidden section is not written")
    func normalOrder() {
        let weights = StrandedAlwaysHiddenDivider.reseatedWeights(
            dividerKeys: [Self.alwaysHidden],
            alwaysHiddenItemKeys: [],
            hiddenSideKeys: [Self.hidden],
            in: [Self.alwaysHidden: 600, Self.hidden: 562],
            ascending: false
        )
        #expect(weights.isEmpty)
    }

    @Test("A tie with the Hidden section says nothing about the side, so nothing is written")
    func equalWeights() {
        let weights = StrandedAlwaysHiddenDivider.reseatedWeights(
            dividerKeys: [Self.alwaysHidden],
            alwaysHiddenItemKeys: [],
            hiddenSideKeys: [Self.hidden],
            in: [Self.alwaysHidden: 562, Self.hidden: 562],
            ascending: false
        )
        #expect(weights.isEmpty)
    }

    @Test("Without a weight for the divider or for the Hidden section, nothing is written")
    func missingWeights() {
        let withoutDivider = StrandedAlwaysHiddenDivider.reseatedWeights(
            dividerKeys: [Self.alwaysHidden],
            alwaysHiddenItemKeys: [],
            hiddenSideKeys: [Self.hidden],
            in: [Self.hidden: 562],
            ascending: false
        )
        let withoutHidden = StrandedAlwaysHiddenDivider.reseatedWeights(
            dividerKeys: [Self.alwaysHidden],
            alwaysHiddenItemKeys: [],
            hiddenSideKeys: [Self.hidden],
            in: [Self.alwaysHidden: 469],
            ascending: false
        )
        #expect(withoutDivider.isEmpty)
        #expect(withoutHidden.isEmpty)
    }

    /// Turning Always Hidden off removes the divider but leaves its old row in the table.
    @Test("With Always Hidden off, the divider's leftover weight is not written")
    func alwaysHiddenOff() {
        let weights = StrandedAlwaysHiddenDivider.reseatedWeights(
            dividerKeys: [],
            alwaysHiddenItemKeys: [],
            hiddenSideKeys: [Self.hidden],
            in: [Self.alwaysHidden: 469, Self.hidden: 562],
            ascending: false
        )
        #expect(weights.isEmpty)
    }

    @Test("The divider lands between the Always Hidden items and the Hidden section")
    func staysRightOfAlwaysHiddenItems() {
        let alwaysHiddenItem = "status:Alfred::Item-0"
        let weights = StrandedAlwaysHiddenDivider.reseatedWeights(
            dividerKeys: [Self.alwaysHidden],
            alwaysHiddenItemKeys: [alwaysHiddenItem],
            hiddenSideKeys: [Self.hidden],
            in: [alwaysHiddenItem: 900, Self.hidden: 562, Self.alwaysHidden: 469],
            ascending: false
        )
        #expect(weights == [Self.alwaysHidden: 731])
    }
}

/// The same decision, read from and written to a store, as the structural restore runs it.
@MainActor
@Suite("Reseating the Always Hidden divider writes only Thaw's own rows")
struct StrandedAlwaysHiddenDividerStoreTests {
    private let alwaysHidden = Self.control(.alwaysHiddenControlItem, windowID: 1, x: 260)
    private let hidden = Self.control(.hiddenControlItem, windowID: 2, x: 120)
    private let jamf = Self.member("com.jamf.connect", "connectMenu", windowID: 3, x: 80)
    private let orbStack = Self.member("dev.kdrag0n.MacVirt", "Item-0", windowID: 4, x: 160)
    private let claude = Self.member("com.anthropic.claudefordesktop", "Item-0", windowID: 5, x: 280)

    /// The report's rows. The kit resolves the divider to the bundle identifier
    /// row at 867, while the bar sorts by the display-name row at 469.
    private var positions: [String: Int] {
        [
            "status:com.stonerl.Thaw::Thaw.ControlItem.AlwaysHidden": 867,
            "status:com.jamf.connect::connectMenu": 837,
            "status:Thaw::Thaw.ControlItem.Hidden": 562,
            "status:OrbStack::Item-0": 550,
            "status:Thaw::Thaw.ControlItem.AlwaysHidden": 469,
            "status:Claude::Item-0": 454,
        ]
    }

    private var resolved: [String: String] {
        [
            alwaysHidden.uniqueIdentifier: "status:com.stonerl.Thaw::Thaw.ControlItem.AlwaysHidden",
            hidden.uniqueIdentifier: "status:Thaw::Thaw.ControlItem.Hidden",
            jamf.uniqueIdentifier: "status:com.jamf.connect::connectMenu",
            orbStack.uniqueIdentifier: "status:OrbStack::Item-0",
            claude.uniqueIdentifier: "status:Claude::Item-0",
        ]
    }

    @Test("The display-name row the bar sorts by moves left of the Hidden section")
    func reseatsTheRowTheBarReads() {
        let fake = FakeStore(positions: positions, resolved: resolved)

        let reseated = reseat(alwaysHidden, in: fake)

        #expect(reseated == [alwaysHidden.uniqueIdentifier])
        var expected = positions
        expected["status:Thaw::Thaw.ControlItem.AlwaysHidden"] = 937
        #expect(fake.writes == [expected])
    }

    @Test("Thaw's rows are looked up under its bundle identifier and its name")
    func ownerNames() {
        let owners = StrandedAlwaysHiddenDivider.ownerNames()
        #expect(owners.contains("com.stonerl.Thaw"))
        #expect(owners.contains("Thaw"))
    }

    @Test("With Always Hidden off, nothing is written")
    func alwaysHiddenOff() {
        let fake = FakeStore(positions: positions, resolved: resolved)

        let reseated = reseat(nil, in: fake)

        #expect(reseated.isEmpty)
        #expect(fake.writes.isEmpty)
    }

    private func reseat(_ divider: MenuBarItem?, in fake: FakeStore) -> [String] {
        StrandedAlwaysHiddenDivider.reseat(
            divider,
            rightOf: [],
            leftOf: [jamf, hidden],
            liveItems: [jamf, hidden, orbStack, alwaysHidden, claude],
            owners: ["com.stonerl.Thaw", "Thaw"],
            store: PermittedPositionStore(wrapping: fake),
            permit: .unsequenced("stranded divider test")
        )
    }

    private static func control(_ tag: MenuBarItemTag, windowID: CGWindowID, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: x, y: 0, width: 2, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }

    private static func member(_ bundleID: String, _ title: String, windowID: CGWindowID, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 200,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }
}

/// A table that resolves items through a fixed map and records every write.
@MainActor
private final class FakeStore: MenuBarPositionStoring {
    private var positions: [String: Int]
    private let resolved: [String: String]
    private(set) var writes: [[String: Int]] = []

    init(positions: [String: Int], resolved: [String: String]) {
        self.positions = positions
        self.resolved = resolved
    }

    func readPositions() -> [String: Int] {
        positions
    }

    func currentPositions() -> [String: Int] {
        positions
    }

    func writePositions(_ positions: [String: Int]) {
        self.positions = positions
        writes.append(positions)
    }

    func resolveKey(
        for item: MenuBarItem, existingKeys _: [String], positions _: [String: Int], liveItems _: [MenuBarItem]
    ) -> String? {
        resolved[item.uniqueIdentifier]
    }

    func parseStatusKey(_: String) -> PositionStatusKey? {
        nil
    }

    func isParkedWeight(_: Int) -> Bool {
        false
    }

    func isProvenAbsent(_: String) -> Bool {
        false
    }

    func move(
        item _: MenuBarItem, to _: MoveDestination, liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool
    ) -> Bool {
        false
    }

    func applyOrder(desiredOrder _: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
        []
    }

    func respaceOrder(desiredOrder _: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
        []
    }

    func breakTiedSiblingWeights(liveItems _: [MenuBarItem]) -> [String] {
        []
    }

    func applyControlItemOrder(desiredOrder _: [MenuBarItem], opaqueVisibleKeys _: [String], liveItems _: [MenuBarItem]) -> [String] {
        []
    }

    func recordAbsenceEvidence(seen _: Set<String>, blank _: Set<String>) -> Set<String> {
        []
    }

    func resetAbsenceEvidence() {}
}
