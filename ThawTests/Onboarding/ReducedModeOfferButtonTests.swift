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
@Suite("Reduced mode offer", .serialized, .scratchDefaults)
struct ReducedModeOfferButtonTests {
    private func height(_ permissions: AppPermissions) -> CGFloat {
        let view = ThawPermissionsView(mode: .onboarding, chooseReducedMode: {}, onContinue: {})
            .frame(width: ThawOnboardingWindowMetrics.width)
            .environment(permissions)
            .environment(AppState())
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("The consequence is visible text, shown only while Accessibility is missing")
    func consequenceIsVisible() {
        #expect(String(localized: ReducedModeOfferButton.offer).contains(Constants.displayName))
        let missing = OnboardingPreview.permissions()
        let granted = OnboardingPreview.permissions(granted: [.accessibility])
        defer {
            missing.stopAllChecks()
            granted.stopAllChecks()
        }
        #expect(height(missing) > height(granted) + 10, "a line of text above the footer")
    }
}
