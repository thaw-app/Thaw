//
//  MenuBarItemAutoDetectedNameTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
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
    func moduleNameMatchingResolvesAliases() {
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "Wi-Fi") == "WiFi")
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "com.apple.menuextra.wifi") == "WiFi")
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "WiFi") == "WiFi")
        #expect(SystemMenuBarModuleCatalog.moduleName(matching: "UnknownExtra") == nil)
    }
}
