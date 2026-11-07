//
//  ReducedModeOfferButtonTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// What declining Accessibility costs was only in a tooltip under a caption-sized button.
@MainActor
@Suite("Reduced mode offer", .scratchDefaults)
struct ReducedModeOfferButtonTests {
    @Test("The consequence is visible text next to the button")
    func consequenceIsVisible() {
        let consequence = String(localized: ReducedModeOfferButton.consequence)
        #expect(consequence.contains(Constants.displayName))
        let host = NSHostingView(rootView: ReducedModeOfferButton().environment(AppState()))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 30, "the button and a line of text")
    }
}
