//
//  RequiredPermissionsNoticeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The setup screen named Accessibility as missing even when another required permission was the one blocking.
@MainActor
@Suite("Required permissions notice")
struct RequiredPermissionsNoticeTests {
    @Test("The notice names each required permission still missing")
    func namesWhatIsMissing() {
        let one = RequiredPermissionsNotice.text(missing: ["Menu Bar Layout Access"])
        #expect(one.contains("Menu Bar Layout Access") && !one.contains("Accessibility"))
        let both = RequiredPermissionsNotice.text(missing: ["Accessibility", "Menu Bar Layout Access"])
        #expect(both.contains("Accessibility") && both.contains("Menu Bar Layout Access"))
        #expect(RequiredPermissionsNotice.text(missing: ["Accessibility"]) != RequiredPermissionsNotice.text(missing: ["Screen Recording"]))
        #expect(RequiredPermissionsNotice.text(missing: []).isEmpty)
    }

    @Test("The live permissions produce a notice only while a required one is missing")
    func readsTheLivePermissions() {
        let permissions = AppPermissions()
        let missing = permissions.requiredPermissions.filter { !$0.hasPermission }
        #expect(RequiredPermissionsNotice.text(for: permissions).isEmpty == missing.isEmpty)
    }
}
