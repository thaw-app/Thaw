//
//  MenuBarSectionControllerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import PlatformRuntimeKit
@testable import Thaw
import XCTest

/// Characterizes `MenuBarSectionController`'s instance lifecycle against fakes for its
/// five collaborators. `refresh()` (and everything that calls it — `show`,
/// `hideRevealedSections`, `setSection`, `revealItemTemporarily`) guards on
/// `appState` being non-nil as its very first line, so constructing the
/// controller with `appState: nil` exercises the guard itself (a real no-op
/// production path when the item manager hasn't attached yet) while still
/// letting the reveal/assignment state transitions run and be observed
/// through the controller's own internal (non-private) accessors.
@MainActor
final class MenuBarSectionControllerTests: XCTestCase {
    final class FakeRuntimeSessionController: RuntimeSessionControllering {
        private(set) var applyCallCount = 0
        private(set) var pulseCallCount = 0
        private(set) var markExternallyTornDownCallCount = 0
        var applyResult = false
        var isHidingAvailable = true
        var isHolding = true

        func apply(sectionAssignment _: [String: MenuBarSection.Name], allItems _: [MenuBarItem]) -> Bool {
            applyCallCount += 1
            return applyResult
        }

        func pulse(sectionAssignment _: [String: MenuBarSection.Name], allItems _: [MenuBarItem]) -> Bool {
            pulseCallCount += 1
            return false
        }

        func markExternallyTornDown() {
            markExternallyTornDownCallCount += 1
        }

        @discardableResult
        func refreshAvailability() -> Bool {
            isHidingAvailable
        }
    }

    final class FakeRuntimeModuleController: RuntimeModuleControlling {
        private(set) var applyCallCount = 0

        func apply(hiddenMenuExtraTitles _: Set<String>) -> Bool {
            applyCallCount += 1
            return false
        }
    }

    final class FakeRuntimeWindowController: RuntimeWindowControlling {
        private(set) var applyCallCount = 0
        private(set) var restoreAllCallCount = 0

        func apply(hiddenPIDs _: Set<pid_t>, allItems _: [MenuBarItem]) -> Set<pid_t> {
            applyCallCount += 1
            return []
        }

        func restoreAll() {
            restoreAllCallCount += 1
        }
    }

    final class FakeAXItemHider: RuntimeWindowControlling {
        private(set) var applyCallCount = 0
        private(set) var restoreAllCallCount = 0

        func apply(hiddenPIDs _: Set<pid_t>, allItems _: [MenuBarItem]) -> Set<pid_t> {
            applyCallCount += 1
            return []
        }

        func restoreAll() {
            restoreAllCallCount += 1
        }
    }

    /// Records the order in which surgical hiders are invoked, shared across
    /// two `OrderRecordingSurgicalHider` instances (CGS + AX) so a test can
    /// assert `applyExperimentalWindowHiding`'s pass ordering.
    final class CallOrderLog {
        private(set) var order: [String] = []
        func record(_ name: String) {
            order.append(name)
        }
    }

    final class OrderRecordingSurgicalHider: RuntimeWindowControlling {
        let name: String
        let log: CallOrderLog
        let handledPIDs: Set<pid_t>
        private(set) var lastReceivedPIDs: Set<pid_t> = []

        init(name: String, log: CallOrderLog, handledPIDs: Set<pid_t> = []) {
            self.name = name
            self.log = log
            self.handledPIDs = handledPIDs
        }

        func apply(hiddenPIDs: Set<pid_t>, allItems _: [MenuBarItem]) -> Set<pid_t> {
            log.record(name)
            lastReceivedPIDs = hiddenPIDs
            return handledPIDs.intersection(hiddenPIDs)
        }

        func restoreAll() {}
    }

    final class FakeRuntimePreferenceStore: RuntimePreferenceProviding {
        private(set) var hasHiddenItems = false
        private(set) var restoreAllCallCount = 0
        var storedPositions: [String: Int] = [:]

        func readPositions() -> [String: Int] {
            storedPositions
        }

        func writePositions(_ dict: [String: Int]) {
            storedPositions = dict
        }

        func restoreAll() {
            restoreAllCallCount += 1
        }

        func hideItems(_: [MenuBarItem]) -> Set<String> {
            hasHiddenItems = true
            return []
        }

