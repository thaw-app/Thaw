//
//  SectionGeometryGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers the two section-geometry predicates that feed
/// `LayoutSolver.shouldPersistSavedOrder`. `hiddenSectionHasRoom`
/// additionally gates `applySavedLayout`'s bulk dispatch (#868).
///
/// Both exist for the same reason: `CacheContext.findSection` degrades
/// rather than fails when the dividers cannot describe the sections, and
/// `saveSectionOrder` then writes that degraded reading down as the user's
/// layout. Each predicate also has to stay quiet for the users whose
/// layouts legitimately look like the fault case, which is the half that
/// keeps the fix from becoming a bug of its own.
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
        // The #849 state: the section is on, so its items are real, but the
        // boundary that identifies them is missing this cycle.
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
        // Users who never enabled the section have no divider by design.
        // Treating that as unresolved would block their layout from ever
        // being saved — trading #849 for a worse bug.
        #expect(LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: hasDivider,
            isAlwaysHiddenSectionEnabled: false
        ))
    }

    // MARK: - hiddenSectionHasRoom (#795)

    @Test("A healthy gap between the dividers has room")
    func healthyGapHasRoom() {
        // Undocked geometry from the report: AlwaysHidden ends at -4612,
        // Hidden starts at -3935, so the hidden section spans 677pt.
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
        // The docked-topology fault: both control items resized to 5016 and
        // landed exactly 5016 apart, so AlwaysHidden.maxX == Hidden.minX and
        // the hidden section is a zero-width span. findSection cannot
        // satisfy `minX >= ah.maxX && maxX <= hidden.minX` at one
        // coordinate, so every on-screen item resolves .visible instead.
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
        // A user who keeps nothing in the hidden section has no reason for
        // the dividers to sit apart. Blocking here would stop their layout
        // being saved at all, which is the false positive this predicate
        // has to avoid.
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
        // The predicate tests for a closed span, not for a span wide enough
        // to hold anything. Anything above zero is left to the layout
        // engine rather than second-guessed here.
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
        // The #868 field incident: dividers collapsed at -5743 with 46
        // items saved hidden. saveSectionOrder refused this geometry, but
        // applySavedLayout read the same collapse as an 11-item section
        // mismatch and dispatched 21 synthetic drags — which separated the
        // dividers, un-tripping the save gate, so the next cycle persisted
        // the misclassification. The apply path now consults this predicate
        // before dispatching, so both writers refuse the same reading.
        #expect(!LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -5743,
            alwaysHiddenControlItemMaxX: -5743,
            savedHiddenItemCount: 46,
            liveHiddenItemCount: 0,
            hasVisibleItemParkedOffBar: true
        ))
    }

    // MARK: - hiddenSectionHasRoom deadlock (#924)

    /// The state #924's reporter reached by dragging every hidden item into
    /// visible. The dividers are correctly adjacent because nothing is between
    /// them, but the saved order still lists the old entries — and it cannot
    /// stop listing them while this gate blocks the write that would clear
    /// them. Their log shows the warning firing from the tick hidden hit zero
    /// through every pass after it, on both a populated and an emptied
    /// always-hidden section.
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

    /// The reason the live count cannot decide this on its own. A collapse
    /// reads as zero live hidden items too — the misclassification is the
    /// fault — so releasing on an empty live section alone would hand #868
    /// straight back.
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

    /// Live hidden items with a closed span is the original fault however the
    /// parked check answers: there is nowhere for those items to be.
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

    /// #868's geometry: the items sit just *right* of the collapsed divider,
    /// so a left-of-divider test would miss them. What gives them away is that
    /// they are thousands of points off any display.
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
        // Every other input is clear, which is the situation the reporter
        // was in: resolution had recovered, so the sourcePID guard passed
        // and the collapsed reading reached disk.
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

/// Exercises the #868 geometry gate through `applySavedLayout` itself, rather
/// than through the predicate it consults.
///
/// The predicate tests above pin the arithmetic; they cannot show that the
/// apply path asks the question. That wiring is the part that regressed:
/// `saveSectionOrder` refused the collapsed reading while `applySavedLayout`
/// dispatched a bulk apply on it. Both cases below feed the same bar,
/// the same saved layout and the same change trigger — only the divider
/// geometry differs — so a failure isolates the gate and nothing else.
///
/// Serialized because each case drives a real `MenuBarItemManager` and swaps
/// the process-wide `Defaults.store`.
@MainActor
@Suite("Section geometry apply gate", .serialized)
struct SectionGeometryApplyGateTests {
    /// Six ordinary app items, all with resolved source PIDs so the
    /// unresolved-identity gate stays clear.
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
    /// `savedSectionOrder` is private and is only loaded from disk by
    /// `performSetup`, which needs a live `AppState`. Arming a profile is the
    /// one test-visible writer; concluding it immediately afterwards clears
    /// `isApplyingProfileLayout`, which would otherwise short-circuit
    /// `applySavedLayout` before it reaches the geometry gate.
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

