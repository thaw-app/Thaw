//
//  ThawSidebarTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import ThawUI

@Suite("Sidebar")
struct ThawSidebarTests {
    private typealias Row = ThawSidebarRow<String>

    private static let rows: [Row] = [
        .page("general"),
        .heading("Search"),
        .page("commands"),
        .gap,
        .page("about"),
    ]

    @Test("A row's page is its own, and a heading or gap has none")
    func rowPage() {
        #expect(Row.page("general").page == "general")
        #expect(Row.heading("Search").page == nil)
        #expect(Row.gap.page == nil)
    }

    @Test("The arrow keys step between pages, past headings and gaps")
    func movesPastHeadingsAndGaps() {
        #expect(Row.page(moving: .down, from: "general", in: Self.rows) == "commands")
        #expect(Row.page(moving: .down, from: "commands", in: Self.rows) == "about")
        #expect(Row.page(moving: .up, from: "about", in: Self.rows) == "commands")
    }

    @Test("The arrow keys stop at either end")
    func stopsAtTheEnds() {
        #expect(Row.page(moving: .up, from: "general", in: Self.rows) == nil)
        #expect(Row.page(moving: .down, from: "about", in: Self.rows) == nil)
    }

    @Test("Left, right and a page outside the sidebar go nowhere")
    func otherMovesGoNowhere() {
        #expect(Row.page(moving: .left, from: "commands", in: Self.rows) == nil)
        #expect(Row.page(moving: .right, from: "commands", in: Self.rows) == nil)
        #expect(Row.page(moving: .down, from: "elsewhere", in: Self.rows) == nil)
    }

    @Test("Repeated gaps and headings, and a page sharing a heading's name, keep separate identities")
    func identitiesAreUnique() {
        let rows: [Row] = [.gap, .page("Search"), .heading("Search"), .gap, .heading("Search")]
        let ids = Row.identified(rows).map(\.id)
        #expect(Set(ids).count == rows.count)
    }

    @Test("A page keeps its identity when rows around it come and go")
    func pageIdentityIsStable() throws {
        let before = try #require(Row.identified([.page("a")]).first?.id)
        let after = try #require(Row.identified([.heading("New"), .gap, .page("a")]).last?.id)
        #expect(before == after)
    }

    @Test("The accent fill is the default, and an app can give its own colours")
    func colours() {
        #expect(ThawSidebarColors().selection == .tinted(.accentColor))
        let custom = ThawSidebarColors(selection: .flat(fill: .gray, edge: .black), title: .red, dimmedTitle: .green, icon: .blue)
        #expect(custom.selection == .flat(fill: .gray, edge: .black))
        #expect(custom.title == .red)
        #expect(custom.dimmedTitle == .green)
        #expect(custom.icon == .blue)
    }
}
