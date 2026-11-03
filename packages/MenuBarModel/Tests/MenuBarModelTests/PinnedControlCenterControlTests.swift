//
//  PinnedControlCenterControlTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

/// A Control Center control the user pinned to the menu bar. MenuBarAgent
/// sorts it by a chrono:<instance UUID> row, and the tag drops that UUID on
/// purpose, so no weight Thaw writes ever reaches the control. Thaw must not
/// try to move it, or every reveal shuffles the icons around it.
@Suite("Pinned Control Center controls")
struct PinnedControlCenterControlTests {
    /// The tag title the provider keeps for the reported Screenshot control.
    private static let screenshotIdentity =
        ":com.apple.screenshot.launcher:com.apple.controls.screenshot:com.apple.controls.screenshot.capture-custom"

    private func agentItem(_ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: title),
            windowID: 0x8000_0002,
            ownerPID: 500,
            sourcePID: 500,
            bounds: CGRect(x: 796, y: 0, width: 21, height: 30),
            title: title,
            isOnScreen: true
        )
    }

    @Test("The stable identity and the live form with an instance UUID are both recognized", arguments: [
        screenshotIdentity,
        ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode",
        ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode:51AF06CF-28BB-497D-94A1-33DD3AFA9A3A",
    ])
    func recognizesAPinnedControl(title: String) {
        #expect(MenuBarItemTag(namespace: .menuBarAgent, title: title).isPinnedControlCenterControl)
    }

    @Test("Menu extras, modules and third-party items are not pinned controls", arguments: [
        "com.apple.menuextra.sound",
        "Item-0",
        "live-activity-pill-1",
    ])
    func ordinaryAgentChildrenAreNot(title: String) {
        #expect(!MenuBarItemTag(namespace: .menuBarAgent, title: title).isPinnedControlCenterControl)
    }

    @Test("The same identity under an app's namespace is not a pinned control")
    func onlyUnderMenuBarAgent() {
        let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: Self.screenshotIdentity)
        #expect(!tag.isPinnedControlCenterControl)
    }

    @Test("It cannot be moved, with or without experimental hiding")
    func notMovable() {
        let control = agentItem(Self.screenshotIdentity)
        #expect(!control.isMovable)
        #expect(!control.isMovable(experimentalSystemItemHiding: true))
        #expect(!control.isPhysicallyOrderable(experimentalSystemItemHiding: false))
        #expect(!control.isPhysicallyOrderable(experimentalSystemItemHiding: true))
    }

    @Test("The refusal is final: macOS anchors it, and no setting lifts that")
    func refusalReason() {
        let control = agentItem(Self.screenshotIdentity)
        #expect(control.orderabilityRefusal(experimentalSystemItemHiding: false) == .systemAnchored)
        #expect(control.orderabilityRefusal(experimentalSystemItemHiding: true) == .systemAnchored)
    }

    @Test("It stays a Visible item that is shown, not one that is excluded")
    func staysVisible() {
        let control = agentItem(Self.screenshotIdentity)
        #expect(control.sectionManagementPolicy == .forcedVisible)
    }
}
