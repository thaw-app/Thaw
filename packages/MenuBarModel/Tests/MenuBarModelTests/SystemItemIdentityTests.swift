//
//  SystemItemIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Legacy SystemUIServer identity")
struct LegacySystemUIServerIdentityTests {
    private func identity(
        namespace: MenuBarItemTag.Namespace = .systemUIServer,
        identifier: String? = nil,
        accessibilityDescription: String? = nil,
        axTitle: String? = nil
    ) -> String? {
        MenuBarItemTag.legacySystemUIServerIdentity(
            namespace: namespace,
            identifier: identifier,
            accessibilityDescription: accessibilityDescription,
            axTitle: axTitle
        )
    }

    @Test("An unnamed SystemUIServer extra resolves to Time Machine")
    func unnamedSystemUIServerIsTimeMachine() {
        #expect(identity() == MenuBarItemTag.timeMachine.title)
        #expect(identity() == "com.apple.menuextra.TimeMachine")
    }

    @Test("Any published identity attribute leaves the item alone")
    func namedAttributesAreNotOverridden() {
        #expect(identity(identifier: "com.apple.menuextra.vpn") == nil)
        #expect(identity(accessibilityDescription: "Siri") == nil)
        #expect(identity(axTitle: "Siri") == nil)
    }

    @Test("Empty strings count as absent attributes")
    func emptyStringsAreAbsent() {
        #expect(identity(identifier: "", accessibilityDescription: "", axTitle: "") == MenuBarItemTag.timeMachine.title)
    }

    @Test("Other hosts are never mapped to Time Machine")
    func otherNamespacesUntouched() {
        #expect(identity(namespace: .menuBarAgent) == nil)
        #expect(identity(namespace: .string("com.example.app")) == nil)
        #expect(identity(namespace: .controlCenter) == nil)
    }
}

@Suite("SystemUIServer display names")
struct SystemUIServerDisplayNameTests {
    @Test("Time Machine keeps its name when its live title is a bare Item-0")
    func timeMachineFromTheTag() {
        #expect(MenuBarItem.systemUIServerDisplayName(title: "Item-0", tagTitle: MenuBarItemTag.timeMachine.title) == "Time Machine")
        #expect(MenuBarItem.systemUIServerDisplayName(title: "com.apple.menuextra.TimeMachine", tagTitle: "Item-0") == "Time Machine")
    }

    @Test("A Time Machine item with no source process is still named from its tag")
    func timeMachineWithoutSourcePID() {
        let item = MenuBarItem(
            tag: .timeMachine,
            windowID: 1,
            ownerPID: 0,
            sourcePID: nil,
            bounds: .zero,
            title: "Item-0",
            isOnScreen: false
        )
        #expect(item.autoDetectedName == "Time Machine")
    }

    @Test("Other SystemUIServer items keep their own title")
    func otherItems() {
        #expect(MenuBarItem.systemUIServerDisplayName(title: "Siri", tagTitle: "Siri") == "Siri")
    }
}

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
