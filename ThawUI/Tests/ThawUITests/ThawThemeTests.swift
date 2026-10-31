//
//  ThawThemeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import ThawUI

@Suite("Theme")
@MainActor
struct ThawThemeTests {
    private static let gray = ThawSidebarColors.Selection.flat(fill: .primary.opacity(0.1), edge: .primary.opacity(0.08))
    private static let size = CGSize(width: 220, height: 60)

    private static func sidebar(colors: ThawSidebarColors? = nil) -> some View {
        ThawSidebar(
            rows: [.page("general"), .page("about")],
            current: "general",
            colors: colors,
            select: { _ in },
            title: { Text(verbatim: $0) },
            icon: { _ in Image(systemName: "gear") }
        )
        .frame(width: size.width, height: size.height)
    }

    private static func pixels(_ view: some View) throws -> Data {
        try OffscreenRender(view.frame(width: size.width, height: size.height), size: size).pixels()
    }

    @Test("With no theme set, the controls take the accent colour")
    func standardLook() {
        let theme = EnvironmentValues().thawTheme
        #expect(theme == ThawTheme())
        #expect(theme.selection == .tinted(.accentColor))
        #expect(theme.hoverTint == .accentColor)
    }

    @Test("An app can give its own selection and hover tint")
    func customValues() {
        let theme = ThawTheme(selection: Self.gray, hoverTint: .primary)
        #expect(theme.selection == Self.gray)
        #expect(theme.hoverTint == .primary)
        #expect(theme != ThawTheme())
    }

    @Test("The modifier reaches the views under it")
    func modifierSetsTheEnvironment() async {
        let probe = ThemeProbe()
        let theme = ThawTheme(selection: Self.gray, hoverTint: .primary)
        let render = OffscreenRender(ThemeReader(probe: probe).thawTheme(theme), size: Self.size)
        await render.settle { probe.theme != nil }
        #expect(probe.theme == theme)
    }

    @Test("The sidebar draws the theme's selection, the same as being handed it")
    func sidebarReadsTheTheme() throws {
        let themed = try Self.pixels(Self.sidebar().thawTheme(ThawTheme(selection: Self.gray)))
        let handed = try Self.pixels(Self.sidebar(colors: ThawSidebarColors(selection: Self.gray)))
        let plain = try Self.pixels(Self.sidebar())
        #expect(themed == handed)
        #expect(themed != plain)
    }

    @Test("A sidebar handed its colours keeps them under any theme")
    func handedColoursWin() throws {
        let handed = try Self.pixels(Self.sidebar(colors: ThawSidebarColors()).thawTheme(ThawTheme(selection: Self.gray)))
        let plain = try Self.pixels(Self.sidebar())
        #expect(handed == plain)
    }

    @Test("With no theme the sidebar looks as it did")
    func sidebarDefault() throws {
        let plain = try Self.pixels(Self.sidebar())
        let accent = try Self.pixels(Self.sidebar(colors: ThawSidebarColors(selection: .tinted(.accentColor))))
        #expect(plain == accent)
    }

    @Test("A selected row takes the theme's flat fill and edge, drawn as they always were")
    func selectedRowFlat() throws {
        let themed = try Self.pixels(Color.clear.selectedRowBackground(true).thawTheme(ThawTheme(selection: Self.gray)))
        let drawn = try Self.pixels(
            Color.clear.background {
                ListStyle.rowShape
                    .fill(Color.primary.opacity(0.1))
                    .overlay(ListStyle.rowShape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            }
        )
        #expect(themed == drawn)
    }

    @Test("A selected row takes the theme's tint, and one not selected draws nothing")
    func selectedRowTinted() throws {
        let themed = try Self.pixels(Color.clear.selectedRowBackground(true))
        let drawn = try Self.pixels(Color.clear.thawSelectedFill(true, in: ListStyle.rowShape))
        let off = try Self.pixels(Color.clear.selectedRowBackground(false))
        let nothing = try Self.pixels(Color.clear)
        #expect(themed == drawn)
        #expect(off == nothing)
    }
}

@MainActor
private final class ThemeProbe {
    var theme: ThawTheme?
}

private struct ThemeReader: View {
    @Environment(\.thawTheme) private var theme
    let probe: ThemeProbe

    var body: some View {
        Color.clear.onAppear { probe.theme = theme }
    }
}
