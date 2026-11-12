//
//  SearchEmptyStatesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// A search that matched nothing left no way back but deleting the query by hand.
@MainActor
@Suite("Search empty states")
struct SearchEmptyStatesTests {
    @Test("No matches draws taller with its Clear Search button than without one")
    func noMatchesOffersClearSearch() {
        let withAction = NSHostingView(rootView: ThawEmptyState.noSearchMatches {}.frame(width: 320))
        let withoutAction = NSHostingView(rootView: ThawEmptyState(
            systemImage: "magnifyingglass",
            title: "No items match",
            caption: "Try part of the item's name or the app that owns it."
        ).frame(width: 320))
        withAction.layoutSubtreeIfNeeded()
        withoutAction.layoutSubtreeIfNeeded()
        #expect(withAction.fittingSize.height > withoutAction.fittingSize.height)
    }
}
