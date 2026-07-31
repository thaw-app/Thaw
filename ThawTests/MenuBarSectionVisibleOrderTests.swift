//
//  MenuBarSectionVisibleOrderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import PlatformRuntimeKit
import Testing
@testable import Thaw

/// Regression coverage for `sectionItemOrder[.visible]`.
///
/// `LayoutSolver` reads the visible order to separate profile-saved visible
/// items from unmanaged ones, and `planNotchOverflow` overflows unmanaged items
/// first. Every path that assigns an item to `.visible` must therefore *record*
/// it there — `removeFromOrder` alone leaves the item unmanaged forever, so a
/// Hidden → Visible round trip would conceal it again as soon as the bar got
/// tight.
///
/// `sectionItemOrder` is loaded from and persisted to the shared app defaults,
/// and the test host *is* the Thaw app, so a controller starts with whatever
/// earlier tests left behind. These tests assert on their own fixtures'
/// membership rather than on the whole array.
@MainActor
struct MenuBarSectionVisibleOrderTests {
    private func makeController() -> MenuBarSectionController {
        let backend = MenuBarSectionControllerTests.FakeRuntimeSessionController()
        let ccModuleManager = MenuBarSectionControllerTests.FakeRuntimeModuleController()
        let cgsWindowHider = MenuBarSectionControllerTests.FakeRuntimeWindowController()
        let axItemHider = MenuBarSectionControllerTests.FakeAXItemHider()
        let positionStore = MenuBarSectionControllerTests.FakeRuntimePreferenceStore()
        let positionHideBackend = MenuBarSectionControllerTests.FakePositionHideBackend()

        return MenuBarSectionController(
            appState: nil,
            backend: backend,
            ccModuleManager: ccModuleManager,
            cgsWindowHider: cgsWindowHider,
            axItemHider: axItemHider,
            positionStore: positionStore,
            positionHideBackend: positionHideBackend
        )
    }

    private func visibleOrder(_ controller: MenuBarSectionController) -> [String] {
        controller.sectionItemOrder[.visible] ?? []
    }

    private func hiddenOrder(_ controller: MenuBarSectionController) -> [String] {
        controller.sectionItemOrder[.hidden] ?? []
    }

    /// A Hidden → Visible round trip must leave the item recorded in the
    /// visible order. `LayoutSolver` reads `sectionItemOrder[.visible]` to tell
    /// profile-saved visible items from unmanaged ones, and `planNotchOverflow`
    /// overflows unmanaged items first — so an item that came back to Visible
    /// without an order entry gets concealed again the moment the bar is tight.
    @Test
    func roundTripToVisibleRecordsItemInVisibleOrder() {
        let controller = makeController()
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.roundtrip", title: "Combined"),
            windowID: 7,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)

        controller.setSection(.hidden, item: item)
        #expect(hiddenOrder(controller).contains(identifier))
        #expect(!visibleOrder(controller).contains(identifier))

        controller.setSection(.visible, item: item)

        #expect(!hiddenOrder(controller).contains(identifier))
        #expect(visibleOrder(controller).contains(identifier))
        #expect(controller.authoredSection(for: identifier) == .visible)
    }

    /// The batch overload (Reset Layout / overflow rebalance) must record
    /// move-to-visible identically to the single-item path, preserving the
    /// batch's relative order.
    @Test
    func batchRoundTripToVisibleRecordsItemsInVisibleOrder() {
        let controller = makeController()
        let first = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.batch", title: "Combined"),
            windowID: 7,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        let second = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.batch", title: "Battery"),
            windowID: 8,
            bounds: CGRect(x: 230, y: 0, width: 24, height: 22)
        )
        let identifiers = [first, second]
            .map { MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier) }

        controller.setSection(.hidden, items: [first, second])
        #expect(hiddenOrder(controller).filter(identifiers.contains) == identifiers)

        controller.setSection(.visible, items: [first, second])

        #expect(hiddenOrder(controller).allSatisfy { !identifiers.contains($0) })
        #expect(visibleOrder(controller).filter(identifiers.contains) == identifiers)
    }

    /// Moving an already-visible item to Visible must not duplicate its entry.
    @Test
    func repeatedMoveToVisibleDoesNotDuplicateOrderEntry() {
        let controller = makeController()
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.norepeat", title: "Combined"),
            windowID: 7,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)

        controller.setSection(.visible, item: item)
        controller.setSection(.visible, item: item)

        #expect(visibleOrder(controller).filter { $0 == identifier }.count == 1)
    }

    /// Reset Layout rebuilt `sectionItemOrder` from non-visible sections only,
    /// wiping the visible order and persisting the wipe — which made
    /// `LayoutSolver` treat every visible item as unmanaged. The visible order
    /// must survive, and items the reset moves out of Hidden must join it.
    @Test
    func resetAssignmentPreservesVisibleOrderAndAdoptsFreedItems() {
        let controller = makeController()
        let stayingVisible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.reset.a", title: "Alpha"),
            windowID: 1,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 22)
        )
        let freedByReset = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.reset.gauge", title: "Combined"),
            windowID: 2,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        let stayingHidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.reset.b", title: "Beta"),
            windowID: 3,
            bounds: CGRect(x: 300, y: 0, width: 24, height: 22)
        )
        let visibleID = MenuBarItemTag.canonicalPersistentIdentifier(stayingVisible.uniqueIdentifier)
        let freedID = MenuBarItemTag.canonicalPersistentIdentifier(freedByReset.uniqueIdentifier)
        let hiddenID = MenuBarItemTag.canonicalPersistentIdentifier(stayingHidden.uniqueIdentifier)

        controller.setSection(.visible, item: stayingVisible)
        controller.setSection(.hidden, items: [freedByReset, stayingHidden])
        #expect(visibleOrder(controller).contains(visibleID))

        // Reset to a layout that keeps only `stayingHidden` hidden.
        controller.resetAssignment(to: [hiddenID: .hidden])

        #expect(hiddenOrder(controller).contains(hiddenID))
        #expect(visibleOrder(controller).contains(visibleID))
        #expect(visibleOrder(controller).contains(freedID))
        #expect(!visibleOrder(controller).contains(hiddenID))
    }
}
