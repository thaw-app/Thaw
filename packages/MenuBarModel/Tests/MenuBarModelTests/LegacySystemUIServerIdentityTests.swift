//
//  LegacySystemUIServerIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

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
