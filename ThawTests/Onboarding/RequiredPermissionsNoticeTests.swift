//
//  RequiredPermissionsNoticeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
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

    @Test("The permissions the setup screen reads produce a notice only while a required one is missing")
    func readsThePermissions() {
        let granted = Self.permission("Accessibility", isRequired: true, granted: true)
        let missingRequired = Self.permission("Menu Bar Layout Access", isRequired: true, granted: false)
        let missingOptional = Self.permission("Screen Recording", isRequired: false, granted: false)

        let allGranted = PermissionsStub([granted])
        #expect(RequiredPermissionsNotice.text(for: allGranted).isEmpty)

        let onlyOptionalMissing = PermissionsStub([granted, missingOptional])
        #expect(RequiredPermissionsNotice.text(for: onlyOptionalMissing).isEmpty, "a missing optional permission does not block setup")

        let requiredMissing = PermissionsStub([granted, missingRequired, missingOptional])
        let text = RequiredPermissionsNotice.text(for: requiredMissing)
        #expect(text == RequiredPermissionsNotice.text(missing: ["Menu Bar Layout Access"]))
        #expect(!text.contains("Accessibility") && !text.contains("Screen Recording"))
    }

    /// A permission whose grant is fixed, so the result does not depend on the Mac running the tests.
    private static func permission(_ title: String, isRequired: Bool, granted: Bool) -> Permission {
        Permission(
            title: title,
            iconName: "lock",
            iconColor: .gray,
            details: [],
            isRequired: isRequired,
            settingsURL: nil,
            check: { granted },
            request: { _ in },
            ungrantedPollBudget: 0,
            openURL: { _ in }
        )
    }
}

/// The permissions a setup screen reads, without the system behind them.
@MainActor
@Observable
private final class PermissionsStub: PermissionsManaging {
    let permissionsState = AppPermissions.PermissionsState.missing
    let allPermissions: [Permission]

    init(_ permissions: [Permission]) {
        allPermissions = permissions
    }
}
