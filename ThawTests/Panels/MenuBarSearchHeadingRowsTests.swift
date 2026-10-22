//
//  MenuBarSearchHeadingRowsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// The search panel's group headings, laid out off screen.
@MainActor
@Suite("Search panel headings")
struct MenuBarSearchHeadingRowsTests {
    private func fittingSize(of row: MenuBarSearchListContent) -> CGSize {
        let host = NSHostingView(rootView: row.frame(width: 300))
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test("A section heading and a plain heading take the same room, with space above and below the text")
    func headingsMatch() {
        let section = fittingSize(of: .header(.hidden))
        let label = fittingSize(of: .label("Recent"))
        #expect(section.height == label.height)
        #expect(section.height > 16, "the heading carries padding around its text")
        #expect(section.width == 300, "a heading spans the row")
    }
}
