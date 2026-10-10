//
//  ChronoControlIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("ChronoControlIdentity")
struct ChronoControlIdentityTests {
    /// The live Dark Mode identifier published by MenuBarAgent.
    private static let darkModeAXIdentifier =
        ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode:51AF06CF-28BB-497D-94A1-33DD3AFA9A3A"

    @Test
    func parsesTheLiveMenuBarForm() throws {
        let identity = try #require(ChronoControlIdentity(axIdentifier: Self.darkModeAXIdentifier))

        #expect(identity.containerBundleID == "com.apple.controlcenter")
        #expect(identity.extensionBundleID == "com.apple.controls.display")
        #expect(identity.controlIdentifier == "com.apple.controls.display.dark-mode")
        #expect(identity.instanceID == "51AF06CF-28BB-497D-94A1-33DD3AFA9A3A")
    }

    @Test
    func stableIdentityDropsTheDisplayableInstanceUUID() {
        #expect(
            ChronoControlIdentity.stableIdentity(forAXIdentifier: Self.darkModeAXIdentifier) ==
                ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode"
        )
    }

    @Test
    func stableIdentityIsUnchangedWhenControlCenterMintsANewInstance() {
        let reAdded =
            ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode:93F5A0FD-661F-4CCB-919F-8AAB320E6380"

        #expect(
            ChronoControlIdentity.stableIdentity(forAXIdentifier: Self.darkModeAXIdentifier) ==
                ChronoControlIdentity.stableIdentity(forAXIdentifier: reAdded)
        )
    }

    @Test
    func parsesTheInstanceLessForm() throws {
        let identity = try #require(
            ChronoControlIdentity(
                axIdentifier: ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode"
            )
        )

        #expect(identity.instanceID == nil)
        #expect(identity.stableIdentity == ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode")
    }

    @Test
    func derivesADisplayNameFromTheControlIdentifier() throws {
        let identity = try #require(ChronoControlIdentity(axIdentifier: Self.darkModeAXIdentifier))

        #expect(identity.derivedDisplayName == "Dark Mode")
    }

    @Test(arguments: [
        // Classic menu extras are not control identities.
        "com.apple.menuextra.clock",
        "BentoBox-0",
        "",
        // Colon-prefixed but too few components.
        ":com.apple.controlcenter:com.apple.controls.display",
        // Empty components.
        ":com.apple.controlcenter::com.apple.controls.display.dark-mode",
        // A non-UUID suffix is a different identifier shape and must not be stripped.
        ":a:b:c:d",
    ])
    func rejectsIdentifiersThatAreNotControlIdentities(identifier: String) {
        #expect(ChronoControlIdentity(axIdentifier: identifier) == nil)
    }
}
