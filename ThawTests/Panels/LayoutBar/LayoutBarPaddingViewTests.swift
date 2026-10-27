//
//  LayoutBarPaddingViewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// A drag as a layout bar sees it, from a chosen source at a fixed spot in the window.
@MainActor
private final class BarDrag: NSObject, NSDraggingInfo {
    let draggingSource: Any?
    var draggingLocation: NSPoint
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    init(source: Any?, location: NSPoint) {
        self.draggingSource = source
        self.draggingLocation = location
    }

    var draggingDestinationWindow: NSWindow? {
        nil
    }

    var draggingSourceOperationMask: NSDragOperation {
        .move
    }

    var draggedImageLocation: NSPoint {
        draggingLocation
    }

    var draggedImage: NSImage? {
        nil
    }

    var draggingPasteboard: NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("ThawTests.LayoutBarPadding"))
    }

    var draggingSequenceNumber: Int {
        1
    }

    var springLoadingHighlight: NSSpringLoadingHighlight {
        .none
    }

    func slideDraggedImage(to _: NSPoint) {}

    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions = [],
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}

/// The layout bar's drag preview, group handle and refused drops. Every drop sent here is
/// one the bar refuses, so nothing is committed to the menu bar.
@MainActor
@Suite("Layout bar drops", .serialized, .scratchDefaults)
struct LayoutBarPaddingViewTests {
    private typealias World = LayoutEditorWorld

    /// One bar per section asked for, stacked in one offscreen window.
    @MainActor
    private final class Bars {
        let world = World()
        let window: NSWindow
        var scrollViews = [MenuBarSection.Name: LayoutBarScrollView]()

        init(_ items: [MenuBarItem], sections: [MenuBarSection.Name] = [.visible]) throws {
            world.seat(items, in: .visible)
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 56 * CGFloat(sections.count)))
            window = NSWindow(contentRect: content.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = content
            for (index, section) in sections.enumerated() {
                let bar = LayoutBarScrollView(appState: world.appState, section: section)
                bar.translatesAutoresizingMaskIntoConstraints = true
                bar.frame = CGRect(x: 0, y: CGFloat(index) * 56, width: 600, height: 48)
                content.addSubview(bar)
                scrollViews[section] = bar
                try container(section).rebuildViews()
            }
            window.layoutIfNeeded()
        }

        func padding(_ section: MenuBarSection.Name = .visible) throws -> LayoutBarPaddingView {
            try #require(scrollViews[section]?.documentView as? LayoutBarPaddingView)
        }

        func container(_ section: MenuBarSection.Name = .visible) throws -> LayoutBarContainer {
            try #require(padding(section).subviews.lazy.compactMap { $0 as? LayoutBarContainer }.first)
        }

        func itemViews(_ section: MenuBarSection.Name = .visible) throws -> [LayoutBarItemView] {
            try container(section).arrangedViews.compactMap { $0 as? LayoutBarItemView }
        }

        func handles(_ section: MenuBarSection.Name = .visible) throws -> [LayoutBarGroupHandleView] {
            try container(section).subviews.compactMap { $0 as? LayoutBarGroupHandleView }
        }

