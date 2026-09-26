//
//  SectionGeometryGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// The two section-geometry predicates behind `LayoutSolver.shouldPersistSavedOrder`;
/// `hiddenSectionHasRoom` also gates `applySavedLayout`'s bulk dispatch (#868).
///
/// `CacheContext.findSection` degrades rather than fails when the dividers cannot
/// describe the sections, and `saveSectionOrder` would save that reading. Each
/// predicate must stay quiet for layouts that legitimately look like the fault.
@Suite("Section geometry persist gate")
struct SectionGeometryGateTests {
    // MARK: - isAlwaysHiddenSectionResolved (#849)

    @Test("A present divider with the section on is resolved")
    func presentDividerIsResolved() {
        #expect(LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: true,
            isAlwaysHiddenSectionEnabled: true
        ))
    }

    @Test("A missing divider with the section on is unresolved")
    func missingDividerWithEnabledSectionIsUnresolved() {
        // The section is on, so its items are real, but its boundary is missing this cycle (#849).
        #expect(!LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: false,
            isAlwaysHiddenSectionEnabled: true
        ))
    }

    @Test(
        "A disabled always-hidden section is always resolved",
        arguments: [true, false]
    )
    func disabledSectionIsResolved(hasDivider: Bool) {
        // No divider by design; treating that as unresolved would block saving forever.
        #expect(LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: hasDivider,
            isAlwaysHiddenSectionEnabled: false
        ))
    }

    // MARK: - hiddenSectionHasRoom (#795)

    @Test("A healthy gap between the dividers has room")
    func healthyGapHasRoom() {
        // Undocked geometry from the report: a 677pt hidden section.
        #expect(LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -3935,
            alwaysHiddenControlItemMaxX: -4612,
            savedHiddenItemCount: 41,
            liveHiddenItemCount: 41,
            hasVisibleItemParkedOffBar: false
        ))
    }

    @Test("Dividers collapsed onto the same coordinate have no room")
    func collapsedGapHasNoRoom() {
        // Docked fault: both dividers resized to 5016 and landed 5016 apart, so
        // AlwaysHidden.maxX == Hidden.minX and every on-screen item resolves .visible.
        #expect(!LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4271,
            alwaysHiddenControlItemMaxX: -4271,
            savedHiddenItemCount: 41,
            liveHiddenItemCount: 0,
            hasVisibleItemParkedOffBar: true
        ))
    }

    @Test("Dividers in the wrong order have no room")
    func invertedDividersHaveNoRoom() {
        // A negative span is at least as broken as a zero one.
        #expect(!LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4500,
            alwaysHiddenControlItemMaxX: -4271,
            savedHiddenItemCount: 41,
            liveHiddenItemCount: 0,
            hasVisibleItemParkedOffBar: true
        ))
    }

    @Test("A saved layout with no hidden items is never blocked")
    func emptyHiddenSectionIsNotBlocked() {
        // Nothing in hidden, so the dividers have no reason to sit apart; blocking would stop all saves.
        #expect(LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4271,
            alwaysHiddenControlItemMaxX: -4271,
            savedHiddenItemCount: 0,
            liveHiddenItemCount: 0,
            hasVisibleItemParkedOffBar: false
        ))
    }

    @Test("Without an always-hidden divider there is no span to close")
    func absentAlwaysHiddenDividerHasRoom() {
        // Everything left of the hidden divider is .hidden by definition,
        // so there is no second boundary that could collapse against it.
        #expect(LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4271,
            alwaysHiddenControlItemMaxX: nil,
            savedHiddenItemCount: 41,
            liveHiddenItemCount: 41,
            hasVisibleItemParkedOffBar: false
        ))
    }

    @Test("A sub-point gap still counts as room")
    func subPointGapHasRoom() {
        // Tests for a closed span, not for one wide enough to hold anything.
        #expect(LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4270.5,
            alwaysHiddenControlItemMaxX: -4271,
            savedHiddenItemCount: 41,
            liveHiddenItemCount: 41,
            hasVisibleItemParkedOffBar: false
        ))
    }

    @Test("The apply-path bypass geometry has no room")
    func applyPathBypassGeometryHasNoRoom() {
        // #868: dividers collapsed at -5743 with 46 items saved hidden. applySavedLayout
        // dispatched 21 drags on it, which separated the dividers and let the next save
        // persist the misclassification. Both writers now refuse this reading.
        #expect(!LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -5743,
            alwaysHiddenControlItemMaxX: -5743,
            savedHiddenItemCount: 46,
            liveHiddenItemCount: 0,
            hasVisibleItemParkedOffBar: true
        ))
    }

    // MARK: - hiddenSectionHasRoom deadlock (#924)

    /// Dragging every hidden item into visible leaves the dividers correctly
    /// adjacent while the saved order still lists the old entries, and it cannot
    /// clear them while this gate blocks the write (#924).
    @Test("An emptied hidden section is not treated as a collapse")
    func emptiedHiddenSectionIsNotACollapse() {
        #expect(LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4436,
            alwaysHiddenControlItemMaxX: -4436,
            savedHiddenItemCount: 6,
            liveHiddenItemCount: 0,
            hasVisibleItemParkedOffBar: false
        ))
    }

    /// A collapse also reads as zero live hidden items, so an empty live section
    /// alone cannot release the gate without bringing #868 back.
    @Test("A collapse that reads as empty is still blocked")
    func collapseReadingAsEmptyIsStillBlocked() {
        #expect(!LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4436,
            alwaysHiddenControlItemMaxX: -4436,
            savedHiddenItemCount: 6,
            liveHiddenItemCount: 0,
            hasVisibleItemParkedOffBar: true
        ))
    }

    /// Live hidden items with a closed span have nowhere to be, whatever the parked check says.
    @Test("Live hidden items with a closed span are still blocked")
    func liveHiddenItemsWithClosedSpanAreBlocked() {
        #expect(!LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4436,
            alwaysHiddenControlItemMaxX: -4436,
            savedHiddenItemCount: 6,
            liveHiddenItemCount: 3,
            hasVisibleItemParkedOffBar: false
        ))
    }

    // MARK: - hasVisibleItemParkedOffBar (#924)

    @Test("Visible items on the bar are not parked")
    func onBarVisibleItemsAreNotParked() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        #expect(!LayoutSolver.hasVisibleItemParkedOffBar(
            itemBounds: [
                CGRect(x: 1200, y: 0, width: 24, height: 22),
                CGRect(x: 1240, y: 0, width: 24, height: 22),
            ],
            hiddenControlItemMinX: 1100,
            screenFrames: [screen]
        ))
    }

    /// The items sit just right of the collapsed divider, so only their distance
    /// from every display gives them away (#868).
    @Test("A visible item off every display is parked")
    func offDisplayVisibleItemIsParked() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        #expect(LayoutSolver.hasVisibleItemParkedOffBar(
            itemBounds: [
                CGRect(x: 1200, y: 0, width: 24, height: 22),
                CGRect(x: -5743, y: 0, width: 24, height: 22),
            ],
            hiddenControlItemMinX: -5743,
            screenFrames: [screen]
        ))
    }

    @Test("With no screens the answer is the conservative one")
    func noScreensReportsParked() {
        #expect(LayoutSolver.hasVisibleItemParkedOffBar(
            itemBounds: [CGRect(x: 1200, y: 0, width: 24, height: 22)],
            hiddenControlItemMinX: 1100,
            screenFrames: []
        ))
    }

    @Test("A bar with no visible items has nothing parked")
    func noVisibleItemsHasNothingParked() {
        #expect(!LayoutSolver.hasVisibleItemParkedOffBar(
            itemBounds: [],
            hiddenControlItemMinX: 1100,
            screenFrames: [CGRect(x: 0, y: 0, width: 1470, height: 956)]
        ))
    }

    // MARK: - Gate composition

    @Test("A collapsed hidden section blocks the save on its own")
    func collapsedGeometryBlocksTheGate() {
        // Everything else is clear: resolution had recovered, so the collapsed reading reached disk.
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                hiddenSectionHasRoom: false
            )
        ))
    }

    @Test("Healthy geometry with everything else clear persists")
    func healthyGeometryPersists() {
        #expect(LayoutSolver.shouldPersistSavedOrder(.init()))
    }
}

