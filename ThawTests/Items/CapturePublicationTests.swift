//
//  CapturePublicationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Capture publication")
struct CapturePublicationTests {
    private typealias Policy = CapturePublicationPolicy
    private let display: CGDirectDisplayID = 42

    private func rejection(
        _ admission: CapturePublicationAdmission,
        layout: MenuBarLayoutPublicationState,
        displayID: CGDirectDisplayID? = 42,
        isResettingLayout: Bool = false,
        moveWithinCooldown: Bool = false,
        ignoreRecentMove: Bool = false
    ) -> Policy.Rejection? {
        Policy.rejection(
            of: admission,
            layout: layout,
            displayID: displayID,
            isResettingLayout: isResettingLayout,
            moveWithinCooldown: moveWithinCooldown,
            ignoreRecentMove: ignoreRecentMove
        )
    }

    @Test("A capture on a quiet layout and the same display publishes", arguments: [false, true])
    func quietCaptureIsPublished(forced: Bool) {
        var layout = MenuBarLayoutPublicationState()
        layout.invalidate()
        let admission = Policy.admit(layout: layout, displayID: display)

        #expect(rejection(admission, layout: layout, ignoreRecentMove: forced) == nil)
    }

    @Test("A move that completed after admission rejects the capture", arguments: [false, true])
    func completedMoveRejects(forced: Bool) {
        var layout = MenuBarLayoutPublicationState()
        let admission = Policy.admit(layout: layout, displayID: display)
        layout.beginMutation()
        layout.endMutation()

        #expect(rejection(admission, layout: layout, ignoreRecentMove: forced) == .layoutChanged)
    }

    @Test("A mutation still running at publication rejects the capture")
    func activeMutationRejects() {
        var layout = MenuBarLayoutPublicationState()
        let admission = Policy.admit(layout: layout, displayID: display)
        layout.beginMutation()

        #expect(rejection(admission, layout: layout, ignoreRecentMove: true) == .layoutChanged)
    }

    @Test("A capture admitted inside a mutation never publishes, even after it ends")
    func admissionInsideMutationNeverPublishes() {
        var layout = MenuBarLayoutPublicationState()
        layout.beginMutation()
        let admission = Policy.admit(layout: layout, displayID: display)
        #expect(rejection(admission, layout: layout) == .layoutChanged)
        layout.endMutation()
        #expect(rejection(admission, layout: layout) == .layoutChanged)
    }

    @Test("An authored layout invalidation rejects the capture")
    func invalidationRejects() {
        var layout = MenuBarLayoutPublicationState()
        let admission = Policy.admit(layout: layout, displayID: display)
        layout.invalidate()

        #expect(rejection(admission, layout: layout) == .layoutChanged)
    }

    @Test("A display switch rejects an otherwise current capture", arguments: [CGDirectDisplayID(7), nil])
    func displaySwitchRejects(current: CGDirectDisplayID?) {
        let layout = MenuBarLayoutPublicationState()
        let admission = Policy.admit(layout: layout, displayID: display)

        #expect(rejection(admission, layout: layout, displayID: current) == .displayChanged)
    }

    @Test("A forced post-reorder refresh ignores the cooldown of the move that already completed")
    func forcedRefreshAfterCompletedMovePublishes() {
        var layout = MenuBarLayoutPublicationState()
        layout.beginMutation()
        layout.endMutation()
        let admission = Policy.admit(layout: layout, displayID: display)

        #expect(rejection(admission, layout: layout, moveWithinCooldown: true) == .recentMove)
        #expect(rejection(admission, layout: layout, moveWithinCooldown: true, ignoreRecentMove: true) == nil)
    }

    @Test("A forced refresh cannot outrun a move that starts during it", arguments: [false, true])
    func newMutationDuringForcedRefreshRejects(finishesBeforePublication: Bool) {
        var layout = MenuBarLayoutPublicationState()
        layout.beginMutation()
        layout.endMutation()
        let admission = Policy.admit(layout: layout, displayID: display)
        layout.beginMutation()
        if finishesBeforePublication {
            layout.endMutation()
        }

        #expect(rejection(
            admission, layout: layout, moveWithinCooldown: true, ignoreRecentMove: true
        ) == .layoutChanged)
    }

    @Test("A layout reset in progress rejects even a forced refresh")
    func layoutResetRejectsForcedRefresh() {
        let layout = MenuBarLayoutPublicationState()
        let admission = Policy.admit(layout: layout, displayID: display)

        #expect(rejection(admission, layout: layout, isResettingLayout: true, ignoreRecentMove: true) == .layoutResetting)
    }

    @Test("The admitted generation is a snapshot, not a view of the live state")
    func admissionIsASnapshot() {
        var layout = MenuBarLayoutPublicationState()
        let admission = Policy.admit(layout: layout, displayID: display)
        layout.invalidate()

        #expect(admission.layoutGeneration != layout.generation)
        #expect(rejection(Policy.admit(layout: layout, displayID: display), layout: layout) == nil)
    }
}

