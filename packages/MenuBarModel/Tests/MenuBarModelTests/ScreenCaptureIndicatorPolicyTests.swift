//
//  ScreenCaptureIndicatorPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import MenuBarModel

/// 2026-10-22 reports: ⌘-dragging the screen sharing indicator broke the
/// whole bar. macOS places it wherever the user drops it, so it is left out
/// of ordering like the camera indicator rather than treated as a trailing
/// anchor that order repair pulls back next to the Clock.
@Suite("The screen sharing indicator stays out of ordering")
struct ScreenCaptureIndicatorPolicyTests {
    @Test func isACaptureActivityIndicator() {
        #expect(MenuBarItemTag.screenCaptureUI.isCaptureActivityIndicator)
        #expect(MenuBarItemTag.screenCaptureUI.sectionManagementPolicy == .excluded)
    }

    @Test func isNotATrailingAnchor() {
        #expect(!MenuBarItemTag.screenCaptureUI.isLayoutAnchoredSystemItem)
    }

    @Test func staysFixedAndShown() {
        #expect(!MenuBarItemTag.screenCaptureUI.isMovable)
        #expect(!MenuBarItemTag.screenCaptureUI.canBeHidden)
    }
}
