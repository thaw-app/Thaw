//
//  SimpleItemHiderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterizes `SimpleItemHider`'s instance lifecycle against fakes for its
/// five collaborators. `refresh()` (and everything that calls it — `show`,
/// `hideRevealedSections`, `setSection`, `revealItemTemporarily`) guards on
/// `appState` being non-nil as its very first line, so constructing the
/// hider with `appState: nil` exercises the guard itself (a real no-op
/// production path when the item manager hasn't attached yet) while still
/// letting the reveal/assignment state transitions run and be observed
/// through the hider's own internal (non-private) accessors.
@MainActor
final class SimpleItemHiderTests: XCTestCase {
    final class FakeAssessmentModeBackend: AssessmentModeBackending {
        private(set) var applyCallCount = 0
        private(set) var pulseCallCount = 0
        private(set) var markExternallyTornDownCallCount = 0
        var applyResult = false
        var isHidingAvailable = true

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

    final class FakeControlCenterModuleManager: ControlCenterModuleManaging {
        private(set) var applyCallCount = 0

        func apply(hiddenMenuExtraTitles _: Set<String>) -> Bool {
            applyCallCount += 1
            return false
        }
    }

    final class FakeCGSWindowHider: SurgicalItemHider {
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

    final class FakeAXItemHider: SurgicalItemHider {
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

    final class OrderRecordingSurgicalHider: SurgicalItemHider {
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

    final class FakeTrailingItemPositionStore: TrailingItemPositioning {
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

    private var backend: FakeAssessmentModeBackend!
    private var ccModuleManager: FakeControlCenterModuleManager!
    private var cgsWindowHider: FakeCGSWindowHider!
    private var axItemHider: FakeAXItemHider!
    private var positionStore: FakeTrailingItemPositionStore!

    override func setUp() {
        super.setUp()
        backend = FakeAssessmentModeBackend()
        ccModuleManager = FakeControlCenterModuleManager()
        cgsWindowHider = FakeCGSWindowHider()
        axItemHider = FakeAXItemHider()
        positionStore = FakeTrailingItemPositionStore()
    }

    private func makeHider() -> SimpleItemHider {
        SimpleItemHider(
            appState: nil,
            backend: backend,
            ccModuleManager: ccModuleManager,
            cgsWindowHider: cgsWindowHider,
            axItemHider: axItemHider,
            positionStore: positionStore
        )
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
        let positionStore = FakeTrailingItemPositionStore()
        let backend = FakeAssessmentModeBackend()
        let ccModuleManager = FakeControlCenterModuleManager()

        let hider = SimpleItemHider(
            appState: nil,
            backend: backend,
            ccModuleManager: ccModuleManager,
            cgsWindowHider: cgsHider,
            axItemHider: axHider,
            positionStore: positionStore
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
        hider.applyExperimentalWindowHiding(
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

    func testRefresh_NoOpsWithoutAttachedAppState() {
        let hider = makeHider()

        hider.refresh()

        // refresh() guards on `appState` being non-nil as its very first
        // line; with no item manager attached yet (the real state before
        // AppState finishes wiring up), the backend must never be touched.
        XCTAssertEqual(backend.applyCallCount, 0)
    }

    func testShow_RevealsOnlyRequestedSection() {
        let hider = makeHider()

        hider.show(.hidden)

        XCTAssertEqual(hider.revealedSection, .hidden)
    }

    func testShow_IsIdempotentForSameSection() {
        let hider = makeHider()

        hider.show(.hidden)
        hider.show(.hidden)

        // Second call with the same already-revealed target returns early
        // (guarded by `revealedSection != target`); refresh() is a no-op
        // either way here, so this only characterizes the reveal state
        // itself, not call counts into refresh().
        XCTAssertEqual(hider.revealedSection, .hidden)
    }

    func testHideRevealedSections_ClearsReveal() {
        let hider = makeHider()
        hider.show(.hidden)
        XCTAssertEqual(hider.revealedSection, .hidden)

        hider.hideRevealedSections()

        XCTAssertNil(hider.revealedSection)
    }

    func testHideRevealedSections_NoOpsWhenNothingRevealed() {
        let hider = makeHider()

        // Must not crash or misbehave when called with nothing revealed.
        hider.hideRevealedSections()

        XCTAssertNil(hider.revealedSection)
    }

    func testSetSection_PersistsAssignment() {
        let hider = makeHider()
        let identifier = "com.example.app:Item-0"

        hider.setSection(.hidden, identifier: identifier)

        XCTAssertEqual(hider.section(for: identifier), .hidden)
    }

    func testSetSection_RejectsControlItemIdentifier() {
        let hider = makeHider()
        let controlItemIdentifier = ControlItem.Identifier.hidden.rawValue

        hider.setSection(.hidden, identifier: controlItemIdentifier)

        // Control-item identifiers can never be assigned a section — they're
        // the dividers themselves, not hideable app items.
        XCTAssertEqual(hider.section(for: controlItemIdentifier), .visible)
    }
}
