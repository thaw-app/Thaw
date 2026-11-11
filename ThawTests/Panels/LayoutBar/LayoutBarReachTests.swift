//
//  LayoutBarReachTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// A long section's bar scrolls, and a selection made anywhere brings its item into view.
@MainActor
@Suite("Layout bar reach", .serialized, .scratchDefaults)
struct LayoutBarReachTests {
    private typealias World = LayoutEditorWorld

    /// One Visible bar of many items in a narrow offscreen window.
    @MainActor
    private final class LongBar {
        let world = World()
        let selection = LayoutSelectionModel { _ in }
        let items: [MenuBarItem]
        let window: NSWindow
        let scrollView: LayoutBarScrollView
        let container: LayoutBarContainer

        init(count: Int, width: CGFloat = 600) throws {
            items = (0 ..< count).map { World.item("Reach\($0)") }
            world.seat(items, in: .visible)
            scrollView = LayoutBarScrollView(appState: world.appState, section: .visible, selection: selection)
            let frame = CGRect(x: 0, y: 0, width: width, height: 48)
            window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = scrollView
            scrollView.translatesAutoresizingMaskIntoConstraints = true
            scrollView.frame = frame
            container = try #require(scrollView.documentView?.subviews.lazy.compactMap { $0 as? LayoutBarContainer }.first)
            container.rebuildViews()
            container.syncSelection()
            window.layoutIfNeeded()
        }

        /// The bar's item views, leading to trailing.
        var views: [LayoutBarItemView] {
            scrollView.arrangedViews.compactMap { $0 as? LayoutBarItemView }
        }

        func select(_ index: Int) {
            selection.click(views[index].item.uniqueIdentifier, in: .visible, kind: .replace)
        }

        func isShown(_ index: Int) throws -> Bool {
            let view = views[index]
            let rect = scrollView.contentView.convert(view.bounds, from: view)
            return scrollView.contentView.bounds.contains(rect)
        }

        func settle() async {
            for _ in 0 ..< 5 {
                await Task.yield()
            }
        }
    }

    @Test("A bar wider than its window scrolls instead of clipping, starting at the trailing end like the menu bar")
    func longBarScrolls() throws {
        let bar = try LongBar(count: 165)
        let document = try #require(bar.scrollView.documentView)
        #expect(document.frame.width > bar.scrollView.contentView.bounds.width)
        #expect(bar.container.rowWidth == nil, "Settings' bars keep one row")
        #expect(bar.scrollView.hasHorizontalScroller)
        #expect(try bar.isShown(164))
        #expect(try !bar.isShown(0))
    }

    @Test("Selecting an item off screen scrolls it into view, and selecting a shown one leaves the bar where it is")
    func selectionScrollsIntoView() async throws {
        let bar = try LongBar(count: 165)
        bar.select(0)
        await bar.settle()
        #expect(try bar.isShown(0))

        let origin = bar.scrollView.contentView.bounds.origin
        bar.select(1)
        await bar.settle()
        #expect(bar.scrollView.contentView.bounds.origin == origin)

        bar.select(120)
        await bar.settle()
        #expect(try bar.isShown(120))
    }

    @Test("Reveal origin", arguments: [
        // Already shown: no scroll.
        (CGRect(x: 100, y: 0, width: 24, height: 24), CGFloat?.none),
        // Off the leading edge: its leading edge becomes the clip's.
        (CGRect(x: -300, y: 0, width: 24, height: 24), CGFloat?.some(-300)),
        // Off the trailing edge: its trailing edge becomes the clip's.
        (CGRect(x: 700, y: 0, width: 24, height: 24), CGFloat?.some(124)),
        // Past the document's start: clamped to it.
        (CGRect(x: -1100, y: 0, width: 24, height: 24), CGFloat?.some(-1000)),
    ])
    func revealOrigin(target: CGRect, expected: CGFloat?) {
        let visible = CGRect(x: 0, y: 0, width: 600, height: 48)
        let document = CGRect(x: -1000, y: 0, width: 1800, height: 48)
        #expect(LayoutBarScrollView.revealOriginX(for: target, visible: visible, document: document) == expected)
    }

    @Test("165 items build and lay out quickly")
    func longBarBuildsQuickly() throws {
        let clock = ContinuousClock()
        var bar: LongBar?
        let elapsed = try clock.measure { bar = try LongBar(count: 165) }
        #expect(bar?.container.arrangedViews.count == 165)
        #expect(elapsed < .seconds(2), "165 items took \(elapsed)")
    }
}