        func showItems(_: [MenuBarItem], allItems _: [MenuBarItem]) -> Set<String> {
            hasHiddenItems = false
            return []
        }

        func lockVisiblePositions(visibleItemKeys _: Set<String>, allItems _: [MenuBarItem]) -> Set<String> {
            []
        }
    }

    /// A position store whose `hideItems` returns a caller-supplied set of plist
    /// keys, letting a test assert how `applyExperimentalWindowHiding` maps those
    /// returned keys back onto live items when stripping the assertion input.
    final class KeyReturningFakePositionStore: RuntimePreferenceProviding {
        var storedPositions: [String: Int]
        let hideReturnKeys: Set<String>
        private(set) var hasHiddenItems = false
        private(set) var lockedVisibleKeys: Set<String> = []

        init(storedPositions: [String: Int], hideReturnKeys: Set<String>) {
            self.storedPositions = storedPositions
            self.hideReturnKeys = hideReturnKeys
        }

        func readPositions() -> [String: Int] {
            storedPositions
        }

        func writePositions(_ dict: [String: Int]) {
            storedPositions = dict
        }

        func restoreAll() {}

        func hideItems(_: [MenuBarItem]) -> Set<String> {
            hasHiddenItems = true
            return hideReturnKeys
        }

        func showItems(_: [MenuBarItem], allItems _: [MenuBarItem]) -> Set<String> {
            []
        }

        func lockVisiblePositions(visibleItemKeys: Set<String>, allItems _: [MenuBarItem]) -> Set<String> {
            lockedVisibleKeys = visibleItemKeys
            return visibleItemKeys
        }
    }

    final class FakePositionHideBackend: PositionHideBackending {
        var hasManagedItems = false
        var isInDesiredState = true
        var applyResult = PositionHideBackend.ApplyResult(
            handledItemIdentifiers: [],
            didWrite: false
        )
        private(set) var applyCallCount = 0
        private(set) var revealAllCallCount = 0
        private(set) var reassertCallCount = 0

        func apply(
            sectionAssignment _: [String: MenuBarSection.Name],
            allItems _: [MenuBarItem],
            visibleOrder _: [MenuBarItem]
        ) -> PositionHideBackend.ApplyResult {
            applyCallCount += 1
            return applyResult
        }

        func revealAll() -> Bool {
            revealAllCallCount += 1
            return false
        }

        func reassert() -> Bool {
            reassertCallCount += 1
            return false
        }
    }

    private var backend = FakeRuntimeSessionController()
    private var ccModuleManager = FakeRuntimeModuleController()
    private var cgsWindowHider = FakeRuntimeWindowController()
    private var axItemHider = FakeAXItemHider()
    private var positionStore = FakeRuntimePreferenceStore()
    private var positionHideBackend = FakePositionHideBackend()

    override func setUp() {
        super.setUp()
        backend = FakeRuntimeSessionController()
        ccModuleManager = FakeRuntimeModuleController()
        cgsWindowHider = FakeRuntimeWindowController()
        axItemHider = FakeAXItemHider()
        positionStore = FakeRuntimePreferenceStore()
        positionHideBackend = FakePositionHideBackend()
    }

    private func makeController() -> MenuBarSectionController {
        MenuBarSectionController(
            appState: nil,
            backend: backend,
            ccModuleManager: ccModuleManager,
            cgsWindowHider: cgsWindowHider,
            axItemHider: axItemHider,
            positionStore: positionStore,
            positionHideBackend: positionHideBackend
        )
    }

    func testHidingUnsupportedVisibilityFailuresIncludesAbsentBundle() {
        let failures = MenuBarSectionController.hidingUnsupportedVisibilityFailures(
            items: [],
            bundleIDs: ["com.example.denylisted"]
        )

        XCTAssertTrue(failures.invisibleItems.isEmpty)
        XCTAssertEqual(failures.absentBundleIDs, ["com.example.denylisted"])
    }

    func testHidingUnsupportedVisibilityFailuresIgnoresVisibleBundle() {
        let item = MenuBarItem(
            tag: .appItem(bundleID: "com.example.denylisted", title: "Item"),
            windowID: 40,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: 120, y: 0, width: 24, height: 22),
            title: "Item",
            isOnScreen: true
        )

        let failures = MenuBarSectionController.hidingUnsupportedVisibilityFailures(
            items: [item],
            bundleIDs: ["com.example.denylisted"]
        )

