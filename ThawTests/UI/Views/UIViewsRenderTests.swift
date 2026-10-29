//
//  UIViewsRenderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// Holds a value a view writes through a binding, so the test sees the write.
@MainActor
private final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }

    var binding: Binding<Value> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}

/// Shared views from Thaw/UI/Views, laid out and drawn off screen.
@Suite("Shared UI views", .serialized)
@MainActor
struct UIViewsRenderTests {
    private func fittingHeight(of view: some View, width: CGFloat) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: width))
        host.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    private static func path(_ count: Int) -> [ReadingPathItem] {
        (0 ..< count).map { ReadingPathItem(id: "v\($0)", label: "Version \($0)") }
    }

    @Test("A reading page chromes its window: transparent title bar, hidden title, clear background")
    func readingPageChromesWindow() async throws {
        let selection = Box<String?>("v0")
        let page = ReadingPage(
            path: Self.path(3),
            selection: selection.binding,
            title: Text(verbatim: "What's New"),
            subtitle: Text(verbatim: "Released today")
        ) {
            ReadingParagraph("A paragraph of text.")
            ReadingParagraph(AttributedString("Another paragraph."))
        } links: {
            Button("Website") { /* No link to open in a test. */ }
        }
        let render = OffscreenRender(page, size: CGSize(width: 860, height: 780))
        let window = try #require(render.host.window)
        await render.settle { window.titlebarAppearsTransparent }
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.backgroundColor == .clear)
        #expect(!window.isOpaque)
        #expect(try render.pixels().contains { $0 != 0 })
        #expect(selection.value == "v0", "drawing does not change the selection")
    }

    @Test("A long path folds its older stops into a menu without growing the page")
    func readingPageFoldsLongPath() {
        let selection = Box<String?>(nil)
        func page(_ count: Int) -> some View {
            ReadingPage(
                path: Self.path(count),
                selection: selection.binding,
                visiblePathCount: 2,
                title: Text(verbatim: "Changelog")
            ) {
                EmptyView()
            } links: {
                EmptyView()
            }
        }
        let short = NSHostingView(rootView: page(2))
        let long = NSHostingView(rootView: page(8))
        short.frame = CGRect(x: 0, y: 0, width: 860, height: 780)
        long.frame = short.frame
        short.layoutSubtreeIfNeeded()
        long.layoutSubtreeIfNeeded()
        #expect(long.fittingSize.width >= 640)
        #expect(short.fittingSize.height == long.fittingSize.height)
    }

    @Test("A paragraph wraps onto more lines in a narrower column")
    func paragraphWraps() {
        let text = String(repeating: "word ", count: 80)
        let wide = fittingHeight(of: ReadingParagraph(text), width: 900)
        let narrow = fittingHeight(of: ReadingParagraph(text), width: 200)
        #expect(narrow > wide)
    }

    @Test("Slider rows share the widest label under sliderLabelAlignment")
    func sliderRowsShareLabelWidth() throws {
        let short = Box(1.0)
        let long = Box(2.5)
        let rows = VStack {
            SecondsSliderRow("A", value: short.binding, in: 0 ... 5, step: 0.5)
            SliderRow("A much longer slider label", value: long.binding, in: 0 ... 10, step: 1) { value in
                Text(verbatim: "\(Int(value))")
            }
        }
        .sliderLabelAlignment()
        .frame(width: 520)
        let render = OffscreenRender(rows, size: CGSize(width: 520, height: 120))
        #expect(try render.pixels().contains { $0 != 0 })
        #expect(short.value == 1.0, "laying out does not move the slider")
        #expect(long.value == 2.5)
        let unaligned = fittingHeight(of: SecondsSliderRow("A", value: short.binding, in: 0 ... 5, step: 0.5), width: 520)
        #expect(unaligned > 0)
    }

    @Test("The more-actions menu draws its ellipsis button")
    func moreActionsMenu() throws {
        let menu = MoreActionsMenu(label: "More actions") {
            Button("Rename") { /* Not pressed in a test. */ }
        }
        let render = OffscreenRender(menu.frame(width: 60, height: 30), size: CGSize(width: 60, height: 30))
        #expect(try render.pixels().contains { $0 != 0 })
    }

    @Test("The editor chrome adds a title bar and a bottom bar around its content, and a subtitle adds height")
    func editorPanelChrome() throws {
        func chrome(subtitle: LocalizedStringKey?) -> some View {
            EditorPanelChrome("Layout", subtitle: subtitle) {
                Color.clear.frame(height: 100)
            } bottomBar: {
                Button("Done") { /* Not pressed in a test. */ }
            }
        }
        let bare = fittingHeight(of: Color.clear.frame(height: 100), width: 400)
        let titled = fittingHeight(of: chrome(subtitle: nil), width: 400)
        let subtitled = fittingHeight(of: chrome(subtitle: "Arrange your items"), width: 400)
        #expect(titled > bare)
        #expect(subtitled > titled)
        let render = OffscreenRender(chrome(subtitle: "Arrange your items").frame(width: 400, height: 260), size: CGSize(width: 400, height: 260))
        #expect(try render.pixels().contains { $0 != 0 })
    }
}
