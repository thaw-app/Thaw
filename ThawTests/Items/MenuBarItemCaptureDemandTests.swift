//
//  MenuBarItemCaptureDemandTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Shared item capture demand")
struct MenuBarItemCaptureDemandTests {
    @Test("Simple Mode and Layout request the same capture work", arguments: SettingsNavigationIdentifier.allCases)
    func simpleModeMatchesLayout(lastPane: SettingsNavigationIdentifier) {
        let simple = navigation(simpleMode: true, pane: lastPane)
        let layout = navigation(pane: .menuBarLayout)
        let cache = MenuBarItemImageCache(screenIsLocked: { false })

        #expect(cache.hasVisibleCaptureConsumer(nav: simple))
        #expect(simple.liveCaptureScope == layout.liveCaptureScope)
        #expect(simple.liveCaptureScope.sections(thawBarSection: nil) == MenuBarSection.Name.allCases)
    }

    @Test("Inactive settings do not keep capturing", arguments: [false, true])
    func inactiveSettings(simpleMode: Bool) {
        #expect(navigation(simpleMode: simpleMode, frontmost: false).liveCaptureScope == .none)
        #expect(navigation(simpleMode: simpleMode, settings: false).liveCaptureScope == .none)
    }

    @Test("Other capture surfaces retain their section selection")
    func otherSurfaces() {
        #expect(navigation(pane: .thawBar).liveCaptureScope == .allSections)
        #expect(navigation(pane: .hotkeys).liveCaptureScope == .none)
        #expect(navigation(pane: .hotkeys, hotkeysExpanded: true).liveCaptureScope == .allSections)
        #expect(navigation(pane: .menuBarAppearance).liveCaptureScope == .none)

        let search = navigation(simpleMode: true, search: true)
        #expect(search.liveCaptureScope.sections(thawBarSection: .hidden) == [.visible])
        let bar = navigation(frontmost: false, thawBar: true)
        #expect(bar.liveCaptureScope.sections(thawBarSection: .hidden) == [.hidden])
        #expect(bar.liveCaptureScope.sections(thawBarSection: nil).isEmpty)
    }

    @Test("Every live-loop start uses the same demand as its capture ticks", arguments: SettingsNavigationIdentifier.allCases, [false, true])
    func startAndTickAgree(pane: SettingsNavigationIdentifier, simpleMode: Bool) {
        let nav = navigation(simpleMode: simpleMode, pane: pane)
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        #expect(cache.hasVisibleCaptureConsumer(nav: nav) == !nav.liveCaptureScope.sections(thawBarSection: nil).isEmpty)
    }

    private func navigation(
        simpleMode: Bool = false,
        pane: SettingsNavigationIdentifier = .menuBarLayout,
        frontmost: Bool = true,
        settings: Bool = true,
        search: Bool = false,
        thawBar: Bool = false,
        hotkeysExpanded: Bool = false
    ) -> MenuBarItemImageCache.NavigationStateSnapshot {
        MenuBarItemImageCache.NavigationStateSnapshot(
            isThawBarPresented: thawBar,
            isSearchPresented: search,
            isAppFrontmost: frontmost,
            isSettingsPresented: settings,
            settingsNavigationIdentifier: pane,
            isItemHotkeyListExpanded: hotkeysExpanded,
            isSimpleModeSettings: simpleMode
        )
    }
}
