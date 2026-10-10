//
//  LegacyConstantsCompatibilityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("Legacy constants compatibility")
struct LegacyConstantsCompatibilityTests {
    @Test
    @available(*, deprecated)
    func ownershipSymbolsForwardToMenuBarIdentity() {
        #expect(Constants.thawOwnedBundleIdentifiers == ThawMenuBarIdentity.ownedBundleIdentifiers)
        #expect(Constants.isThawOwnedBundleIdentifier(ThawMenuBarIdentity.bundleIdentifier))
    }
}
