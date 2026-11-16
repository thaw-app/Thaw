//
//  ItemEnumerationDumpDrawnBarsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw
import ThawAXCore

/// The item dump records where MenuBarAgent draws each item, beside the frame its app reports.
@MainActor
@Suite("Item dump drawn bars")
struct ItemEnumerationDumpDrawnBarsTests {
    private static func entry(_ pid: pid_t, x: CGFloat, width: CGFloat) -> MenuBarAgentWindow.Entry {
        MenuBarAgentWindow.Entry(ownerPID: pid, frame: CGRect(x: x, y: 0, width: width, height: 30))
    }

    @Test("Each bar lists its items left to right, with the app that owns each")
    func barsListTheirItems() {
        let bars = [
            MenuBarAgentWindow.Bar(
                frame: CGRect(x: 0, y: 0, width: 1920, height: 30),
                entries: [Self.entry(20, x: 1495, width: 38), Self.entry(10, x: 1457, width: 38), Self.entry(1, x: 1740, width: 36)]
            ),
        ]
        let names: [pid_t: String] = [10: "com.example.left", 20: "com.example.right"]

        let drawn = ItemEnumerationDump.drawnBars(from: bars) { names[$0] }

        #expect(drawn.count == 1)
        #expect(drawn[0].frameWidth == 1920)
        #expect(drawn[0].items.map(\.processIdentifier) == [10, 20, 1])
        #expect(drawn[0].items.map(\.bundleIdentifier) == ["com.example.left", "com.example.right", nil])
        #expect(drawn[0].items[0].frameX == 1457)
        #expect(drawn[0].items[0].frameWidth == 38)
    }

    @Test("A bar whose own frame could not be read still lists its items")
    func unreadableBarFrame() {
        let drawn = ItemEnumerationDump.drawnBars(from: [.init(frame: nil, entries: [Self.entry(10, x: 100, width: 24)])]) { _ in nil }

        #expect(drawn[0].frameX == nil)
        #expect(drawn[0].items.count == 1)
    }

    @Test("A report written before drawn bars were recorded still decodes, and a new one keeps them")
    func reportsDecodeWithAndWithoutDrawnBars() throws {
        let old = Data(#"{"timestamp":"2026-11-16T03:01:37Z","apps":[],"discovery":[]}"#.utf8)
        #expect(try JSONDecoder().decode(ItemEnumerationDump.Report.self, from: old).drawnBars == nil)

        let bar = ItemEnumerationDump.drawnBars(from: [.init(frame: CGRect(x: 0, y: 0, width: 1800, height: 39), entries: [Self.entry(10, x: 1264, width: 38)])]) { _ in "com.example.item" }
        let report = ItemEnumerationDump.Report(timestamp: "now", apps: [], discovery: nil, drawnBars: bar)
        let decoded = try JSONDecoder().decode(ItemEnumerationDump.Report.self, from: JSONEncoder().encode(report))
        #expect(decoded.drawnBars == bar)
    }
}
