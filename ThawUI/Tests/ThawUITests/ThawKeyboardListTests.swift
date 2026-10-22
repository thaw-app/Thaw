//
//  ThawKeyboardListTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Keyboard list")
struct ThawKeyboardListTests {
    @Test("The ring shows only for the chosen row while the window is key")
    func ringVisibility() {
        #expect(ThawFocusRingRule.isVisible(isShown: true, activeState: .key))
        #expect(!ThawFocusRingRule.isVisible(isShown: true, activeState: .active))
        #expect(!ThawFocusRingRule.isVisible(isShown: true, activeState: .inactive))
        #expect(!ThawFocusRingRule.isVisible(isShown: false, activeState: .key))
    }

    @Test("A keyboard list with a ringed row lays out at its rows' size")
    func rendersRows() {
        let host = NSHostingView(rootView: KeyboardListSample())
        host.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        #expect(host.fittingSize.height >= 40)
    }
}

/// Two rows behind one keyboard stop, the first showing the ring.
private struct KeyboardListSample: View {
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 2, id: \.self) { row in
                Text("Row \(row)")
                    .frame(width: 120, height: 20)
                    .thawFocusRing(row == 0, in: RoundedRectangle(cornerRadius: ThawRadius.row))
            }
        }
        .thawKeyboardList(isFocused: $isFocused) { _ in }
    }
}