        XCTAssertTrue(failures.invisibleItems.isEmpty)
        XCTAssertTrue(failures.absentBundleIDs.isEmpty)
    }

    func testRecoverySnapshotUsesProvidedLiveItemsWithoutAXRefresh() {
        let controlled = MenuBarItem(
            tag: .appItem(bundleID: "com.test.hidden", title: "Hidden"),
            windowID: 41,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: 120, y: 0, width: 24, height: 22),
            title: "Hidden",
            isOnScreen: true
        )
        let visible = MenuBarItem(
            tag: .appItem(bundleID: "com.test.visible", title: "Visible"),
            windowID: 42,
            ownerPID: 101,
            sourcePID: 101,
            bounds: CGRect(x: 150, y: 0, width: 24, height: 22),
            title: "Visible",
            isOnScreen: true
        )
        let controlledIdentifiers = Set([controlled.uniqueIdentifier])

        let exposed = MenuBarSectionController.makeRecoverySnapshot(
            items: [controlled, visible],
            controlledIdentifiers: controlledIdentifiers,
            screenCount: 2
        )
        let concealed = MenuBarSectionController.makeRecoverySnapshot(
            items: [visible],
            controlledIdentifiers: controlledIdentifiers,
            screenCount: 2
        )

        XCTAssertFalse(exposed.isControlledHidden)
        XCTAssertTrue(concealed.isControlledHidden)
        XCTAssertEqual(concealed.screenCount, 2)
        XCTAssertNotEqual(exposed.itemSignature, concealed.itemSignature)
    }

    func testRecoverySnapshotChangesWhenCachedGeometryMoves() {
        let original = MenuBarItem(
            tag: .appItem(bundleID: "com.test.visible", title: "Visible"),
            windowID: 42,
            ownerPID: 101,
            sourcePID: 101,
            bounds: CGRect(x: 150, y: 0, width: 24, height: 22),
            title: "Visible",
            isOnScreen: true
        )
        let moved = MenuBarItem(
            tag: original.tag,
            windowID: original.windowID,
            ownerPID: original.ownerPID,
            sourcePID: original.sourcePID,
            bounds: CGRect(x: 180, y: 0, width: 24, height: 22),
            title: original.title,
            isOnScreen: true
        )

        let before = MenuBarSectionController.makeRecoverySnapshot(
            items: [original],
            controlledIdentifiers: [],
            screenCount: 1
        )
        let after = MenuBarSectionController.makeRecoverySnapshot(
            items: [moved],
            controlledIdentifiers: [],
            screenCount: 1
        )

        XCTAssertNotEqual(before.itemSignature, after.itemSignature)
        XCTAssertFalse(before.isControlledHidden)
        XCTAssertFalse(after.isControlledHidden)
    }

    func testPositionHidingRemovesThirdPartyItemsFromAssertionInput() {
        let item = MenuBarItem(
            tag: .appItem(bundleID: "com.test.App", title: "Item-0"),
            windowID: 71,
            ownerPID: 200,
            sourcePID: 200,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 22),
            title: "Item-0",
            isOnScreen: true
        )
        positionHideBackend.applyResult = .init(
            handledItemIdentifiers: [item.uniqueIdentifier],
            thirdPartyItemIdentifiers: [item.uniqueIdentifier],
            didWrite: true
        )
        let controller = makeController()
        var assertionAssignment = [item.uniqueIdentifier: MenuBarSection.Name.hidden]

        controller.applyPositionHiding(
            enabled: true,
            effectiveAssignment: assertionAssignment,
            allItems: [item],
            backendAssignment: &assertionAssignment
        )

        XCTAssertEqual(positionHideBackend.applyCallCount, 1)
        XCTAssertNil(assertionAssignment[item.uniqueIdentifier])
    }

    func testPositionHidingStripsUnresolvedThirdPartyItemFromAssertionInput() {
        // A third-party item that never resolved to a `status:` key
        // (`handledItemIdentifiers` empty) must STILL be removed from the
        // assertion input as long as the backend reported it as third-party.
        // Leaving it in would let the concealed set flip on every reveal,
        // re-applying the assertion and re-compositing the whole bar. The item
        // simply stays visible instead of falling back to the assertion.
        let item = MenuBarItem(
            tag: .appItem(bundleID: "com.test.Unresolved", title: "Item-0"),
            windowID: 72,
            ownerPID: 201,
            sourcePID: 201,
            bounds: CGRect(x: 130, y: 0, width: 24, height: 22),
            title: "Item-0",
            isOnScreen: true
        )
        positionHideBackend.applyResult = .init(
            handledItemIdentifiers: [],
            thirdPartyItemIdentifiers: [item.uniqueIdentifier],
            didWrite: false
        )
        let controller = makeController()
        var assertionAssignment = [item.uniqueIdentifier: MenuBarSection.Name.hidden]

        controller.applyPositionHiding(
            enabled: true,
            effectiveAssignment: assertionAssignment,
            allItems: [item],
            backendAssignment: &assertionAssignment
        )

        XCTAssertTrue(positionHideBackend.applyResult.handledItemIdentifiers.isEmpty)
        XCTAssertNil(assertionAssignment[item.uniqueIdentifier])
    }

    func testSurgicalHidersRunInOrder_CGSThenAX() {
        // This test characterizes the ordering offlation ordering in
        // `applyExperimentalWindowHiding`: CGS runs first, AX runs second (on
        // macOS < 27), and AX only receives PIDs that CGS didn't handle.
        let log = CallOrderLog()
        let cgsHandledPID: pid_t = 123
        let axHandledPID: pid_t = 456
        let cgsHider = OrderRecordingSurgicalHider(
            name: "CGS",
            log: log,
            handledPIDs: [cgsHandledPID]
        )
        let axHider = OrderRecordingSurgicalHider(
            name: "AX",
            log: log,
            handledPIDs: [axHandledPID]
        )
        let positionStore = FakeRuntimePreferenceStore()
        let backend = FakeRuntimeSessionController()
        let ccModuleManager = FakeRuntimeModuleController()

        let controller = MenuBarSectionController(
            appState: nil,
            backend: backend,
            ccModuleManager: ccModuleManager,
            cgsWindowHider: cgsHider,
            axItemHider: axHider,
            positionStore: positionStore,
            positionHideBackend: FakePositionHideBackend()
        )

        // Create test items with known PIDs.
        let item1 = MenuBarItem(
            tag: MenuBarItemTag(namespace: .optional("com.test.app1"), title: "Item1", windowID: 1, instanceIndex: 0),
            windowID: 1,
            ownerPID: 123,
            sourcePID: 123,
            bounds: CGRect(x: 0, y: 0, width: 20, height: 22),
            title: "Item1",
            isOnScreen: true
        )
        let item2 = MenuBarItem(
            tag: MenuBarItemTag(namespace: .optional("com.test.app2"), title: "Item2", windowID: 2, instanceIndex: 0),
            windowID: 2,
            ownerPID: 456,
            sourcePID: 456,
            bounds: CGRect(x: 30, y: 0, width: 20, height: 22),
            title: "Item2",
            isOnScreen: true
        )
        let allItems = [item1, item2]

        var backendAssignment: [String: MenuBarSection.Name] = [
            item1.uniqueIdentifier: .hidden,
            item2.uniqueIdentifier: .hidden,
        ]

        // Drive the surgical pipeline directly (bypassing the plist pass).
        controller.applyExperimentalWindowHiding(
            enabled: true,
            effectiveAssignment: backendAssignment,
            allItems: allItems,
            backendAssignment: &backendAssignment
        )

        // Assert CGS was called before AX.
        XCTAssertEqual(log.order, ["CGS", "AX"], "Surgical hiders must run in order: CGS then AX")

        // Assert AX only received the PID that CGS didn't handle.
        XCTAssertEqual(axHider.lastReceivedPIDs, [axHandledPID], "AX should only receive PIDs not handled by CGS")
    }

    func testExperimentalWindowHidingStripsAssertionUsingResolvedKeyNotNaiveKey() {
        // Regression: iStat-style items rewrite their AX title every second while
        // registering under a stable internal identifier. `hideItems` returns the
        // stable plist key; the assertion-strip pass must map the live item back
        // to that same stable key via the shared positional resolver — NOT the
        // naive `status:<bundle>::<title>` key, which never matches the stored
        // key and would leave the item in BOTH the plist set and the assertion
        // input, forcing a whole-bar reflow.
        let namespace = "com.bjango.istatmenus"
        let cpuKey = "status:\(namespace)::com.bjango.istatmenus.cpu"
        let memKey = "status:\(namespace)::com.bjango.istatmenus.mem"

        // Two siblings with dynamic titles that match neither stable key.
        let cpuItem = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(namespace), title: "CPU 10%", windowID: 1, instanceIndex: 0),
            windowID: 1,
            ownerPID: 900,
            sourcePID: 900,
            bounds: CGRect(x: 0, y: 0, width: 20, height: 22),
            title: "CPU 10%",
            isOnScreen: true
        )
        let memItem = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(namespace), title: "MEM 40%", windowID: 2, instanceIndex: 0),
            windowID: 2,
            ownerPID: 900,
            sourcePID: 900,
            bounds: CGRect(x: 30, y: 0, width: 20, height: 22),
            title: "MEM 40%",
            isOnScreen: true
        )
        let allItems = [cpuItem, memItem]

        // The plist stores the stable keys; the naive dynamic-title keys are
        // absent, so only positional resolution can pair them.
        let positionStore = KeyReturningFakePositionStore(
            storedPositions: [cpuKey: 100, memKey: 200],
            hideReturnKeys: [cpuKey, memKey]
        )
        let controller = MenuBarSectionController(
            appState: nil,
            backend: FakeRuntimeSessionController(),
            ccModuleManager: FakeRuntimeModuleController(),
            cgsWindowHider: FakeRuntimeWindowController(),
            axItemHider: FakeAXItemHider(),
            positionStore: positionStore,
            positionHideBackend: FakePositionHideBackend()
        )

        var backendAssignment: [String: MenuBarSection.Name] = [
            cpuItem.uniqueIdentifier: .hidden,
            memItem.uniqueIdentifier: .hidden,
        ]

        controller.applyExperimentalWindowHiding(
            enabled: true,
            effectiveAssignment: backendAssignment,
            allItems: allItems,
            backendAssignment: &backendAssignment
        )

        // Both items were resolved to their stable plist keys and stripped from
        // the assertion input; the naive key would have matched neither.
        XCTAssertNil(
            backendAssignment[cpuItem.uniqueIdentifier],
            "Plist-handled item must be stripped from the assertion input via its resolved key"
        )
        XCTAssertNil(
            backendAssignment[memItem.uniqueIdentifier],
            "Plist-handled item must be stripped from the assertion input via its resolved key"
        )
    }

    func testAssertionLayoutMembershipDivergedReadsHiderAssignment() {
        // macOS 27 membership is assignment-driven: divergence must be read from
        // MenuBarSectionController.section(for:), not from the item's spatial X (which
        // still reads hidden-side after an assertion reflow).
        let controller = makeController()
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.a", title: "Foo"),
            windowID: 5,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        controller.setSection(.hidden, item: item)

        // Control-item geometry is irrelevant on this backend; supply a fixture.
        let controlItems = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
        let backend = RuntimeMenuBarBackend()

        // Assigned hidden but saved visible → divergence.
        XCTAssertTrue(
            backend.layoutMembershipDiverged(
                savedSectionByBaseID: ["com.test.a:Foo": .visible],
                items: [item],
                controlItems: controlItems,
                hider: controller
            )
        )
        // Assigned hidden and saved hidden → no divergence.
        XCTAssertFalse(
            backend.layoutMembershipDiverged(
                savedSectionByBaseID: ["com.test.a:Foo": .hidden],
                items: [item],
                controlItems: controlItems,
                hider: controller
            )
        )
        // No controller → cannot read assignment, never diverges.
        XCTAssertFalse(
            backend.layoutMembershipDiverged(
                savedSectionByBaseID: ["com.test.a:Foo": .visible],
                items: [item],
                controlItems: controlItems,
                hider: nil
            )
        )
    }

    func testRefresh_NoOpsWithoutAttachedAppState() {
        let controller = makeController()

        controller.refresh()

        // refresh() guards on `appState` being non-nil as its very first
        // line; with no item manager attached yet (the real state before
        // AppState finishes wiring up), the backend must never be touched.
        XCTAssertEqual(backend.applyCallCount, 0)
    }

    func testRefreshSignatureStableWhenConcealedItemDropsFromCache() {
        // Regression: a third-party item we conceal via the assertion drops
        // out of the live `allItems` cache as a side effect of our own hiding.
        // The refresh dedup signature must NOT change when that happens; if it
        // did, refresh() would re-apply the assertion on the next 1 Hz tick and
        // re-composite the whole bar — the 2-3s "Always Hidden items flicker
        // then vanish and never come back" loop.
        let controller = makeController()
        let item = MenuBarItem(
            tag: .appItem(bundleID: "com.test.AlwaysHidden", title: "Item-0"),
            windowID: 91,
            ownerPID: 300,
            sourcePID: 300,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 22),
            title: "Item-0",
            isOnScreen: true
        )
        controller.setSection(.alwaysHidden, identifier: item.uniqueIdentifier)

        let signatureWhilePresent = controller.refreshSignature(
            allItems: [item],
            experimentalSystemItemHiding: false,
            experimentalWindowHiding: false
        )
        let signatureAfterConcealed = controller.refreshSignature(
            allItems: [],
            experimentalSystemItemHiding: false,
            experimentalWindowHiding: false
        )

        XCTAssertEqual(signatureWhilePresent, signatureAfterConcealed)
    }

    func testRefreshSignatureChangesWhenNonConcealedItemAppears() {
        // The dedup must still fire for genuine external changes: an unmanaged
        // (visible) item appearing has to move the signature so refresh() can
        // react. Guards against over-broadening the concealed-item
        // stabilization above into "never notice new items".
        let controller = makeController()
        let item = MenuBarItem(
            tag: .appItem(bundleID: "com.test.Visible", title: "Item-0"),
            windowID: 92,
            ownerPID: 301,
            sourcePID: 301,
            bounds: CGRect(x: 140, y: 0, width: 24, height: 22),
            title: "Item-0",
            isOnScreen: true
        )

        let signatureEmpty = controller.refreshSignature(
            allItems: [],
            experimentalSystemItemHiding: false,
            experimentalWindowHiding: false
        )
        let signatureWithItem = controller.refreshSignature(
            allItems: [item],
            experimentalSystemItemHiding: false,
            experimentalWindowHiding: false
        )

        XCTAssertNotEqual(signatureEmpty, signatureWithItem)
    }

    func testShow_RevealsOnlyRequestedSection() {
        let controller = makeController()

        controller.show(.hidden)

        XCTAssertEqual(controller.revealedSection, .hidden)
    }

    func testShow_DefaultSchedulesBatchOrderSynchronization() {
        let controller = makeController()

        controller.show(.alwaysHidden)

        XCTAssertEqual(controller.revealedSection, .alwaysHidden)
        XCTAssertTrue(controller.hasPendingRevealOrderSynchronization)
        controller.hideRevealedSections()
        XCTAssertNil(controller.revealedSection)
        XCTAssertFalse(controller.hasPendingRevealOrderSynchronization)
    }

    func testShow_CaptureRevealDoesNotScheduleOrderSynchronization() {
        let controller = makeController()

        controller.show(
            .alwaysHidden,
            reconcileBoundary: false,
            synchronizeOrder: false
        )

        XCTAssertEqual(controller.revealedSection, .alwaysHidden)
        XCTAssertFalse(controller.hasPendingRevealOrderSynchronization)
    }

    func testShow_IsIdempotentForSameSection() {
        let controller = makeController()

        controller.show(.hidden)
        controller.show(.hidden)

        // Second call with the same already-revealed target returns early
        // (guarded by `revealedSection != target`); refresh() is a no-op
        // either way here, so this only characterizes the reveal state
        // itself, not call counts into refresh().
        XCTAssertEqual(controller.revealedSection, .hidden)
    }

    func testRevealingFocusDoesNotChangeItsPersistedHiddenAssignment() {
        let controller = makeController()
        let focusIdentifier = "com.apple.MenuBarAgent:com.apple.menuextra.focusmode"

        controller.setSection(.hidden, identifier: focusIdentifier)
        controller.show(.hidden)

        XCTAssertEqual(controller.section(for: focusIdentifier), .hidden)
        XCTAssertEqual(controller.authoredSection(for: focusIdentifier), .hidden)
        XCTAssertEqual(controller.revealedSection, .hidden)
    }

    func testHideRevealedSections_ClearsReveal() {
        let controller = makeController()
        controller.show(.hidden)
        XCTAssertEqual(controller.revealedSection, .hidden)

        controller.hideRevealedSections()

        XCTAssertNil(controller.revealedSection)
    }

    func testHideRevealedSections_NoOpsWhenNothingRevealed() {
        let controller = makeController()

        // Must not crash or misbehave when called with nothing revealed.
        controller.hideRevealedSections()

        XCTAssertNil(controller.revealedSection)
    }

    func testSetSection_PersistsAssignment() {
        let controller = makeController()
        let identifier = "com.example.app:Item-0"

        controller.setSection(.hidden, identifier: identifier)

        XCTAssertEqual(controller.section(for: identifier), .hidden)
    }

    func testClearingAutomaticOverflowRestoresAuthoredVisibleAssignment() {
        let controller = makeController()
        let identifier = "com.example.overflowed:Item-0"

        controller.setOverflowHiddenIdentifiers([identifier])
        XCTAssertEqual(controller.section(for: identifier), .hidden)
        XCTAssertEqual(controller.authoredSection(for: identifier), .visible)

        controller.setOverflowHiddenIdentifiers([])

        XCTAssertEqual(controller.section(for: identifier), .visible)
    }

    func testClearingAutomaticOverflowPreservesExplicitHiddenAssignment() {
        let controller = makeController()
        let explicitHidden = "com.example.explicit:Item-0"
        let overflowHidden = "com.example.overflowed:Item-0"
        controller.setSection(.hidden, identifier: explicitHidden)
        controller.setOverflowHiddenIdentifiers([overflowHidden])

        controller.setOverflowHiddenIdentifiers([])

        XCTAssertEqual(controller.section(for: explicitHidden), .hidden)
        XCTAssertEqual(controller.section(for: overflowHidden), .visible)
    }

    func testReplacingAutomaticOverflowRestoresItemsThatFitAgain() {
        let controller = makeController()
        let nowFits = "com.example.now-fits:Item-0"
        let stillOverflowed = "com.example.still-overflowed:Item-0"
        controller.setOverflowHiddenIdentifiers([nowFits, stillOverflowed])

        controller.setOverflowHiddenIdentifiers([stillOverflowed])

        XCTAssertEqual(controller.section(for: nowFits), .visible)
        XCTAssertEqual(controller.section(for: stillOverflowed), .hidden)
    }

    func testAutomaticOverflowRetainsSnapshotForLaterRebalance() {
        let controller = makeController()
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.overflowed", title: "Item-0"),
            windowID: 73,
            bounds: CGRect(x: 120, y: 0, width: 24, height: 22)
        )

        controller.setOverflowHiddenItems([item])

        XCTAssertEqual(controller.snapshot(for: item.uniqueIdentifier)?.windowID, item.windowID)
    }

    func testSetSection_RejectsControlItemIdentifier() {
        let controller = makeController()
        let controlItemIdentifier = ControlItem.Identifier.hidden.rawValue

        controller.setSection(.hidden, identifier: controlItemIdentifier)

        // Control-item identifiers can never be assigned a section — they're
        // the dividers themselves, not hideable app items.
        XCTAssertEqual(controller.section(for: controlItemIdentifier), .visible)
    }

    // MARK: - Native-overflow temporary-presentation gating (macOS 27)

    /// Regression: Ice Bar being open must NOT gate native-overflow probing
    /// — otherwise once overflow forces Ice Bar via `shouldUseIceBar`, the
    /// probe that could observe overflow-absent and let Ice Bar's fallback
    /// end can never run again (sticky Ice Bar).
    func testIceBarAloneDoesNotGateProbing() {
        let gates = MenuBarSectionController.nativeOverflowTemporaryPresentationGates(
            hasRevealedSection: false,
            hasTemporarilyRevealedIDs: false,
            isClockActivationBridgeActive: false,
            isIceBarShowing: true,
            isMenuBarHiddenBySystem: false,
            shouldDeferMacOS27MenuBarMutation: false
        )

        XCTAssertFalse(gates.probeGate, "Ice Bar alone must not block probing")
        XCTAssertTrue(gates.drainGate, "Ice Bar must still block rebalancing (moving items)")
    }

    /// Every other temporary-presentation reason must still gate both
    /// probing and rebalancing exactly as before this fix.
    func testOtherTemporaryPresentationReasonsGateBothProbeAndDrain() {
        let reasons: [(String, () -> (probeGate: Bool, drainGate: Bool))] = [
            ("revealedSection", {
                MenuBarSectionController.nativeOverflowTemporaryPresentationGates(
                    hasRevealedSection: true,
                    hasTemporarilyRevealedIDs: false,
                    isClockActivationBridgeActive: false,
                    isIceBarShowing: false,
                    isMenuBarHiddenBySystem: false,
                    shouldDeferMacOS27MenuBarMutation: false
                )
            }),
            ("temporarilyRevealedIDs", {
                MenuBarSectionController.nativeOverflowTemporaryPresentationGates(
                    hasRevealedSection: false,
                    hasTemporarilyRevealedIDs: true,
                    isClockActivationBridgeActive: false,
                    isIceBarShowing: false,
                    isMenuBarHiddenBySystem: false,
                    shouldDeferMacOS27MenuBarMutation: false
                )
            }),
            ("clockActivationBridge", {
                MenuBarSectionController.nativeOverflowTemporaryPresentationGates(
                    hasRevealedSection: false,
                    hasTemporarilyRevealedIDs: false,
                    isClockActivationBridgeActive: true,
                    isIceBarShowing: false,
                    isMenuBarHiddenBySystem: false,
                    shouldDeferMacOS27MenuBarMutation: false
                )
            }),
            ("menuBarHiddenBySystem", {
                MenuBarSectionController.nativeOverflowTemporaryPresentationGates(
                    hasRevealedSection: false,
                    hasTemporarilyRevealedIDs: false,
                    isClockActivationBridgeActive: false,
                    isIceBarShowing: false,
                    isMenuBarHiddenBySystem: true,
                    shouldDeferMacOS27MenuBarMutation: false
                )
            }),
            ("deferMacOS27MenuBarMutation", {
                MenuBarSectionController.nativeOverflowTemporaryPresentationGates(
                    hasRevealedSection: false,
                    hasTemporarilyRevealedIDs: false,
                    isClockActivationBridgeActive: false,
                    isIceBarShowing: false,
                    isMenuBarHiddenBySystem: false,
                    shouldDeferMacOS27MenuBarMutation: true
                )
            }),
        ]

        for (name, makeGates) in reasons {
            let gates = makeGates()
            XCTAssertTrue(gates.probeGate, "\(name) must gate probing")
            XCTAssertTrue(gates.drainGate, "\(name) must gate rebalancing")
        }
    }

    /// With no temporary-presentation reason active at all, neither gate
    /// should block.
    func testNoTemporaryPresentationReasonGatesNothing() {
        let gates = MenuBarSectionController.nativeOverflowTemporaryPresentationGates(
            hasRevealedSection: false,
            hasTemporarilyRevealedIDs: false,
            isClockActivationBridgeActive: false,
            isIceBarShowing: false,
            isMenuBarHiddenBySystem: false,
            shouldDeferMacOS27MenuBarMutation: false
        )

        XCTAssertFalse(gates.probeGate)
        XCTAssertFalse(gates.drainGate)
    }

    // MARK: - Stale native-overflow display pruning (macOS 27)

    /// Regression: a display that was once overflowing but has since lost
    /// menu-bar focus must be pruned even though it's still connected — the
    /// probe only ever samples the active display, so a merely-inactive
    /// display would otherwise be tracked as overflowing forever and keep
    /// forcing Ice Bar via `shouldUseIceBar(for:)`.
    func testStaleNativeOverflowDisplayIDsPrunesInactiveButConnectedDisplay() {
        let stale = MenuBarSectionController.staleNativeOverflowDisplayIDs(
            tracked: [1, 2],
            activeDisplayID: 1,
            connectedDisplayIDs: [1, 2]
        )

        XCTAssertEqual(stale, [2])
    }

    /// A disconnected display must be pruned even if it happens to match the
    /// (now-stale) active display ID reading.
    func testStaleNativeOverflowDisplayIDsPrunesDisconnectedDisplay() {
        let stale = MenuBarSectionController.staleNativeOverflowDisplayIDs(
            tracked: [1, 2],
            activeDisplayID: 2,
            connectedDisplayIDs: [2]
        )

        XCTAssertEqual(stale, [1])
    }

    /// The active, connected display must never be pruned.
    func testStaleNativeOverflowDisplayIDsKeepsActiveConnectedDisplay() {
        let stale = MenuBarSectionController.staleNativeOverflowDisplayIDs(
            tracked: [1],
            activeDisplayID: 1,
            connectedDisplayIDs: [1]
        )

        XCTAssertTrue(stale.isEmpty)
    }
}
