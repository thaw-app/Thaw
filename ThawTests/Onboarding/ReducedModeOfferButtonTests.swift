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

/// Reduced mode is off the visible UI until it moves to its own app, though the code stays.
@MainActor
@Suite("Reduced mode offer", .serialized, .scratchDefaults)
struct ReducedModeOfferButtonTests {
    private func height(_ permissions: AppPermissions) -> CGFloat {
        let view = ThawPermissionsView(mode: .onboarding, onContinue: {})
            .frame(width: ThawOnboardingWindowMetrics.width)
            .environment(permissions)
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("The permissions window offers no Reduced mode while Accessibility is missing")
    func noOffer() {
        let missing = OnboardingPreview.permissions()
        let granted = OnboardingPreview.permissions(granted: [.accessibility])
        defer {
            missing.stopAllChecks()
            granted.stopAllChecks()
        }
        #expect(height(missing) == height(granted), "no extra line above the footer")
    }

    @Test("The consequence still names the app, for when the offer comes back")
    func consequenceNamesTheApp() {
        #expect(String(localized: ReducedModeOfferButton.consequence).contains(Constants.displayName))
    }
}