        func point(on view: NSView) -> NSPoint {
            view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        }
    }

    private static func pair() -> [MenuBarItem] {
        ["One", "Two"].map {
            World.item(MenuBarItemTag(namespace: .string("com.example.Pair"), title: $0, instanceIndex: 0))
        }
    }

    @Test("Only the visible Thaw icon among control items can be dragged in the layout bar")
    func dragSources() {
        #expect(LayoutBarPaddingView.acceptsLayoutDrag(of: World.item("Alpha")))
        #expect(LayoutBarPaddingView.acceptsLayoutDrag(of: World.item(.visibleControlItem)))
        #expect(!LayoutBarPaddingView.acceptsLayoutDrag(of: World.item(.hiddenControlItem)))
        #expect(!LayoutBarPaddingView.allowsAnchoredSystemItemReordering(appState: nil))
        let world = World()
        let expected = world.appState.settings.displaySettings.configurationForActiveDisplay().useThawBar
        #expect(LayoutBarPaddingView.allowsAnchoredSystemItemReordering(appState: world.appState) == expected)
    }

    @Test("Dragging an item across its own bar previews the move and puts the bar back when the drag ends")
    func itemDragPreview() throws {
        let items = ["A", "B", "C"].map(World.item)
        let bars = try Bars(items)
        let padding = try bars.padding()
        let views = try bars.itemViews()
        try #require(views.count == 3)
        let drag = BarDrag(source: views[0], location: bars.point(on: views[2]))

        #expect(padding.draggingEntered(drag) == .move)
        #expect(try !bars.container().acceptsViewUpdates, "the bar is frozen while a drag is over it")
        drag.draggingLocation = bars.point(on: views[1])
        #expect(padding.draggingUpdated(drag) == .move)
        padding.draggingExited(drag)
        padding.draggingEnded(drag)
        #expect(try bars.container().acceptsViewUpdates, "a drag that ends without a drop thaws the bar")
    }

    @Test("A drag from something that is not a bar item is ignored and leaves the bar live")
    func foreignDrag() throws {
        let bars = try Bars([World.item("A")])
        let padding = try bars.padding()
        let drag = BarDrag(source: nil, location: .zero)
        #expect(padding.draggingEntered(drag) == [])
        #expect(!padding.performDragOperation(drag))
        padding.draggingExited(nil)
        padding.draggingEnded(drag)
        #expect(try bars.container().acceptsViewUpdates)
    }

    @Test("A divider dropped on the bar is refused")
    func dividerDropRefused() throws {
        let bars = try Bars([World.item("A")])
        let divider = LayoutBarItemView(appState: bars.world.appState, item: World.item(.hiddenControlItem))
        let drag = BarDrag(source: divider, location: .zero)
        #expect(try !bars.padding().performDragOperation(drag))
        #expect(try bars.container().acceptsViewUpdates)
    }

    @Test("The Thaw icon dropped outside Visible snaps back with an explanation")
    func thawIconStaysVisible() throws {
        let bars = try Bars([World.item("A")], sections: [.visible, .hidden])
        let icon = LayoutBarItemView(appState: bars.world.appState, item: World.item(.visibleControlItem))
        icon.hasContainer = true
        let drag = BarDrag(source: icon, location: .zero)
        #expect(try !bars.padding(.hidden).performDragOperation(drag))
        #expect(!icon.hasContainer)
        let refusal = try #require(bars.world.appState.layoutFeedback.refusal)
        #expect(refusal.title.contains(MenuBarSection.Name.visible.localizedName))
    }

    @Test("A group shows a handle that offers a drop within its own bar")
    func groupHandleDropPreview() throws {
        let alpha = World.item("Alpha")
        let bars = try Bars(Self.pair() + [alpha])
        let handle = try #require(bars.handles().first)
        #expect(handle.sourceSection == .visible)
        #expect(handle.memberIdentifiers.count == 2)
        let padding = try bars.padding()
        let drag = try BarDrag(source: handle, location: bars.point(on: bars.itemViews().last ?? handle))

        #expect(padding.draggingEntered(drag) == .move)
        #expect(try bars.container().groupDropMarkerX != nil)
        #expect(padding.draggingUpdated(drag) == .move)
        padding.draggingExited(drag)
        #expect(try bars.container().groupDropMarkerX == nil)
        padding.draggingEnded(drag)
    }

    @Test("A group handle from another bar whose members are gone cannot drop")
    func foreignGroupHandle() throws {
        let bars = try Bars([World.item("Alpha")], sections: [.visible, .hidden])
        let handle = try LayoutBarGroupHandleView(
            sourceContainer: bars.container(.hidden),
            sourceSection: .hidden,
            memberIdentifiers: ["missing-one", "missing-two"]
        )
        let drag = BarDrag(source: handle, location: .zero)
        #expect(try bars.padding().draggingEntered(drag) == [])
        #expect(try bars.padding().draggingUpdated(drag) == [])
    }

    @Test("A group handle draws a grip, reads as a handle and has no menu without a group")
    func groupHandleView() throws {
        let bars = try Bars([World.item("Alpha")])
        let handle = try LayoutBarGroupHandleView(sourceContainer: bars.container(), sourceSection: .visible, memberIdentifiers: [])
        #expect(LayoutBarGroupHandleView.preferredSize(height: 10).height == 18)
        #expect(LayoutBarGroupHandleView.preferredSize(height: 30).height == 30)
        #expect(handle.isAccessibilityElement())
        #expect(handle.accessibilityRole() == .handle)
        #expect(handle.accessibilityLabel()?.isEmpty == false)
        #expect(!handle.accessibilityPerformShowMenu(), "no group, no menu")
        #expect(handle.toolTip?.isEmpty == false)

        handle.frame = CGRect(x: 0, y: 0, width: 11, height: 18)
        let bitmap = try #require(handle.bitmapImageRepForCachingDisplay(in: handle.bounds))
        handle.cacheDisplay(in: handle.bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        #expect(Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh).contains { $0 != 0 })
        handle.resetCursorRects()

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: bars.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        handle.mouseDown(with: event)
        handle.mouseDragged(with: event)
    }

    @Test("A group is drawn as one cluster, snapshotted together and dragged as one block")
    func groupCluster() throws {
        let pair = Self.pair()
        let alpha = World.item("Alpha")
        let bars = try Bars(pair + [alpha])
        let container = try bars.container()
        let groups = container.resolvedGroups()
        #expect(groups.count == 1)
        #expect(container.resolvedGroups().map(\.memberIndices) == groups.map(\.memberIndices), "the groups are memoized")

        let views = try bars.itemViews()
        let pairViews = views.filter { view in pair.contains { $0.tag == view.item.tag } }
        let loneView = try #require(views.first { $0.item.tag == alpha.tag })
        #expect(container.dragUnitViews(for: pairViews[0]).count == 2)
        #expect(container.dragUnitViews(for: loneView).count == 1)
        #expect(container.dragUnitViews(for: LayoutBarNewItemsBadgeView()).count == 1, "a view not in the bar moves alone")

        let snapshot = try #require(container.snapshotCluster(memberIdentifiers: pair.map(\.uniqueIdentifier)))
        #expect(snapshot.rect.width >= pairViews.map(\.frame.width).reduce(0, +))
        #expect(container.snapshotCluster(memberIdentifiers: ["missing"]) == nil)

        #expect(container.orderedItemsForMenu().count == 3)
        #expect(container.closestView(toX: loneView.frame.midX) === loneView)
        #expect(container.closestView(toX: loneView.frame.midX, excludingBadge: true) === loneView)

        container.groupDropMarkerX = loneView.frame.minX
        let bitmap = try #require(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        #expect(Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh).contains { $0 != 0 }, "the cluster and marker are drawn")
        container.groupDropMarkerX = nil
    }

    @Test("A resized tile reflows the bar, and a tile from elsewhere is ignored")
    func resizedTileReflows() throws {
        let items = ["A", "B"].map(World.item)
        let bars = try Bars(items)
        let container = try bars.container()
        let views = try bars.itemViews()
        let before = views[1].frame.minX
        views[0].setFrameSize(NSSize(width: views[0].frame.width + 20, height: views[0].frame.height))
        container.itemPreferredSizeDidChange(views[0])
        container.layoutSubtreeIfNeeded()
        #expect(views[1].frame.minX > before, "the next tile moves over")
        container.itemPreferredSizeDidChange(LayoutBarNewItemsBadgeView())
    }

    @Test("A bar picks up a new item once the menu bar reports a change")
    func rebuildsOnSystemChanges() async throws {
        let bars = try Bars([World.item("A")])
        let beta = World.item("B")
        bars.world.appState.itemManager.itemCache[.visible] = bars.world.appState.itemManager.itemCache[.visible] + [beta]
        NotificationCenter.default.post(name: .menuBarAgentPositionsDidChange, object: nil)
        for _ in 0 ..< 50 where try !bars.itemViews().contains(where: { $0.item.tag == beta.tag }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try bars.itemViews().contains { $0.item.tag == beta.tag })
        bars.window.contentView = nil
    }
}
