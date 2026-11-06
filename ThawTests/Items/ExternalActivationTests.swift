//
//  ExternalActivationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Activation by identifier, as Shortcuts and thaw://activate-item reach it:
/// which items may be pressed, and what is decided before any press.
@MainActor
@Suite("External item activation")
struct ExternalActivationTests {
    private typealias Outcome = MenuBarItemActivationOutcome

    private func item(_ tag: MenuBarItemTag) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: 1,
            ownerPID: pid_t.max,
            sourcePID: nil,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }

    private func appItem(_ title: String = "Item") -> MenuBarItem {
        item(MenuBarItemTag(namespace: .string("com.example.thawtests.activation"), title: title, instanceIndex: 0))
    }

    private func makeManager(holding items: [MenuBarItem], in section: MenuBarSection.Name = .hidden) -> MenuBarItemManager {
        let manager = MenuBarItemManager()
        manager.itemCache[section] = items
        return manager
    }

    @Test("Permission is checked before liveness, and a go-ahead needs both")
    func preflightOrder() {
        #expect(MenuBarItemManager.activationPreflight(hasAccessibilityPermission: false, itemIsLive: false) == .permissionMissing)
        #expect(MenuBarItemManager.activationPreflight(hasAccessibilityPermission: false, itemIsLive: true) == .permissionMissing)
        #expect(MenuBarItemManager.activationPreflight(hasAccessibilityPermission: true, itemIsLive: false) == .itemUnavailable)
        #expect(MenuBarItemManager.activationPreflight(hasAccessibilityPermission: true, itemIsLive: true) == nil)
    }

    @Test("An item is found by identifier in any section")
    func findsItemsInEverySection() {
        let target = appItem()
        for section in MenuBarSection.Name.allCases {
            let manager = makeManager(holding: [appItem("Other"), target], in: section)
            #expect(manager.externallyActionableItem(withIdentifier: target.uniqueIdentifier) == target)
        }
    }

    @Test("Thaw's own dividers and unknown identifiers are not offered for activation")
    func controlItemsAndStrangersAreNotActionable() {
        let divider = item(.visibleControlItem)
        let manager = makeManager(holding: [divider, appItem()], in: .visible)

        #expect(manager.externallyActionableItem(withIdentifier: divider.uniqueIdentifier) == nil)
        #expect(manager.externallyActionableItem(withIdentifier: "com.example.gone:Item") == nil)
    }

    @Test("A live item is pressed once and the press decides the outcome", arguments: [
        Outcome.completed(reactionObserved: true),
        .completed(reactionObserved: false),
        .activationFailed,
    ])
    func liveItemIsPressed(result: MenuBarItemActivationOutcome) async {
        let target = appItem()
        let manager = makeManager(holding: [appItem("Other"), target])
        var pressed: [MenuBarItem] = []

        let outcome = await manager.activateItem(
            withIdentifier: target.uniqueIdentifier,
            hasAccessibilityPermission: true
        ) { item in
            pressed.append(item)
            return result
        }

        #expect(outcome == result)
        #expect(pressed == [target])
    }

    @Test("Without Accessibility nothing is pressed, even for an item that is there")
    func missingPermissionPressesNothing() async {
        let target = appItem()
        let manager = makeManager(holding: [target])
        var presses = 0

        let outcome = await manager.activateItem(
            withIdentifier: target.uniqueIdentifier,
            hasAccessibilityPermission: false
        ) { _ in
            presses += 1
            return .completed(reactionObserved: true)
        }

        #expect(outcome == .permissionMissing)
        #expect(presses == 0)
    }

    @Test("An identifier with no live, actionable item is unavailable and presses nothing", arguments: [false, true])
    func unavailableItemPressesNothing(namesADivider: Bool) async {
        let divider = item(.visibleControlItem)
        let manager = makeManager(holding: [divider], in: .visible)
        var presses = 0

        let outcome = await manager.activateItem(
            withIdentifier: namesADivider ? divider.uniqueIdentifier : "com.example.gone:Item",
            hasAccessibilityPermission: true
        ) { _ in
            presses += 1
            return .completed(reactionObserved: true)
        }

        #expect(outcome == .itemUnavailable)
        #expect(presses == 0)
    }

    @Test("A manager that was never set up reports failure rather than pressing")
    func unsetManagerFailsActivation() async {
        let target = appItem()
        let manager = makeManager(holding: [target])

        #expect(await manager.activateItem(withIdentifier: target.uniqueIdentifier) == .activationFailed)
    }
}
