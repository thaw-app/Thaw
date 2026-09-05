//
//  LayoutBarContainerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Testing
@testable import Thaw

@MainActor
@Suite("Badge-only layout section drops")
struct LayoutBarContainerTests {
    @Test("A regular item sees a badge-only section as an empty drop target")
    func badgeOnlySectionHasNoRegularItemDropTargets() {
        let badge = LayoutBarNewItemsBadgeView()

        let regularItemTargets = LayoutBarContainer.enabledDropTargets(
            in: [badge],
            excludingBadge: true
        )
        let badgeDragTargets = LayoutBarContainer.enabledDropTargets(
            in: [badge],
            excludingBadge: false
        )

        #expect(regularItemTargets.isEmpty)
        #expect(badgeDragTargets.count == 1)
        #expect(badgeDragTargets.first === badge)
    }

    @Test("A regular item lands on the side of the badge where it is dropped")
    func badgeOnlyInsertionIndexUsesDropSideOfBadge() {
        let badge = LayoutBarNewItemsBadgeView()
        badge.setFrameOrigin(CGPoint(x: 100, y: 0))

        let beforeBadgeIndex = LayoutBarContainer.emptyTargetInsertionIndex(
            for: badge.frame.midX - 1,
            in: [badge],
            excludingBadge: true
        )
        let afterBadgeIndex = LayoutBarContainer.emptyTargetInsertionIndex(
            for: badge.frame.midX + 1,
            in: [badge],
            excludingBadge: true
        )

        #expect(beforeBadgeIndex == 0)
        #expect(afterBadgeIndex == 1)
    }

    @Test("An empty section inserts its first item at the beginning")
    func emptySectionInsertionIndexStartsAtBeginning() {
        let insertionIndex = LayoutBarContainer.emptyTargetInsertionIndex(
            for: 500,
            in: [],
            excludingBadge: true
        )

        #expect(insertionIndex == 0)
    }
}

@Suite("Layout item activation")
struct LayoutBarItemActivationTests {
    @Test("A left click released inside the icon activates its menu bar item")
    func leftClickActivates() {
        #expect(LayoutBarItemView.shouldActivateRepresentedItem(
            buttonNumber: 0,
            didBeginDragging: false,
            mouseUpInsideBounds: true
        ))
    }

    @Test("A drag never activates the app on mouse-up")
    func dragDoesNotActivate() {
        #expect(!LayoutBarItemView.shouldActivateRepresentedItem(
            buttonNumber: 0,
            didBeginDragging: true,
            mouseUpInsideBounds: true
        ))
    }

    @Test("Clicks released outside the icon and non-left clicks do not activate")
    func unrelatedClicksDoNotActivate() {
        #expect(!LayoutBarItemView.shouldActivateRepresentedItem(
            buttonNumber: 0,
            didBeginDragging: false,
            mouseUpInsideBounds: false
        ))
        #expect(!LayoutBarItemView.shouldActivateRepresentedItem(
            buttonNumber: 1,
            didBeginDragging: false,
            mouseUpInsideBounds: true
        ))
    }
}

/// A cross-container drop only inserts the dragged view into the destination,
/// so the drag unit is resolved against both bars. The order those items are
/// handed over in is the order the block move commits, which is why the source
/// bar leads.
@Suite("Cross-container group drag ordering")
struct LayoutBarGroupResolutionOrderTests {
    private func item(_ bundleID: String, _ title: String, _ windowID: CGWindowID) -> MenuBarItem {
        .fixture(tag: .appItem(bundleID: bundleID, title: title), windowID: windowID)
    }

    @Test("A member dragged out of its group keeps its place in the source order")
    func draggedMemberKeepsSourceOrder() throws {
        let first = item("com.example.a", "1", 1)
        let dragged = item("com.example.a", "2", 2)
        let last = item("com.example.a", "3", 3)
        let unrelated = item("com.example.b", "1", 4)

        // The dragged item shows up in the destination and is restored to the
        // slot it left in the source before the unit is resolved.
        let resolutionItems = LayoutBarPaddingView.groupResolutionItems(
            sourceItems: [first, dragged, last],
            destinationItems: [unrelated, dragged]
        )
        let groups = MenuBarItemGroupResolver.resolve(
            tags: resolutionItems.map(\.tag),
            groupSet: .empty
        )
        let draggedIndex = try #require(resolutionItems.firstIndex { $0.tag == dragged.tag })
        let unit = MenuBarItemGroupResolver
            .dragUnitIndices(forIndex: draggedIndex, in: groups)
            .map { resolutionItems[$0].tag }

        #expect(unit == [first.tag, dragged.tag, last.tag])
    }

