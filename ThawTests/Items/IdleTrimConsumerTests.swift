//
//  IdleTrimConsumerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Idle trim gates capture and purge strictly on active image consumers")
struct IdleTrimConsumerTests {
    private static func nav(
        thawBar: Bool = false,
        search: Bool = false,
        layoutEditor: Bool = false,
        frontmost: Bool,
        settings: Bool,
        pane: SettingsNavigationIdentifier?,
        hotkeysExpanded: Bool = false,
        simpleMode: Bool = false
    ) -> MenuBarItemImageCache.NavigationStateSnapshot {
        MenuBarItemImageCache.NavigationStateSnapshot(
            isThawBarPresented: thawBar,
            isSearchPresented: search,
            isAppFrontmost: frontmost,
            isSettingsPresented: settings,
            settingsNavigationIdentifier: pane,
            isItemHotkeyListExpanded: hotkeysExpanded,
            isSimpleModeSettings: simpleMode,
            isLayoutEditorPresented: layoutEditor
        )
    }

    @Test("The Layout pane on screen behind another app keeps its glyphs while live polling rests")
    func unfocusedLayoutPaneIsAConsumer() {
        let cache = MenuBarItemImageCache()
        let nav = Self.nav(frontmost: false, settings: true, pane: .menuBarLayout)
        #expect(!cache.hasVisibleCaptureConsumer(nav: nav))
        #expect(cache.hasActiveImageConsumer(nav: nav))
        #expect(cache.hasUnfocusedCaptureConsumer(nav: nav))
    }

    @Test("ThawBar, Search, Layout Editor, and glyph settings panes count as active image consumers")
    func visibleImageSurfacesCountAsConsumers() {
        let cache = MenuBarItemImageCache()
        #expect(cache.hasActiveImageConsumer(nav: Self.nav(thawBar: true, frontmost: false, settings: false, pane: nil)))
        #expect(cache.hasActiveImageConsumer(nav: Self.nav(search: true, frontmost: false, settings: false, pane: nil)))
        #expect(cache.hasActiveImageConsumer(nav: Self.nav(layoutEditor: true, frontmost: false, settings: false, pane: nil)))
        #expect(cache.hasActiveImageConsumer(nav: Self.nav(frontmost: true, settings: true, pane: .thawBar)))
        #expect(cache.hasActiveImageConsumer(nav: Self.nav(frontmost: true, settings: true, pane: .general, simpleMode: true)))
        #expect(cache.hasActiveImageConsumer(nav: Self.nav(frontmost: true, settings: true, pane: .hotkeys, hotkeysExpanded: true)))
    }

    @Test("Closed settings or panes without glyphs allow idle trim to purge everything")
    func otherStatesAllowTheTrim() {
        let cache = MenuBarItemImageCache()
        #expect(!cache.hasActiveImageConsumer(nav: Self.nav(frontmost: false, settings: false, pane: .menuBarLayout)))
        #expect(!cache.hasActiveImageConsumer(nav: Self.nav(frontmost: false, settings: true, pane: nil)))
        #expect(!cache.hasActiveImageConsumer(nav: Self.nav(frontmost: true, settings: true, pane: .general)))
        #expect(!cache.hasActiveImageConsumer(nav: Self.nav(frontmost: true, settings: true, pane: .menuBarAppearance)))
        #expect(!cache.hasActiveImageConsumer(nav: Self.nav(frontmost: true, settings: true, pane: .hotkeys, hotkeysExpanded: false)))
    }
}