@MainActor
@Suite("Capture failure ledger commit")
struct CaptureLedgerCommitTests {
    private func makeItem(title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.ledger"), title: title, instanceIndex: 0),
            windowID: 301,
            ownerPID: 999_993,
            sourcePID: 999_993,
            bounds: CGRect(x: 1000, y: 4.5, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private func strikes(for item: MenuBarItem, in cache: MenuBarItemImageCache) -> Int {
        cache.failedCapturesLock.withLock { $0[item.tag]?.failureCount ?? 0 }
    }

    @Test("Strikes and recoveries wait for the pass to be committed")
    func ledgerChangesOnlyOnCommit() {
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        let struck = makeItem(title: "Struck")
        let forgiven = makeItem(title: "Forgiven")
        cache.recordCaptureFailure(for: forgiven)

        var pass = MenuBarItemImageCache.CapturePass()
        pass.failedCaptureItems = [struck]
        pass.recoveredItems = [forgiven]

        #expect(strikes(for: struck, in: cache) == 0)
        #expect(strikes(for: forgiven, in: cache) == 1)
        cache.commitCaptureLedger(of: pass)
        #expect(strikes(for: struck, in: cache) == 1)
        #expect(strikes(for: forgiven, in: cache) == 0)
    }
}

/// A real cache on a bare AppState, three visible items and a scripted bar.
///
/// No item holds both a prior glyph and a fresh crop: that pairing feeds the
/// volatility index, which saves itself to the host's defaults.
@MainActor
private struct CaptureWorld {
    static let display: CGDirectDisplayID = 42

    let appState = AppState()
    let cache = MenuBarItemImageCache(screenIsLocked: { false })
    let gate = CaptureGate()
    let reader: CaptureFixture

    /// One strike on record and a glyph on the bar: a published pass forgives it.
    let fresh = CaptureWorld.makeItem("Fresh", x: 1000, windowID: 101)
    /// Blacklisted with a glyph on the bar: only a pass that sets its record aside tries it.
    let retried = CaptureWorld.makeItem("Retried", x: 1100, windowID: 102)
    /// An untrusted prior and no glyph on the bar: a published pass drops the prior.
    let stale = CaptureWorld.makeItem("Stale", x: 1200, windowID: 103)

    struct State: Equatable {
        let images: [MenuBarItemTag: MenuBarItemGlyphCapture]
        let ledger: [MenuBarItemTag: MenuBarItemImageCache.FailedCapture]
        let accessTimestamps: [MenuBarItemTag: UInt64]
    }

    var state: State {
        State(
            images: cache.capturesByTag,
            ledger: cache.failedCapturesLock.withLock { $0 },
            accessTimestamps: cache.accessTimestamps
        )
    }

    var items: [MenuBarItem] {
        [fresh, retried, stale]
    }

    init(gated: Bool) throws {
        reader = try CaptureFixture(
            hosting: nil,
            strip: CaptureFixture.barCapture(opaque: true, glyphXs: [1008, 1108]),
            items: [fresh, retried, stale],
            gates: gated ? [.strip: gate] : [:]
        )
        cache.appState = appState
        seat(on: Self.display)
        try cache.setCapture(Self.narrowGlyph(), for: stale.tag)
        let now = Date()
        let records = [
            MenuBarItemImageCache.FailedCapture(tag: fresh.tag, failureCount: 1, lastFailureTime: now),
            MenuBarItemImageCache.FailedCapture(
                tag: retried.tag,
                failureCount: MenuBarItemImageCache.maxFailuresBeforeBlacklist,
                lastFailureTime: now
            ),
        ]
        cache.failedCapturesLock.withLock { ledger in
            for record in records {
                ledger[record.tag] = record
            }
        }
    }

    /// Files the items under the item cache of the given display.
    func seat(on displayID: CGDirectDisplayID) {
        var itemCache = MenuBarItemCache(displayID: displayID)
        itemCache[.visible] = items
        appState.itemManager.itemCache = itemCache
    }

    /// A move that finished before the pass was admitted and is still inside its cooldown.
    func completeMoveBeforeAdmission() {
        appState.itemManager.layoutPublication.beginMutation()
        appState.itemManager.layoutPublication.endMutation()
        let tracker = MoveOperationTracker()
        tracker.noteMoveOperation()
        cache.moveActivity = tracker
    }

    /// The crop pipeline a visible section runs, reading the scripted bar.
    func capture(forgiving forgivenTags: Set<MenuBarItemTag>) async -> MenuBarItemImageCache.CapturePass {
        await cache.captureImages(
            of: items, scale: 2, displayID: Self.display, screenFrame: nil,
            freshBounds: true, concealedIdentifiers: [], forgivenTags: forgivenTags, using: reader
        )
    }

    /// The production pass, with the scripted bar as its only pixel source.
    func recapture(forced: Bool) async -> Bool {
        await cache.runRecapturePass(
            capturing: [.visible], displayID: Self.display, ignoreRecentMove: forced, appState: appState
        ) { _ in
            await capture(forgiving: [retried.tag])
        }
    }

    static func makeItem(_ title: String, x: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.pipeline"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 999_994,
            sourcePID: 999_994,
            bounds: CGRect(x: x, y: 4.5, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// Ink, but narrower than a trusted glyph.
    static func narrowGlyph() throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil, width: 20, height: 48, bitsPerComponent: 8, bytesPerRow: 20 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 48))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 2)
    }
}