    @Test("A member already sitting in the destination still joins the unit")
    func destinationMemberJoinsTheUnit() throws {
        let first = item("com.example.a", "1", 1)
        let dragged = item("com.example.a", "2", 2)
        let stranded = item("com.example.a", "3", 3)
        let unrelated = item("com.example.b", "1", 4)

        let resolutionItems = LayoutBarPaddingView.groupResolutionItems(
            sourceItems: [first, dragged],
            destinationItems: [unrelated, dragged, stranded]
        )
        let groups = MenuBarItemGroupResolver.resolve(
            tags: resolutionItems.map(\.tag),
            groupSet: .empty
        )
        let draggedIndex = try #require(resolutionItems.firstIndex { $0.tag == dragged.tag })
        let unit = MenuBarItemGroupResolver
            .dragUnitIndices(forIndex: draggedIndex, in: groups)
            .map { resolutionItems[$0].tag }

        #expect(resolutionItems.map(\.tag) == [first.tag, dragged.tag, unrelated.tag, stranded.tag])
        #expect(unit == [first.tag, dragged.tag, stranded.tag])
    }
}

@Suite("Layout item drag presentation")
struct LayoutBarItemDragPresentationTests {
    @Test("A dragged item keeps a visible dimmed placeholder")
    func draggedItemKeepsVisiblePlaceholder() {
        let fraction = LayoutBarItemView.iconFraction(
            isDraggingPlaceholder: true,
            isEnabled: true
        )

        #expect(fraction > 0)
        #expect(fraction < 1)
    }

    @Test("A frozen container keeps its last stable thumbnail")
    func frozenContainerRejectsTransientThumbnail() {
        #expect(!LayoutBarItemView.shouldUpdateCachedImage(
            hasContainer: true,
            containerAllowsUpdates: false
        ))
        #expect(LayoutBarItemView.shouldUpdateCachedImage(
            hasContainer: true,
            containerAllowsUpdates: true
        ))
        #expect(LayoutBarItemView.shouldUpdateCachedImage(
            hasContainer: false,
            containerAllowsUpdates: false
        ))
    }

    @Test("Geometry-only cache changes keep the existing item view")
    func geometryChangeReusesItemView() {
        let tag = MenuBarItemTag.appItem(
            bundleID: "com.example.status-item",
            title: "Item-0",
            windowID: 711
        )
        let beforeMove = MenuBarItem.fixture(
            tag: tag,
            windowID: 711,
            bounds: CGRect(x: 1400, y: 0, width: 24, height: 33),
            isOnScreen: true
        )
        let afterMove = MenuBarItem.fixture(
            tag: tag,
            windowID: 711,
            bounds: CGRect(x: -3700, y: 0, width: 24, height: 33),
            isOnScreen: false
        )

        #expect(LayoutBarContainer.canReuseItemView(
            representing: beforeMove,
            for: afterMove
        ))
    }

    @Test("A recreated status-item window gets a new item view")
    func recreatedWindowDoesNotReuseItemView() {
        let oldItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status-item", title: "Item-0", windowID: 711),
            windowID: 711
        )
        let recreatedItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status-item", title: "Item-0", windowID: 812),
            windowID: 812
        )

        #expect(!LayoutBarContainer.canReuseItemView(
            representing: oldItem,
            for: recreatedItem
        ))
    }

    @Test("A changed status-item size gets a new item view")
    func resizedItemDoesNotReuseItemView() {
        let tag = MenuBarItemTag.appItem(
            bundleID: "com.example.status-item",
            title: "Item-0",
            windowID: 711
        )
        let oldItem = MenuBarItem.fixture(
            tag: tag,
            windowID: 711,
            bounds: CGRect(x: 1400, y: 0, width: 24, height: 33)
        )
        let resizedItem = MenuBarItem.fixture(
            tag: tag,
            windowID: 711,
            bounds: CGRect(x: -3700, y: 0, width: 36, height: 33),
            isOnScreen: false
        )

        #expect(!LayoutBarContainer.canReuseItemView(
            representing: oldItem,
            for: resizedItem
        ))
    }

    @Test("The New Items badge remains visible while dragged")
    func draggedBadgeKeepsVisiblePlaceholder() {
        let opacity = LayoutBarNewItemsBadgeView.contentOpacity(isDraggingPlaceholder: true)

        #expect(opacity > 0)
        #expect(opacity < 1)
    }

    @Test("A cancelled cross-row drag restores the original view exactly once")
    @MainActor
    func cancelledCrossRowDragRestoresOriginalView() {
        let appState = AppState()
        let source = LayoutBarContainer(appState: appState, section: .visible)
        let destination = LayoutBarContainer(appState: appState, section: .hidden)
        let draggedView = LayoutBarNewItemsBadgeView()

        source.arrangedViews = [draggedView]
        source.arrangedViews.removeAll()
        destination.arrangedViews = [draggedView]

        source.restoreArrangedViewAfterCancelledDrag(
            draggedView,
            from: destination,
            at: 0
        )

        #expect(source.arrangedViews.count { $0 === draggedView } == 1)
        #expect(!destination.arrangedViews.contains { $0 === draggedView })
        #expect(draggedView.superview === source)
    }

    @Test("A row frozen by another drag rejects a new drag")
    func frozenRowRejectsUnrelatedDrag() {
        #expect(!LayoutBarPaddingView.canAcceptDrag(
            containerAllowsUpdates: false,
            beganInContainer: false,
            alreadyAccepted: false
        ))
        #expect(LayoutBarPaddingView.canAcceptDrag(
            containerAllowsUpdates: false,
            beganInContainer: true,
            alreadyAccepted: false
        ))
        #expect(LayoutBarPaddingView.canAcceptDrag(
            containerAllowsUpdates: false,
            beganInContainer: false,
            alreadyAccepted: true
        ))
    }
}

