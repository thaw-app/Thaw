//
//  MenuBarManagerUnsetupTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Testing
@testable import Thaw

/// The manager's own bookkeeping, on an AppState that was never set up so no engine or status item exists.
@MainActor
@Suite("Menu bar manager before setup", .serialized, .scratchDefaults)
struct MenuBarManagerUnsetupTests {
    @Test("Automatic Zen Mode stays on until the last source clears")
    func automaticZenWaitsForEverySource() {
        let appState = AppState()
        let manager = appState.menuBarManager
        manager.setAutomaticZenMode(true, reason: .screenSharing)
        manager.setAutomaticZenMode(true, reason: .recording)
        #expect(manager.isZenModeActive)
        #expect(!manager.showOnHoverAllowed)
        manager.setAutomaticZenMode(false, reason: .screenSharing)
        #expect(manager.isZenModeActive)
        manager.setAutomaticZenMode(false, reason: .recording)
        #expect(!manager.isZenModeActive)
        #expect(manager.showOnHoverAllowed)
    }

    @Test("An automatic source clearing never ends Zen Mode the user turned on")
    func manualZenOutlivesAutomaticSources() {
        let appState = AppState()
        let manager = appState.menuBarManager
        manager.toggleZenMode()
        manager.setAutomaticZenMode(true, reason: .recording)
        manager.setAutomaticZenMode(false, reason: .recording)
        #expect(manager.isZenModeActive)
        manager.toggleZenMode()
        #expect(!manager.isZenModeActive)
    }

    @Test("Turning Zen Mode off by hand drops every automatic reason")
    func manualToggleClearsAutomaticReasons() {
        let appState = AppState()
        let manager = appState.menuBarManager
        manager.setAutomaticZenMode(true, reason: .screenSharing)
        manager.toggleZenMode()
        #expect(!manager.isZenModeActive)
        // A later automatic request starts afresh and can withdraw itself.
        manager.setAutomaticZenMode(true, reason: .recording)
        manager.setAutomaticZenMode(false, reason: .recording)
        #expect(!manager.isZenModeActive)
    }

    @Test("Clearing the swap state forgets the swap and saves that")
    func clearSwapState() {
        Defaults.set(true, forKey: .swapActive)
        let appState = AppState()
        let manager = appState.menuBarManager
        #expect(manager.isSwapped)
        manager.clearSwapState()
        #expect(!manager.isSwapped)
        #expect(!manager.isSwapInFlight)
        #expect(!Defaults.bool(forKey: .swapActive))
    }

    @Test("Without an engine nothing is assigned, hidden natively or published")
    func noEngine() {
        let appState = AppState()
        let manager = appState.menuBarManager
        manager.assignSection(.hidden, identifier: "com.example.item")
        #expect(manager.setSection(.hidden, items: []) == nil)
        #expect(manager.nativeHiddenBundleIDs.isEmpty)
        #expect(manager.nativeUntrackedBundleIDs.isEmpty)
        var received = 0
        let first = manager.revealedSectionChanges.sink { _ in received += 1 }
        let second = manager.sectionLayoutChanges.sink { _ in received += 1 }
        #expect(received == 0)
        first.cancel()
        second.cancel()
    }

    @Test("Every section is present and the visible one has a control item")
    func sections() {
        let appState = AppState()
        let manager = appState.menuBarManager
        for name in MenuBarSection.Name.allCases {
            #expect(manager.section(withName: name)?.name == name)
            #expect(manager.controlItem(withName: name) === manager.section(withName: name)?.controlItem)
        }
    }

    @Test("Small housekeeping calls are safe before setup")
    func housekeeping() {
        let appState = AppState()
        let manager = appState.menuBarManager
        manager.updateLastShowTimestamp()
        manager.noteUserRevealOwnership()
        manager.dismissLayoutEditorPanel()
        manager.dismissAppearanceEditorPanel()
        manager.synchronizeAlwaysShowHiddenItems()
        manager.rebuildItemHotkeys()
        manager.openItem(withIdentifier: "com.example.missing")
        #expect(manager.lastUserRevealDate != nil)
        #expect(!manager.shouldAlwaysShowHiddenItems)
        #expect(!manager.shouldDeferBarMutation)
        #expect(manager.hotkeyItemMap.isEmpty)
    }

    @Test("Showing and hiding the application menus without setup changes nothing")
    func applicationMenusWithoutSetup() {
        let appState = AppState()
        let manager = appState.menuBarManager
        manager.hideApplicationMenus(manual: true)
        #expect(!manager.isHidingApplicationMenus)
        manager.showApplicationMenus()
        #expect(!manager.isHidingApplicationMenus)
    }
}

/// The average color sample and the contrast decisions made from it.
@MainActor
@Suite("Menu bar average color")
struct MenuBarAverageColorInfoTests {
    private func info(white: CGFloat) -> MenuBarAverageColorInfo {
        MenuBarAverageColorInfo(color: CGColor(srgbRed: white, green: white, blue: white, alpha: 1), source: .menuBarWindow)
    }

    @Test("White reads bright and black reads dark")
    func brightness() {
        #expect(info(white: 1).isBright(for: nil))
        #expect(!info(white: 0).isBright(for: nil))
        #expect(info(white: 1).relativeLuminance > info(white: 0.5).relativeLuminance)
    }

    @Test("A black tint darkens the sample and keeps its source")
    func tint() {
        let sample = MenuBarAverageColorInfo(color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), source: .desktopWallpaper)
        let tinted = sample.tinted(by: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), opacity: 0.8)
        #expect(tinted.relativeLuminance < sample.relativeLuminance)
        #expect(tinted.source == .desktopWallpaper)
        let untouched = sample.tinted(by: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), opacity: 0)
        #expect(abs(untouched.relativeLuminance - sample.relativeLuminance) < 0.001)
    }
}
