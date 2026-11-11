//
//  StrandSelectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Strand selection")
struct StrandSelectionTests {
    static func app(_ name: String, x: CGFloat, width: CGFloat = 24, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(name)"), title: name, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 3, width: width, height: 24),
            title: name,
            isOnScreen: true
        )
    }

    static func hiddenDivider(x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: .hiddenControlItem,
            windowID: 9,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: x, y: 3, width: 2, height: 24),
            title: ControlItemIdentifier.hidden.rawValue,
            isOnScreen: true
        )
    }

    static let visibleControl = MenuBarItem(
        tag: .visibleControlItem,
        windowID: 8,
        ownerPID: 501,
        sourcePID: 501,
        bounds: CGRect(x: 1600, y: 3, width: 24, height: 24),
        title: ControlItemIdentifier.visible.rawValue,
        isOnScreen: true
    )

    private static let unavailableTable = StoredWeights.Table(isAvailable: false, positions: [:])

    private func selection(
        memory: BoundaryRepairMemory = BoundaryRepairMemory(),
        hidden: Set<String> = [],
        readWeights: @escaping () -> StoredWeights.Table = { unavailableTable },
        weights: [CGWindowID: Int] = [:]
    ) -> StrandSelection {
        StrandSelection(
            memory: memory,
            experimentalSystemItemHiding: false,
            authoredSection: { hidden.contains($0) ? .hidden : .visible },
            readWeights: readWeights,
            weigh: { _, _ in { weights[$0.windowID] } }
        )
    }

    private let divider = hiddenDivider(x: 300)
    private var pair: ControlItemPair {
        ControlItemPair(hidden: divider, alwaysHidden: nil)
    }

    private let stranded = app("Stranded", x: 200, windowID: 1)
    private let seated = app("Seated", x: 400, windowID: 2)
    private var bar: [MenuBarItem] {
        [stranded, divider, seated, Self.visibleControl]
    }

    @Test("A visible item left of the Hidden divider is a strand, one right of it is not")
    func strandsAreVisibleItemsOnTheHiddenSide() {
        var selection = selection()
        let strands = selection.failingStrands(liveItems: bar, controlItems: pair)
        #expect(strands.map(\.uniqueIdentifier) == [stranded.uniqueIdentifier])
    }

    @Test("Items assigned elsewhere and items the breaker gave up on are not strands")
    func assignedElsewhereOrSuppressedIsNoStrand() {
        let other = Self.app("Other", x: 150, windowID: 3)
        let memory = BoundaryRepairMemory()
        memory.breaker.suppress(PostRestrictionRepairItemID(other))
        var selection = selection(memory: memory, hidden: [stranded.uniqueIdentifier])
        #expect(selection.failingStrands(liveItems: [other] + bar, controlItems: pair).isEmpty)
    }

    @Test("An item owed a physical seat is a strand wherever it stands")
    func pendingSeatIsAStrand() {
        let memory = BoundaryRepairMemory()
        memory.pendingPhysicalSeatIDs.insert(seated.uniqueIdentifier)
        var selection = selection(memory: memory)
        let strands = selection.failingStrands(liveItems: bar, controlItems: pair)
        #expect(strands.map(\.uniqueIdentifier) == [stranded.uniqueIdentifier, seated.uniqueIdentifier])
    }

    @Test("An item with a phantom frame is not a strand, and the seat names who holds it")
    func phantomFrameIsNoStrand() {
        let holder = Self.app("Holder", x: 200, windowID: 4)
        var selection = selection()
        #expect(selection.failingStrands(liveItems: [holder] + bar, controlItems: pair).isEmpty)
        #expect(StrandSelection.seatHolders(of: stranded, among: [holder] + bar).map(\.windowID) == [4])
        #expect(StrandSelection.seatHolders(of: seated, among: bar).isEmpty)
    }

    @Test("The position table is read once until an attempt asks for a fresh one")
    func tableIsReadOncePerAttempt() {
        var reads = 0
        var selection = selection(readWeights: {
            reads += 1
            return Self.unavailableTable
        })
        _ = selection.failingStrands(liveItems: bar, controlItems: pair)
        _ = selection.failingStrands(liveItems: bar, controlItems: pair)
        #expect(reads == 1)
        selection.forgetWeights()
        _ = selection.failingStrands(liveItems: bar, controlItems: pair)
        #expect(reads == 2)
    }

    @Test("A Hidden divider whose frame stopped following the bar is judged from its weight")
    func staleDividerIsJudgedFromItsWeight() {
        // The bar from DividerSeatTests: the divider reports a seat inside Sound, its weight puts it before Home.
        let near = Self.app("Near", x: 1333, width: 34, windowID: 2)
        let home = Self.app("Home", x: 1390, width: 26, windowID: 3)
        let items = [
            Self.app("Far", x: 1303, windowID: 1), near, home,
            Self.app("Sound", x: 1432, width: 22, windowID: 4),
            Self.app("After", x: 1469, windowID: 5),
            Self.app("Bluetooth", x: 1508, width: 16, windowID: 6),
            Self.hiddenDivider(x: 1437.5), Self.visibleControl,
        ]
        let stale = ControlItemPair(hidden: Self.hiddenDivider(x: 1437.5), alwaysHidden: nil)
        let weights: [CGWindowID: Int] = [1: 349, 2: 279, 3: 266, 4: 256, 5: 190, 6: 174, 9: 276]

        var byFrame = selection(hidden: [items[0].uniqueIdentifier, near.uniqueIdentifier])
        #expect(byFrame.failingStrands(liveItems: items, controlItems: stale).map(\.windowID).contains(home.windowID))

        var byWeight = selection(hidden: [items[0].uniqueIdentifier, near.uniqueIdentifier], weights: weights)
        #expect(byWeight.failingStrands(liveItems: items, controlItems: stale).isEmpty)
    }

    @Test("A strand still failing after the trip limit is suppressed and seeded; a repaired one is cleared")
    func scoringSuppressesAfterTheTripLimit() {
        let memory = BoundaryRepairMemory()
        let selection = selection(memory: memory)
        let strandID = PostRestrictionRepairItemID(stranded)

        // The same strand twice in one pass counts as one failure.
        let first = selection.scoreOutcomes(attempted: [stranded, stranded, seated], liveItems: bar, controlItems: pair)
        #expect(first.isEmpty)
        #expect(memory.breaker.trips(for: strandID) == 1)

        let second = selection.scoreOutcomes(attempted: [stranded, seated], liveItems: bar, controlItems: pair)
        #expect(second.map(\.strand.windowID) == [1])
        #expect(second.map(\.trips) == [BoundaryRepairMemory.tripLimit])
        #expect(memory.seededStrandIDs == [strandID])
        #expect(memory.breaker.trips(for: PostRestrictionRepairItemID(seated)) == 0)
    }

    @Test("A drag that left the frame where it was grabbed is found by window, then by identity")
    func unmovedAfterDrag() {
        let nudged = Self.app("Stranded", x: 200.3, windowID: 1)
        #expect(StrandSelection.unmovedAfterDrag(stranded, in: [nudged])?.bounds.minX == 200.3)
        #expect(StrandSelection.unmovedAfterDrag(stranded, in: [Self.app("Stranded", x: 340, windowID: 1)]) == nil)
        #expect(StrandSelection.unmovedAfterDrag(stranded, in: [Self.app("Stranded", x: 200, windowID: 7)])?.windowID == 7)
        #expect(StrandSelection.unmovedAfterDrag(stranded, in: [seated]) == nil)
    }

    @Test("Refreshed dividers are kept only while the walk still reads a judgeable Hidden divider")
    func refreshedDividers() {
        let displays = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let clock = MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            windowID: 20,
            ownerPID: 400,
            sourcePID: 400,
            bounds: CGRect(x: 1840, y: 3, width: 56, height: 24),
            title: "com.apple.menuextra.clock",
            isOnScreen: true
        )
        func refreshed(_ items: [MenuBarItem]) -> ControlItemPair? {
            StrandSelection.refreshedDividers(
                in: items, hiddenControlItemWindowID: nil, alwaysHiddenControlItemWindowID: nil, displays: displays
            )
        }
        #expect(refreshed(bar + [clock])?.hidden.bounds.minX == 300)
        #expect(refreshed([stranded, seated, clock]) == nil)
        #expect(refreshed([stranded, Self.hiddenDivider(x: 1860), clock]) == nil)
    }

    @Test("The suppression note reports the frame and both weights, or that weights were unreadable")
    func strandDiagnostics() {
        #expect(
            StrandSelection.strandDiagnostics(for: stranded, hiddenDivider: divider, positions: [:], weight: { _ in 1 })
                == "frame=200,3 24x24 weights=unavailable"
        )
        #expect(
            StrandSelection.strandDiagnostics(
                for: stranded, hiddenDivider: divider, positions: ["k": 1], weight: { $0.isControlItem ? nil : 279 }
            ) == "frame=200,3 24x24 weight=279 hiddenDividerWeight=none"
        )
    }
}
