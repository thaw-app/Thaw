//
//  SettingsURIApprovalTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Who may change settings through thaw:// without being asked, outside the full app too.
@MainActor
@Suite("Settings URI approval")
struct SettingsURIApprovalTests {
    private let stranger = SettingsURISender(
        bundleIdentifier: "com.example.never-approved.\(UUID().uuidString)", teamIdentifier: nil, codeHash: "aa"
    )

    @Test("An unidentified sender is never approved")
    func noSender() {
        #expect(!SettingsURIHandler.isApproved(nil, isEnabled: { true }, builtInTrust: { _ in true }))
    }

    @Test("A built-in trusted sender is approved even with the Settings URI off")
    func builtInTrust() {
        #expect(SettingsURIHandler.isApproved(stranger, isEnabled: { false }, builtInTrust: { _ in true }))
    }

    @Test("Anyone else needs the Settings URI on and a stored approval", arguments: [false, true])
    func strangerIsRefused(enabled: Bool) {
        #expect(!SettingsURIHandler.isApproved(stranger, isEnabled: { enabled }, builtInTrust: { _ in false }))
    }

    @Test("An app you approved passes while the Settings URI is on, and not while it is off", .scratchDefaults)
    func approvedSenderFollowsTheSwitch() {
        SettingsURIHandler.addToWhitelist(bundleId: stranger.bundleIdentifier, codeHash: stranger.codeHash)
        #expect(SettingsURIHandler.isApproved(stranger, isEnabled: { true }, builtInTrust: { _ in false }))
        #expect(!SettingsURIHandler.isApproved(stranger, isEnabled: { false }, builtInTrust: { _ in false }))
    }
}
