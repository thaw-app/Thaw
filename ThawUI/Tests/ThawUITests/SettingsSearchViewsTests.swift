//
//  SettingsSearchViewsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Settings search views")
struct SettingsSearchViewsTests {
    private struct Entry: Identifiable {
        let id: String
    }

    private struct ResultGroup: Identifiable {
        let id: Int
        let entries: [Entry]
    }

    private static let groups = [
        ResultGroup(id: 1, entries: [Entry(id: "a"), Entry(id: "b")]),
        ResultGroup(id: 2, entries: [Entry(id: "c")]),
    ]

    private static func fittingSize(_ view: some View) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    /// Lays the view out in a window of its own, so its body and its hidden buttons run.
    private static func draw(_ view: some View) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view.frame(width: 400, height: 300)))
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @Test("Hover washes a row, a press deepens it, and at rest it has none")
    func washStrength() {
        typealias Style = SettingsSearchResultButtonStyle
        #expect(Style.strength(isPressed: false, isHovering: false) == nil)
        #expect(Style.strength(isPressed: false, isHovering: true) == .hover)
        #expect(Style.strength(isPressed: true, isHovering: false) == .selected)
        #expect(Style.strength(isPressed: true, isHovering: true) == .selected)
    }

    @Test("A row grows for its section and its description")
    func rowLines() {
        func height(_ text: SettingsSearchResultText) -> CGFloat {
            Self.fittingSize(SettingsSearchResultRow(text) {}.frame(width: 320)).height
        }
        let title = Text(verbatim: "Title")
        let bare = height(SettingsSearchResultText(title: title))
        let sectioned = height(SettingsSearchResultText(title: title, section: Text(verbatim: "Section")))
        let full = height(SettingsSearchResultText(title: title, section: Text(verbatim: "Section"), detail: Text(verbatim: "Detail")))
        #expect(sectioned > bare)
        #expect(full > sectioned)
    }

    @Test("The highlight does not move a row or change its size")
    func highlightKeepsSize() {
        let text = SettingsSearchResultText(title: Text(verbatim: "Title"))
        let plain = Self.fittingSize(SettingsSearchResultRow(text) {}.frame(width: 320))
        let highlighted = Self.fittingSize(SettingsSearchResultRow(text, isHighlighted: true, hoverTint: .primary) {}.frame(width: 320))
        #expect(plain == highlighted)
    }

    @Test("The list asks the app for every group's entries, titles and icons")
    func listAsksTheApp() {
        var titled: [Int] = []
        var worded: [String] = []
        let list = SettingsSearchResultsList(
            groups: Self.groups,
            entries: \.entries,
            highlighted: "b",
            onSelect: { _ in },
            groupTitle: { group in
                titled.append(group.id)
                return Text(verbatim: "Group \(group.id)")
            },
            result: { entry in
                worded.append(entry.id)
                return SettingsSearchResultText(title: Text(verbatim: entry.id))
            },
            groupIcon: { _ in Image(systemName: "gear") }
        )
        _ = Self.draw(list)
        #expect(Set(titled) == [1, 2])
        #expect(Set(worded) == ["a", "b", "c"])
    }

    @Test("The list draws a header above its results")
    func listHeader() {
        var drewHeader = false
        let list = SettingsSearchResultsList(
            groups: [ResultGroup](),
            entries: \.entries,
            onSelect: { _ in },
            groupTitle: { _ in Text(verbatim: "") },
            result: { SettingsSearchResultText(title: Text(verbatim: $0.id)) },
            groupIcon: { _ in EmptyView() },
            header: {
                DrawProbe { drewHeader = true }
                SettingsSearchResultCount(Text(verbatim: "3 results"))
            }
        )
        _ = Self.draw(list)
        #expect(drewHeader)
    }

    @Test("The arrow keys ask the app to move, up by one and down by one")
    func keyboardMoves() {
        var moves: [Int] = []
        var submitted = 0
        let keyboard = SettingsSearchKeyboard(
            isSearching: true,
            previousLabel: "Up",
            nextLabel: "Down",
            move: { moves.append($0) },
            submit: { submitted += 1 }
        )
        keyboard.move(-1)
        keyboard.move(1)
        keyboard.submit()
        #expect(moves == [-1, 1])
        #expect(submitted == 1)
    }

    @Test("The search field holds the app's words")
    func fieldWords() {
        let keyboard = SettingsSearchKeyboard(isSearching: false, previousLabel: "Up", nextLabel: "Down", move: { _ in }, submit: {})
        let field = SettingsSearchField(text: .constant(""), placement: .sidebar, prompt: "Look", findLabel: "Seek", keyboard: keyboard)
        #expect(field.prompt == "Look")
        #expect(field.findLabel == "Seek")
        #expect(field.keyboard?.previousLabel == "Up")
        #expect(field.keyboard?.nextLabel == "Down")
    }

    @Test("A split view takes the search field with or without the arrow keys", arguments: [false, true])
    func fieldDraws(withKeyboard: Bool) {
        let keyboard = SettingsSearchKeyboard(isSearching: true, previousLabel: "Up", nextLabel: "Down", move: { _ in }, submit: {})
        let view = NavigationSplitView {
            Text(verbatim: "Sidebar")
        } detail: {
            Text(verbatim: "Detail")
        }
        .settingsSearchField(text: .constant("query"), placement: .sidebar, prompt: "Look", findLabel: "Seek", keyboard: withKeyboard ? keyboard : nil)
        #expect(Self.draw(view).fittingSize.width > 0)
    }
}

/// Reports that SwiftUI asked for its body, which a list draws only with its header.
private struct DrawProbe: View {
    let onDraw: () -> Void

    var body: some View {
        onDraw()
        return Color.clear.frame(width: 1, height: 1)
    }
}
