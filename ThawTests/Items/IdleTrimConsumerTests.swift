//
//  IdleTrimConsumerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Idle trim spares glyphs an unfocused settings pane still draws")
struct IdleTrimConsumerTests {
    private static func nav(
        frontmost: Bool,
        settings: Bool,
        pane: SettingsNavigationIdentifier?
    ) -> MenuBarItemImageCache.NavigationStateSnapshot {
        MenuBarItemImageCache.NavigationStateSnapshot(
            isThawBarPresented: false,
            isSearchPresented: false,
            isAppFrontmost: frontmost,
            isSettingsPresented: settings,
            settingsNavigationIdentifier: pane,
            isItemHotkeyListExpanded: false,
            isSimpleModeSettings: false
        )
    }

    @Test("The Layout pane on screen behind another app keeps its glyphs")
    func unfocusedLayoutPaneIsAConsumer() {
        let cache = MenuBarItemImageCache()
        let nav = Self.nav(frontmost: false, settings: true, pane: .menuBarLayout)
        // The live refresh rests, but the trim must wait.
        #expect(!cache.hasVisibleCaptureConsumer(nav: nav))
        #expect(cache.hasUnfocusedCaptureConsumer(nav: nav))
    }

    @Test("Closed settings or a pane without glyphs still allows the trim")
    func otherStatesAllowTheTrim() {
        let cache = MenuBarItemImageCache()
        #expect(!cache.hasUnfocusedCaptureConsumer(nav: Self.nav(frontmost: false, settings: false, pane: .menuBarLayout)))
        #expect(!cache.hasUnfocusedCaptureConsumer(nav: Self.nav(frontmost: false, settings: true, pane: nil)))
    }
}
