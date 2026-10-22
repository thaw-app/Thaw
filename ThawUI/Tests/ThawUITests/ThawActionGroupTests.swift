//
//  ThawActionGroupTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Action group")
struct ThawActionGroupTests {
    /// The size the view lays out at, after drawing it once offscreen.
    private static func renderedSize(of view: some View) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        return host.fittingSize
    }

    @Test("Pressing fills darker than hovering, and a disabled button shows no hover")
    func fillOpacity() {
        #expect(ThawGroupedButtonStyle.fillOpacity(isPressed: true, isHovered: false, isEnabled: true) == 0.14)
        #expect(ThawGroupedButtonStyle.fillOpacity(isPressed: true, isHovered: true, isEnabled: true) == 0.14)
        #expect(ThawGroupedButtonStyle.fillOpacity(isPressed: false, isHovered: true, isEnabled: true) == 0.07)
        #expect(ThawGroupedButtonStyle.fillOpacity(isPressed: false, isHovered: true, isEnabled: false) == nil)
        #expect(ThawGroupedButtonStyle.fillOpacity(isPressed: false, isHovered: false, isEnabled: true) == nil)
    }

    @Test("Each button adds width, and the capsule is at least a grouped button tall")
    func layout() {
        let one = Self.renderedSize(of: ThawActionGroup {
            Button("First") {}
        }.buttonStyle(.thawGrouped))
        let two = Self.renderedSize(of: ThawActionGroup {
            Button("First") {}
            Button("Second") {}
        }.buttonStyle(.thawGrouped))
        #expect(two.width > one.width)
        #expect(one.height >= 26)
    }

    @Test("A disabled group still lays out")
    func disabled() {
        let size = Self.renderedSize(of: ThawActionGroup {
            Button("First") {}
        }.buttonStyle(.thawGrouped).disabled(true))
        #expect(size.width > 0)
    }
}