/// What can happen to the bar while a capture is suspended in its screenshot.
private enum CaptureDisruption: CaseIterable, Sendable {
    case completedMove, activeMutation, displaySwitch, layoutReset

    @MainActor
    func apply(to world: CaptureWorld) {
        let itemManager = world.appState.itemManager
        switch self {
        case .completedMove:
            itemManager.layoutPublication.beginMutation()
            itemManager.layoutPublication.endMutation()
        case .activeMutation:
            itemManager.layoutPublication.beginMutation()
        case .displaySwitch:
            world.seat(on: 7)
        case .layoutReset:
            itemManager.isResettingLayout = true
        }
    }
}

@MainActor
@Suite("Recapture pass publication", .serialized, .timeLimit(.minutes(1)))
struct RecapturePassPublicationTests {
    @Test("A pass on a quiet bar publishes images, invalidations and its ledger")
    func quietPassPublishes() async throws {
        let world = try CaptureWorld(gated: false)

        #expect(await world.recapture(forced: false))

        #expect(world.cache.capturesByTag[world.fresh.tag] != nil)
        #expect(world.cache.capturesByTag[world.retried.tag] != nil, "A forgiven item is attempted despite its record")
        #expect(world.cache.capturesByTag[world.stale.tag] == nil, "The invalidation drops the untrusted prior")
        #expect(world.state.ledger.isEmpty)
    }

    @Test(
        "A bar that changes while the screenshot is in flight leaves the cache and ledger untouched",
        arguments: CaptureDisruption.allCases, [false, true]
    )
    private func disruptedPassChangesNothing(disruption: CaptureDisruption, forced: Bool) async throws {
        let world = try CaptureWorld(gated: true)
        if forced {
            world.completeMoveBeforeAdmission()
        }
        let before = world.state

        let pass = Task { await world.recapture(forced: forced) }
        await world.gate.waitUntilArrived()
        disruption.apply(to: world)
        await world.gate.release()

        #expect(await pass.value == false)
        #expect(world.state == before)
        #expect(await world.reader.captures.contains(.strip), "The pass was rejected after it took pixels, not before")
    }

    @Test("A forced refresh keeps its result after a move that completed before it; an ordinary pass waits out the cooldown")
    func forcedRefreshAfterCompletedMovePublishes() async throws {
        let world = try CaptureWorld(gated: false)
        world.completeMoveBeforeAdmission()
        let before = world.state

        #expect(await world.recapture(forced: false) == false)
        #expect(world.state == before)

        #expect(await world.recapture(forced: true))
        #expect(world.cache.capturesByTag[world.fresh.tag] != nil)
        #expect(world.state.ledger.isEmpty)
    }

