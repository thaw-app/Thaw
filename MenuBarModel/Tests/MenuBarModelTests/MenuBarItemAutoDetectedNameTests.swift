//
//  MenuBarItemAutoDetectedNameTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("MenuBarItem autoDetectedName")
struct MenuBarItemAutoDetectedNameTests {
    @Test
    func menuBarAgentPrefersAXTitleOverHostingProcess() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.wifi"),
            windowID: 1,
            ownerPID: 1,
            sourcePID: nil,
            bounds: .zero,
            title: "Wi-Fi",
            isOnScreen: true
        )

        #expect(item.autoDetectedName == "Wi-Fi")
    }

    @Test
    func menuBarAgentMapsMenuExtraIdentityViaCatalog() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.bluetooth"),
            windowID: 2,
            ownerPID: 1,
            sourcePID: nil,
            bounds: .zero,
            title: "com.apple.menuextra.bluetooth",
            isOnScreen: true
        )

        #expect(item.autoDetectedName == "Bluetooth")
    }

    @Test
    func menuBarAgentMapsBentoBoxViaCatalog() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "BentoBox-0"),
            windowID: 3,
            ownerPID: 1,
            sourcePID: nil,
            bounds: .zero,
            title: "BentoBox-0",
            isOnScreen: true
        )

        #expect(item.autoDetectedName == "Control Center")
    }

    @Test
    func menuBarAgentFallsBackToTagTitleWhenDisplayTitleMissing() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"),
            windowID: 4,
            ownerPID: 1,
            sourcePID: nil,
            bounds: .zero,
            title: nil,
            isOnScreen: true
        )

        #expect(item.autoDetectedName == "Clock")
    }

    @Test
    func menuBarAgentPrefersControlDescriptionOverChronoIdentity() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .menuBarAgent,
                title: ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode"
            ),
            windowID: 5,
            ownerPID: 1,
            sourcePID: nil,
            bounds: .zero,
            title: "Dark Mode",
            isOnScreen: true
        )

        #expect(item.autoDetectedName == "Dark Mode")
    }

    @Test
    func menuBarAgentDerivesAChronoControlNameWhenDescriptionMissing() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .menuBarAgent,
                title: ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode"
            ),
            windowID: 6,
            ownerPID: 1,
            sourcePID: nil,
            bounds: .zero,
            title: nil,
            isOnScreen: true
        )

        #expect(item.autoDetectedName == "Dark Mode")
    }

    // Restored conceal snapshots have no PID or resolvable source application.
    // Uninstalled bundle identifiers keep these assertions independent of the host's apps.

    @Test
    func anItemWithNoSourceProcessIsNamedFromItsNamespace() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.thawtests.orca"), title: "Item-0"),
            windowID: 7,
            ownerPID: 0,
            sourcePID: nil,
            bounds: .zero,
            title: nil,
            isOnScreen: true
        )

        #expect(item.autoDetectedName == "Orca")
    }

    @Test
    func aNamespaceDerivedNameIsTitleCased() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.thawtests.musicPresence"), title: "Item-0"),
            windowID: 8,
            ownerPID: 0,
            sourcePID: nil,
            bounds: .zero,
            title: nil,
            isOnScreen: true
        )

        #expect(item.autoDetectedName == "Music Presence")
    }

    @Test
    func anItemWithNoSourceProcessAndNoNamespaceStillFallsBack() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .null, title: "Item-0"),
            windowID: 9,
            ownerPID: 0,
            sourcePID: nil,
            bounds: .zero,
            title: nil,
            isOnScreen: true
        )

        #expect(item.autoDetectedName == "Menu Bar Item")
    }

    @Test
    func moduleNameMatchingResolvesAliases() {
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "Wi-Fi") == "WiFi")
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "com.apple.menuextra.wifi") == "WiFi")
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "WiFi") == "WiFi")
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "UnknownExtra") == nil)
    }

    /// Timer is a live MenuBarAgent row (module:Timer); its identifier and position key must resolve.
    @Test
    func timerModuleResolvesAliasesAndPositionKey() {
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "Timer") == "Timer")
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "com.apple.menuextra.timer") == "Timer")
        #expect(
            SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: "com.apple.menuextra.timer")
                == "module:Timer"
        )
    }

    /// Without a Control Center per-host key, Timer stays forced-visible like Sound until hiding is verified.
    @Test
    func timerModuleHasNoControlCenterGovernance() {
        #expect(SystemMenuBarModuleCatalog.controlCenterKeysByMenuExtraTitle["com.apple.menuextra.timer"] == nil)
    }
}