/// Drives the #868 geometry gate through `applySavedLayout` itself, since the
/// wiring is what regressed. Both cases share inputs and differ only in divider
/// geometry, so a failure isolates the gate.
///
/// Serialized because each case drives a real `MenuBarItemManager` and swaps
/// the process-wide `Defaults.store`.
@MainActor
@Suite("Section geometry apply gate", .serialized)
struct SectionGeometryApplyGateTests {
    /// Resolved source PIDs keep the unresolved-identity gate clear.
    private static func makeItems() -> [MenuBarItem] {
        (0 ..< 6).map { index in
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.app\(index)", title: "Item\(index)"),
                windowID: CGWindowID(500 + index),
                bounds: CGRect(x: -5743 + Double(index) * 24, y: 0, width: 24, height: 22)
            )
        }
    }

    /// Builds a manager whose saved layout puts every item in hidden.
    ///
    /// `savedSectionOrder` only loads in `performSetup`, which needs `AppState`, so
    /// arm a profile to write it and conclude it at once to clear
    /// `isApplyingProfileLayout`, which would short-circuit `applySavedLayout`.
    private func makeManager(savingAllOf items: [MenuBarItem]) -> MenuBarItemManager {
        let order = [
            "visible": [String](),
            "hidden": items.map(\.uniqueIdentifier),
            "alwaysHidden": [String](),
        ]
        let manager = MenuBarItemManager()
        manager.armProfileState(
            source: .profile,
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: order,
            itemSectionMap: [:],
            itemOrder: order
        )
        manager.concludeProfileApplyWithoutMoves(source: .profile, items: [])
        return manager
    }

    /// Absent from the current bar: the app-quit signal that advances the change gate immediately.
    private static let departedWindowID: CGWindowID = 999_999

    /// The only `return true` in `applySavedLayout` follows the `applyProfileLayout`
    /// dispatch, so `false` means the apply was never entered.
    @Test("Collapsed dividers stop the apply before it dispatches", .timeLimit(.minutes(1)))
    func collapsedGeometryBlocksTheApply() async throws {
        try await withScratchDefaults { _ in
            let items = Self.makeItems()
            let manager = makeManager(savingAllOf: items)
            // The field incident's shape at fixture scale.
            let collapsed = MenuBarItemManager.ControlItemPair.fixture(
                hiddenAt: CGRect(x: -5743, y: 0, width: 10, height: 22),
                alwaysHiddenAt: CGRect(x: -5753, y: 0, width: 10, height: 22)
            )

            let didApply = await manager.applySavedLayout(
                items: items,
                previousCycle: .init(windowIDs: [Self.departedWindowID]),
                controlItems: collapsed
            )

            #expect(
                !didApply,
                "A collapsed hidden section must refuse the bulk apply instead of dragging the misread section"
            )
        }
    }

    /// Without this, a gate that refused everything would pass the test above.
    @Test("A healthy gap lets the same apply through", .timeLimit(.minutes(1)))
    func healthyGeometryReachesTheApply() async throws {
        try await withScratchDefaults { _ in
            let items = Self.makeItems()
            let manager = makeManager(savingAllOf: items)
            let healthy = MenuBarItemManager.ControlItemPair.fixture(
                hiddenAt: CGRect(x: -5743, y: 0, width: 10, height: 22),
                alwaysHiddenAt: CGRect(x: -6000, y: 0, width: 10, height: 22)
            )

            let didApply = await manager.applySavedLayout(
                items: items,
                previousCycle: .init(windowIDs: [Self.departedWindowID]),
                controlItems: healthy
            )

            #expect(
                didApply,
                "Healthy divider geometry must still dispatch the bulk apply"
            )
        }
    }

    /// The recovery recache after `recreateStatusItem` passes
    /// `bypassSavedLayoutCooldown: true`, which reaches `applySavedLayout` as
    /// `bypassMoveCooldown: true` and must get past a fresh move cooldown.
    ///
    /// `recoverParkedHiddenDividerIfNeeded` needs a live `AppState`; its gate and
    /// episode latch are covered in `ControlItemRecoveryTests`.
    @Test("A recovery retry can bypass a fresh move cooldown", .timeLimit(.minutes(1)))
    func recoveryRetryBypassesMoveCooldown() async throws {
        try await withScratchDefaults { _ in
            let items = Self.makeItems()
            let manager = makeManager(savingAllOf: items)
            let healthy = MenuBarItemManager.ControlItemPair.fixture(
                hiddenAt: CGRect(x: -5743, y: 0, width: 10, height: 22),
                alwaysHiddenAt: CGRect(x: -6000, y: 0, width: 10, height: 22)
            )
            manager.recordExternalMoveOperation()

            let blocked = await manager.applySavedLayout(
                items: items,
                previousCycle: .init(windowIDs: [Self.departedWindowID]),
                controlItems: healthy
            )
            let retried = await manager.applySavedLayout(
                items: items,
                previousCycle: .init(windowIDs: [Self.departedWindowID]),
                controlItems: healthy,
                bypassMoveCooldown: true
            )

            #expect(!blocked)
            #expect(retried)
        }
    }

    // No test for the hard cap: `MoveCircuitBreaker.bulkApplyPermitted` returns before the
    // `applyProfileLayout` dispatch where recovery lives, and the recovery recache
    // skips `applySavedLayout` entirely.
}