@Suite("Layout bar drag identity")
struct LayoutBarDragIdentityTests {
    private let provisional = MenuBarItem.fixture(
        tag: MenuBarItemTag(
            namespace: .controlCenter,
            title: "Item-0",
            windowID: 5467,
            instanceIndex: 0
        ),
        windowID: 5467,
        sourcePID: nil,
        ownerPID: 645
    )

    private let resolved = MenuBarItem.fixture(
        tag: .appItem(bundleID: "IconSwitcher", title: "Item-0", windowID: 5467),
        windowID: 5467,
        sourcePID: 12460,
        ownerPID: 645
    )

    private let otherItem = MenuBarItem.fixture(
        tag: .appItem(bundleID: "com.example.other", title: "Item-0", windowID: 2556),
        windowID: 2556
    )

    @Test("The same window is the same item after its identity resolves")
    func sameWindowIsSameItem() {
        #expect(LayoutBarPaddingView.isSameItem(resolved, provisional))
        #expect(!LayoutBarPaddingView.isSameItem(otherItem, provisional))
    }

    @Test("A recreated window still matches by tag")
    func recreatedWindowMatchesByTag() {
        let recreated = MenuBarItem.fixture(
            tag: .appItem(bundleID: "IconSwitcher", title: "Item-0", windowID: 5744),
            windowID: 5744,
            sourcePID: 12460,
            ownerPID: 645
        )

        #expect(LayoutBarPaddingView.isSameItem(recreated, resolved))
    }

    @Test("The dragged item is found beside its target under its resolved name")
    func reachedPositionUnderResolvedName() {
        let reached = LayoutBarPaddingView.itemReachedIntendedPosition(
            item: provisional,
            destination: .leftOfItem(otherItem),
            sectionItems: [resolved, otherItem]
        )

        #expect(reached)
    }

    @Test("The wrong side of the target is not the intended position")
    func wrongSideIsNotReached() {
        let reached = LayoutBarPaddingView.itemReachedIntendedPosition(
            item: provisional,
            destination: .rightOfItem(otherItem),
            sectionItems: [resolved, otherItem]
        )

        #expect(!reached)
    }

    @Test("Containment is enough when the target is a section divider")
    func dividerTargetNeedsOnlyContainment() {
        let divider = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 5134,
            sourcePID: nil
        )
        let reached = LayoutBarPaddingView.itemReachedIntendedPosition(
            item: provisional,
            destination: .leftOfItem(divider),
            sectionItems: [otherItem, resolved]
        )

        #expect(reached)
    }

    @Test("An item missing from the section has not reached its position")
    func missingItemIsNotReached() {
        let reached = LayoutBarPaddingView.itemReachedIntendedPosition(
            item: provisional,
            destination: .leftOfItem(otherItem),
            sectionItems: [otherItem]
        )

        #expect(!reached)
    }
}
