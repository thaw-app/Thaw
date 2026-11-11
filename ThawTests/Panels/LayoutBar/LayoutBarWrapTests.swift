//
//  LayoutBarWrapTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// A drag from inside the bar, at a fixed spot in the window.
@MainActor
private final class RowDrag: NSObject, NSDraggingInfo {
    let draggingSource: Any?
    let draggingLocation: NSPoint
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
        NSPasteboard(name: NSPasteboard.Name("ThawTests.LayoutBarWrap"))
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

/// The Layout window's bars wrap a long section onto rows, and drags read the rows as one bar.
@MainActor
@Suite("Layout bar rows", .serialized, .scratchDefaults)
struct LayoutBarWrapTests {
    private typealias World = LayoutEditorWorld

    /// One Visible bar that wraps, in a narrow offscreen window. A wrapped bar draws no notch.
    @MainActor
    private final class WrappedBar {
        let world = World()
        let window: NSWindow
        let scrollView: LayoutBarScrollView
        let container: LayoutBarContainer

        init(count: Int, width: CGFloat = 300) throws {
            world.seat((0 ..< count).map { World.item("Row\($0)") }, in: .visible)
            scrollView = LayoutBarScrollView(appState: world.appState, section: .visible, wrapsRows: true)
            container = try #require(scrollView.documentView?.subviews.lazy.compactMap { $0 as? LayoutBarContainer }.first)
            container.rebuildViews()
            let frame = CGRect(x: 0, y: 0, width: width, height: scrollView.height(forWidth: width))
            window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = scrollView
            scrollView.translatesAutoresizingMaskIntoConstraints = true
            scrollView.frame = frame
            window.layoutIfNeeded()
        }

        var views: [LayoutBarArrangedView] {
            container.arrangedViews
        }

        func windowPoint(_ point: CGPoint) -> NSPoint {
            container.convert(point, to: nil)
        }

        func indices(onRow line: Int) -> [Int] {
            container.flow.row.indices.filter { container.flow.row[$0] == line }
        }
    }

    @Test("Items wrap onto rows inside the bar's width, and the bar is as tall as its rows")
    func wraps() throws {
        let bar = try WrappedBar(count: 40)
        let flow = bar.container.flow
        #expect(flow.rowCount > 1)
        #expect(bar.container.frame.width <= bar.scrollView.bounds.width)
        for view in bar.views {
            #expect(bar.container.bounds.contains(view.frame), "\(view.frame) is outside \(bar.container.bounds)")
        }
        #expect(!bar.scrollView.hasHorizontalScroller)
        #expect(bar.scrollView.intrinsicContentSize.height == flow.height + 24)
        #expect(bar.scrollView.height(forWidth: 3000) == LayoutBarScrollView.barHeight, "one row keeps the single-row bar's height")
        #expect(bar.scrollView.height(forWidth: 150) > bar.scrollView.height(forWidth: 300))
    }

    @Test("The end of one row and the start of the next drop in the same place")
    func dropAtRowEnds() throws {
        let bar = try WrappedBar(count: 40)
        let firstRow = bar.indices(onRow: 0)
        let secondRow = bar.indices(onRow: 1)
        let rowY = { (line: Int) in bar.container.flow.band(ofRow: line, width: bar.container.bounds.width).midY }

        let endOfFirst = bar.windowPoint(CGPoint(x: bar.container.bounds.maxX - 1, y: rowY(0)))
        let startOfSecond = bar.windowPoint(CGPoint(x: 0, y: rowY(1)))
        let atEnd = bar.container.groupDropDestination(atX: bar.container.sweepX(at: endOfFirst))
        let atStart = bar.container.groupDropDestination(atX: bar.container.sweepX(at: startOfSecond))
        #expect(atEnd.boundary == firstRow.count, "after the first row's last item")
        #expect(atStart.boundary == firstRow.count, "before the second row's first item")

        let middle = try #require(secondRow.dropFirst().first)
        let onMiddle = bar.windowPoint(CGPoint(x: bar.views[middle].frame.midX - 1, y: rowY(1)))
        #expect(bar.container.closestView(toX: bar.container.sweepX(at: onMiddle)) === bar.views[middle])
    }

    @Test("Dragging an item onto a lower row moves it there")
    func dragAcrossRows() throws {
        let bar = try WrappedBar(count: 40)
        let source = bar.views[0]
        let target = try #require(bar.indices(onRow: 2).dropFirst().first)
        let targetView = bar.views[target]
        let location = bar.windowPoint(CGPoint(x: targetView.frame.midX, y: targetView.frame.midY))
        bar.container.animatesNextLayoutPass = false
        bar.container.handleDrag(RowDrag(source: source, location: location), phase: .entered)
        #expect(bar.views.firstIndex(of: source) == target, "the item takes the slot it was dragged onto")
        #expect(bar.views.firstIndex(of: targetView) == target - 1, "and the item it passed moves back one")
        #expect(bar.container.dropMarker() == nil, "no gap is open, since the item is not a placeholder here")
    }

