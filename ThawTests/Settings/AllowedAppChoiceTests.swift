//
//  AllowedAppChoiceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Adding an allowed app comes from picking the app, not typing its bundle ID.
@Suite("Allowed app choice")
struct AllowedAppChoiceTests {
    @Test("A picked app with a bundle ID is added")
    func newAppIsAdded() {
        #expect(AutomationSettings.choice(forBundleID: "com.example.App", allowed: []) == .add("com.example.App"))
    }

    @Test("An app that is already allowed is not added twice")
    func allowedAppIsReported() {
        let choice = AutomationSettings.choice(forBundleID: "com.example.App", allowed: ["com.example.App"])
        #expect(choice == .alreadyAllowed("com.example.App"))
    }

    @Test("An app without a bundle ID can't be allowed")
    func missingBundleIDIsRefused() {
        #expect(AutomationSettings.choice(forBundleID: nil, allowed: []) == .noBundleID)
        #expect(AutomationSettings.choice(forBundleID: "  ", allowed: []) == .noBundleID)
    }

    @Test("Surrounding whitespace is trimmed before comparing")
    func bundleIDIsTrimmed() {
        #expect(AutomationSettings.choice(forBundleID: " com.example.App\n", allowed: []) == .add("com.example.App"))
        let choice = AutomationSettings.choice(forBundleID: "com.example.App ", allowed: ["com.example.App"])
        #expect(choice == .alreadyAllowed("com.example.App"))
    }
}