    @Test("A pass that goes stale at the commit changes neither pixels nor bookkeeping", arguments: [false, true])
    func staleCommitChangesNothing(forced: Bool) async throws {
        let world = try CaptureWorld(gated: false)
        let admission = CapturePublicationPolicy.admit(
            layout: world.appState.itemManager.layoutPublication, displayID: CaptureWorld.display
        )
        // Nothing forgiven, so the only ledger change on offer is the recovery.
        let pass = await world.capture(forgiving: [])
        try #require(pass.recoveredItems.map(\.tag) == [world.fresh.tag])
        try #require(pass.invalidatedTags.contains(world.stale.tag))
        let before = world.state

        world.appState.itemManager.layoutPublication.invalidate()

        #expect(!world.cache.commitRecapturePass(
            pass, admission: admission, ignoreRecentMove: forced, appState: world.appState
        ))
        #expect(world.state == before)
    }

    @Test("A current pass with nothing to draw still commits its ledger")
    func ledgerOnlyPassCommits() throws {
        let world = try CaptureWorld(gated: false)
        let admission = CapturePublicationPolicy.admit(
            layout: world.appState.itemManager.layoutPublication, displayID: CaptureWorld.display
        )
        var pass = MenuBarItemImageCache.CapturePass()
        pass.recoveredItems = [world.fresh]
        pass.forgivenTags = [world.retried.tag]
        let images = world.cache.capturesByTag

        #expect(!world.cache.commitRecapturePass(
            pass, admission: admission, ignoreRecentMove: false, appState: world.appState
        ), "Nothing a consumer could see changed")
        #expect(world.state.ledger.isEmpty)
        #expect(world.cache.capturesByTag == images)
    }

    @Test("A forgiven item is attempted on every pass, and its record waits for the commit")
    func forgivenessIsStagedNotApplied() async throws {
        let world = try CaptureWorld(gated: false)
        let blacklisted = MenuBarItemImageCache.maxFailuresBeforeBlacklist
        func strikes() -> Int {
            world.state.ledger[world.retried.tag]?.failureCount ?? 0
        }

        let unforgiving = await world.capture(forgiving: [])
        #expect(unforgiving.captured[world.retried.tag] == nil, "The record still blacklists the item for other passes")

        // Twice: a pass that is thrown away must not cost the next one its attempt.
        for _ in 0 ..< 2 {
            let pass = await world.capture(forgiving: [world.retried.tag])
            #expect(pass.captured[world.retried.tag] != nil)
            #expect(strikes() == blacklisted, "An uncommitted pass forgives nothing")
        }

        let pass = await world.capture(forgiving: [world.retried.tag])
        world.cache.commitCaptureLedger(of: pass)
        #expect(strikes() == 0)
    }
}

/// Records single-item reveals. Each one rebuilds the restriction, which the
/// app answers by invalidating the layout publication.
@MainActor
private final class RevealingSectionController: MenuBarSectionControlling {
    private let itemManager: MenuBarItemManager
    private(set) var revealed = [String]()
    private(set) var concealed = [String]()

    init(itemManager: MenuBarItemManager) {
        self.itemManager = itemManager
    }

    func revealItemTemporarily(_ identifier: String) {
        revealed.append(identifier)
        // Not noteRestrictionChange(): that also schedules a live repair pass.
        itemManager.layoutPublication.invalidate()
    }

    func concealTemporarilyRevealedItem(_ identifier: String) {
        concealed.append(identifier)
        itemManager.layoutPublication.invalidate()
    }

    var sectionAssignment: [String: MenuBarSectionName] { [:] }
    var isOperational: Bool { true }
    var revealedSection: MenuBarSectionName? { nil }
    var isHidingAvailable: Bool { true }
    var isRestrictionApplied: Bool { true }
    var overflowHiddenIdentifiers: Set<String> { [] }
    var sectionItemOrder: [MenuBarSectionName: [String]] { [:] }
    var assignedSnapshotTags: Set<MenuBarItemTag> { [] }
    var effectivelyConcealedIdentifiers: Set<String> { [] }
    var shouldBridgeClockActivation: Bool { false }

    func section(for _: MenuBarItem) -> MenuBarSectionName { .hidden }
    func section(for _: String) -> MenuBarSectionName { .hidden }
    func isSectionHidden(_: MenuBarSectionName) -> Bool { true }
    func isNativeOverflowActive(on _: CGDirectDisplayID) -> Bool { false }
    func nativeOverflowControlBounds(on _: CGDirectDisplayID) -> [CGRect] { [] }
    func beginClockActivationBridge(scope _: ClockActivationBridgeScope) -> Bool { false }
    func endClockActivationBridge() {}
    func displayOrdered(_ items: [MenuBarItem], in _: MenuBarSectionName) -> [MenuBarItem] { items }
    func ordered(_ items: [MenuBarItem], in _: MenuBarSectionName) -> [MenuBarItem] { items }
    func authoredSection(for _: String) -> MenuBarSectionName { .hidden }
    func snapshot(for _: String) -> MenuBarItem? { nil }
    func setOverflowHiddenIdentifiers(_: Set<String>) -> Bool { false }
    func setOverflowHiddenItems(_: [MenuBarItem]) -> Bool { false }
    func resetAssignment(to _: [String: MenuBarSectionName]) {}
    func applyProfileLayout(itemSectionMap _: [String: String], itemOrder _: [String: [String]]) {}
    func show(_: MenuBarSectionName, reconcileBoundary _: Bool, synchronizeOrder _: Bool) {}
    func hideRevealedSections() {}
    func scheduleTemporaryItemConceal(_: String) {}
    func setSectionOrder(_: [String], for _: MenuBarSectionName) {}
    func setSectionOrder(from _: [MenuBarItem], for _: MenuBarSectionName) {}
    func setSection(_: MenuBarSectionName, identifier _: String) {}
    func setSection(_: MenuBarSectionName, item _: MenuBarItem) {}
    func concealItemTemporarily(_: String) {}
    func revealTransientlyConcealedItem(_: String) {}
    func regatherGroups() {}
    func pulseRestrictionAfterReflow(liveItems _: [MenuBarItem]) -> Bool { false }
    func notePreferredPositionsSelfWrite() {}
    func refreshHidingAvailability() -> Bool { false }
    func refresh(forceRestrictionPulse _: Bool, forceReapply _: Bool) {}
    func repairGroupInvariantIfNeeded() -> MenuBarItemGroupPolicy.CanonicalizationReport? { nil }
}