    @Test("The group marker is drawn on the row its slot is on")
    func markerOnItsRow() throws {
        let bar = try WrappedBar(count: 40)
        let secondRow = bar.indices(onRow: 1)
        let point = bar.windowPoint(CGPoint(x: bar.views[secondRow[1]].frame.minX + 1, y: bar.container.flow.band(ofRow: 1, width: 1).midY))
        bar.container.showGroupDropMarker(at: point)
        let marker = try #require(bar.container.dropMarker())
        #expect(marker.band == bar.container.flow.band(ofRow: 1, width: bar.container.bounds.width))
        #expect(abs(marker.x - bar.views[secondRow[1]].frame.minX) <= 1)
    }

    @Test("165 items wrap and relayout quickly when the width changes")
    func relayoutTime() throws {
        let bar = try WrappedBar(count: 165, width: 900)
        let clock = ContinuousClock()
        // The fastest of three, so a stall in the parallel suite can't fail it.
        let elapsed = (0 ..< 3).map { _ in
            bar.container.rowWidth = 900
            return clock.measure {
                for width in stride(from: CGFloat(880), through: 400, by: -40) {
                    bar.container.rowWidth = width
                }
            }
        }.min() ?? .zero
        #expect(bar.container.flow.rowCount > 5)
        #expect(elapsed < .milliseconds(500), "13 relayouts of 165 items took \(elapsed)")
    }

    @Test("The bar in SwiftUI grows as items arrive, at the width it is given")
    func hostedHeight() async throws {
        let world = World()
        world.seat((0 ..< 4).map { World.item("Hosted\($0)") }, in: .visible)
        let bar = LayoutBar(imageCache: world.appState.imageCache, section: .visible, chrome: .bare, wrapsRows: true)
            .frame(width: 300)
            .environment(world.appState)
        let host = NSHostingView(rootView: bar)
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let short = host.fittingSize.height
        #expect(short == LayoutBarScrollView.barHeight)

        world.seat((0 ..< 60).map { World.item("Hosted\($0)") }, in: .visible)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > short, "the bar asks for its new rows")
    }

    @Test("The bars' pane fits the bars, up to its share of the window")
    func barsHeightCap() {
        #expect(LayoutDashboardMetrics.barsHeight(fitting: nil, sections: 3, available: nil) == LayoutDashboardMetrics.barsHeight(sections: 3))
        #expect(LayoutDashboardMetrics.barsHeight(fitting: 200, sections: 3, available: 1000) == 200 + LayoutDashboardMetrics.barsChrome)
        #expect(LayoutDashboardMetrics.barsHeight(fitting: 900, sections: 3, available: 1000) == 1000 * LayoutDashboardMetrics.barsMaxShare)
        #expect(
            LayoutDashboardMetrics.barsHeight(fitting: 900, sections: 3, available: 100) == LayoutDashboardMetrics.barsHeight(sections: 1),
            "a tiny window still shows a whole bar"
        )
    }

    @Test("A Layout window of 165 wrapped items settles and then stays idle")
    func idleWindow() async throws {
        let world = World()
        world.seat((0 ..< 165).map { World.item("Idle\($0)") }, in: .visible)
        let target = LayoutEditTarget(displayUUID: "D1", displayID: 1, spaceKey: "S1", displayName: "Display", spaceName: "Desktop 1")
        let model = LayoutDashboardModel(undoManager: world.appState.layoutUndo, readTarget: { target })
        let clock = ContinuousClock()
        let host = NSHostingView(rootView: LayoutDashboardView(appState: world.appState, model: model))
        let built = clock.measure {
            host.frame = NSRect(origin: .zero, size: LayoutDashboardMetrics.windowMinSize)
            host.layoutSubtreeIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()

        let bars = Self.subviews(of: host).compactMap { $0 as? LayoutBarScrollView }
        #expect(!bars.isEmpty)
        var changes = 0
        let tokens = bars.flatMap { bar -> [NSObjectProtocol] in
            bar.postsFrameChangedNotifications = true
            let views: [NSView] = [bar] + (bar.documentView.map { [$0] } ?? [])
            return views.map { view in
                NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: nil) { _ in
                    MainActor.assumeIsolated { changes += 1 }
                }
            }
        }
        defer { tokens.forEach(NotificationCenter.default.removeObserver) }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        #expect(changes == 0, "the bars kept resizing while idle")
    }

    private static func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews(of:))
    }
}