    /// A previous window ID that is absent from the current bar, which is the
    /// app-quit signal that advances the change gate immediately (no
    /// two-cycle divergence confirmation to wait for).
    private static let departedWindowID: CGWindowID = 999_999

    /// The apply path must refuse the geometry `applyPathBypassGeometryHasNoRoom`
    /// describes. `false` is the whole assertion: the only `return true` in
    /// `applySavedLayout` sits after the `applyProfileLayout` dispatch, so a
    /// `false` return is exactly "the shared apply was never entered".
    @Test("Collapsed dividers stop the apply before it dispatches", .timeLimit(.minutes(1)))
    func collapsedGeometryBlocksTheApply() async throws {
        try await withScratchDefaults { _ in
            let items = Self.makeItems()
            let manager = makeManager(savingAllOf: items)
            // AlwaysHidden.maxX == Hidden.minX == -5743, with 6 items saved
            // hidden: the field incident's shape at fixture scale.
            let collapsed = MenuBarItemManager.ControlItemPair.fixture(
                hiddenAt: CGRect(x: -5743, y: 0, width: 10, height: 22),
                alwaysHiddenAt: CGRect(x: -5753, y: 0, width: 10, height: 22)
            )

            let didApply = await manager.applySavedLayout(
                items: items,
                previousWindowIDs: [Self.departedWindowID],
                controlItems: collapsed
            )

            #expect(
                !didApply,
                "A collapsed hidden section must refuse the bulk apply instead of dragging the misread section"
            )
        }
    }

    /// The other half of the gate: with the dividers apart, the same inputs
    /// reach the dispatch. Without this, a gate that refused everything would
    /// pass the test above.
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
                previousWindowIDs: [Self.departedWindowID],
                controlItems: healthy
            )

            #expect(
                didApply,
                "Healthy divider geometry must still dispatch the bulk apply"
            )
        }
    }

    /// A divider rebuild is initiated by an unfinished apply, which may have
    /// just stamped the move cooldown. The recovery-owned recache that follows
    /// `recreateStatusItem` passes `bypassSavedLayoutCooldown: true` through
    /// `cacheItemsRegardless`, which carries into `applySavedLayout` as
    /// `bypassMoveCooldown: true`. This test exercises that contract: a fresh
    /// move cooldown blocks an ordinary apply, but the bypass flag — the same
    /// one the recovery recache uses — lets the verification dispatch through.
    ///
    /// `recoverParkedHiddenDividerIfNeeded` itself is private and requires a
    /// live `AppState` with real `NSStatusItem`s, so it cannot be exercised
    /// at this seam. The pure gate (`shouldRecoverParkedHiddenDivider`) and
    /// the episode latch are covered in `ControlItemRecoveryTests`.
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
                previousWindowIDs: [Self.departedWindowID],
                controlItems: healthy
            )
            let retried = await manager.applySavedLayout(
                items: items,
                previousWindowIDs: [Self.departedWindowID],
                controlItems: healthy,
                bypassMoveCooldown: true
            )

            #expect(!blocked)
            #expect(retried)
        }
    }

    // The hard-cap gate (`automaticBulkApplyPermitted`) blocks dispatch
    // before `applyProfileLayout` — and therefore before
    // `recoverParkedHiddenDividerIfNeeded` — can run. The recovery recache
    // uses `scheduleDeferredCacheRefresh` with `skipSavedLayoutApply: true`,
    // which skips `applySavedLayout` entirely, so it is unaffected by the
    // cap. This invariant is structural: the `automaticBulkApplyPermitted`
    // check at the top of `applySavedLayout` returns `false` before the
    // dispatch to `applyProfileLayout` where the recovery lives, so the
    // recovery cannot fire when the cap has tripped. No test is needed
    // because the call ordering cannot be inverted without moving the
    // recovery outside the apply dispatch.
}