@MainActor
@Suite("Grouped reveal publication", .serialized, .timeLimit(.minutes(1)))
struct GroupedRevealPublicationTests {
    /// Reveals fresh and retried one batch each, through the production loop.
    private func prewarm(
        _ world: CaptureWorld,
        controller: RevealingSectionController,
        whileSettling: @escaping @MainActor () -> Void = {}
    ) async {
        await world.cache.captureRevealBatches(
            [[world.fresh], [world.retried]],
            controller: controller,
            displayID: CaptureWorld.display,
            admittedDisplayID: world.appState.itemManager.itemDisplayID,
            scale: 2,
            missPolicy: .dropUntrustedEntries,
            appState: world.appState,
            sources: .init(
                settledItems: { batch in
                    whileSettling()
                    return batch.map { (requested: $0, live: $0) }
                },
                renderSettle: {},
                reader: world.reader
            )
        )
    }

    /// The prewarm forgets the section's failures before it reveals anything.
    private func makeWorld(gated: Bool) throws -> (CaptureWorld, RevealingSectionController) {
        let world = try CaptureWorld(gated: gated)
        world.cache.clearCaptureFailures(tags: [world.retried.tag])
        return (world, RevealingSectionController(itemManager: world.appState.itemManager))
    }

    @Test("A reveal that moves the layout generation still publishes its own batch")
    func revealInvalidationDoesNotRejectTheBatch() async throws {
        let (world, controller) = try makeWorld(gated: false)
        let generation = world.appState.itemManager.layoutPublication.generation

        await prewarm(world, controller: controller)

        #expect(world.appState.itemManager.layoutPublication.generation > generation)
        #expect(world.cache.capturesByTag[world.fresh.tag] != nil)
        #expect(world.cache.capturesByTag[world.retried.tag] != nil, "The first batch's conceal must not cost the second")
        #expect(world.state.ledger.isEmpty)
        let identifiers = [world.fresh, world.retried].map(\.uniqueIdentifier)
        #expect(controller.revealed == identifiers)
        #expect(controller.concealed == identifiers)
    }

    @Test(
        "A move during the batch's screenshot discards it, conceals what was revealed and stops",
        arguments: [CaptureDisruption.completedMove, .activeMutation, .displaySwitch]
    )
    private func externalChangeDuringScreenshotRejects(disruption: CaptureDisruption) async throws {
        let (world, controller) = try makeWorld(gated: true)
        let before = world.state

        let pass = Task { await prewarm(world, controller: controller) }
        await world.gate.waitUntilArrived()
        disruption.apply(to: world)
        await world.gate.release()
        await pass.value

        #expect(world.state == before)
        #expect(controller.revealed == [world.fresh.uniqueIdentifier], "No further batch is revealed")
        #expect(controller.concealed == [world.fresh.uniqueIdentifier])
    }

    @Test("A display that switches while the reveal settles is not adopted as the batch's baseline")
    func displaySwitchWhileSettlingRejects() async throws {
        let (world, controller) = try makeWorld(gated: false)
        let before = world.state

        await prewarm(world, controller: controller, whileSettling: { world.seat(on: 7) })

        #expect(world.state == before)
        #expect(await world.reader.captures.isEmpty, "No pixels are taken for a batch that cannot publish")
        #expect(controller.revealed == [world.fresh.uniqueIdentifier])
        #expect(controller.concealed == [world.fresh.uniqueIdentifier])
    }
}
