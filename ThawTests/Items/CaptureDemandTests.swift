//
//  CaptureDemandTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins what asks for a capture: the item cache state that invalidates the
/// last one, the sections a live scope covers, and how one pass folds its
/// sections together.
@MainActor
@Suite("Capture demand rules")
struct CaptureDemandRulesTests {
    private static func item(
        _ title: String,
        bounds: CGRect = CGRect(x: 100, y: 4, width: 24, height: 22),
        windowID: CGWindowID,
        isOnScreen: Bool = true
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 501,
            sourcePID: 501,
            bounds: bounds,
            title: title,
            isOnScreen: isOnScreen
        )
    }

    private static func cache(
        displayID: CGDirectDisplayID? = 7,
        visible: [MenuBarItem] = [],
        hidden: [MenuBarItem] = []
    ) -> MenuBarItemCache {
        var cache = MenuBarItemCache(displayID: displayID)
        cache[.visible] = visible
        cache[.hidden] = hidden
        return cache
    }

    private static func capture(width: Int) throws -> MenuBarItemGlyphCapture {
        try ItemsFixture.glyph(width: width, height: 16, color: nil)
    }

    // MARK: captureInvalidationKey

    @Test("An item that only moved does not ask for a new capture")
    func positionIsLeftOut() {
        let before = Self.item("A", bounds: CGRect(x: 100, y: 4, width: 24, height: 22), windowID: 1)
        let after = Self.item("A", bounds: CGRect(x: 131, y: 5, width: 24, height: 22), windowID: 1)

        #expect(
            MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [before]))
                == MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [after]))
        )
    }

    @Test("A change of size, window, visibility, section or display asks for one")
    func everythingElseCounts() {
        let item = Self.item("A", windowID: 1)
        let key = MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [item]))

        let resized = Self.item("A", bounds: CGRect(x: 100, y: 4, width: 30, height: 22), windowID: 1)
        let taller = Self.item("A", bounds: CGRect(x: 100, y: 4, width: 24, height: 24), windowID: 1)
        let rehosted = Self.item("A", windowID: 2)
        let offScreen = Self.item("A", windowID: 1, isOnScreen: false)

        for changed in [resized, taller, rehosted, offScreen] {
            #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [changed])) != key)
        }
        #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache(hidden: [item])) != key)
        #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache(displayID: 8, visible: [item])) != key)
        #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache(displayID: nil, visible: [item])) != key)
        #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache()) != key)
    }

    @Test("The order items are listed in within a section does not matter")
    func orderWithinASectionIsLeftOut() {
        let first = Self.item("A", windowID: 1)
        let second = Self.item("B", windowID: 2)

        let key = MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [first, second]))

        #expect(key == MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [second, first])))
        #expect(key.displayID == 7)
        #expect(key.entries.map(\.windowID) == [1, 2])
    }

    @Test("Entries sort by section, then identifier, then window")
    func entryOrdering() {
        typealias Entry = MenuBarItemImageCache.CaptureInvalidationKey.Entry
        func entry(_ section: String, _ identifier: String, _ windowID: CGWindowID) -> Entry {
            Entry(section: section, identifier: identifier, windowID: windowID, width: 24, height: 22, isOnScreen: true)
        }

        #expect(entry("a", "z", 9) < entry("b", "a", 1))
        #expect(entry("a", "a", 9) < entry("a", "b", 1))
        #expect(entry("a", "a", 1) < entry("a", "a", 2))
        #expect(!(entry("a", "a", 1) < entry("a", "a", 1)))
    }

    // MARK: LiveCaptureScope

    @Test("Each scope names the sections it captures")
    func scopeSections() {
        typealias Scope = MenuBarItemImageCache.LiveCaptureScope

        #expect(Scope.none.sections(thawBarSection: .hidden).isEmpty)
        #expect(Scope.visible.sections(thawBarSection: .hidden) == [.visible])
        #expect(Scope.allSections.sections(thawBarSection: nil) == MenuBarSection.Name.allCases)
        #expect(Scope.thawBar.sections(thawBarSection: .alwaysHidden) == [.alwaysHidden])
    }

    @Test("The Thaw Bar scope captures nothing while the bar shows no section")
    func thawBarWithoutASection() {
        #expect(MenuBarItemImageCache.LiveCaptureScope.thawBar.sections(thawBarSection: nil).isEmpty)
    }

    // MARK: CapturePass

    @Test("Absorbing a section adds everything it learned")
    func absorbAddsEverything() throws {
        let first = Self.item("A", windowID: 1)
        let second = Self.item("B", windowID: 2)
        let third = Self.item("C", windowID: 3)

        var pass = MenuBarItemImageCache.CapturePass()
        pass.captured[first.tag] = try Self.capture(width: 20)
        pass.unreadable = [first]
        pass.invalidatedTags = [first.tag]
        pass.unconditionallyInvalidatedTags = [first.tag]
        pass.failedCaptureItems = [first]
        pass.recoveredItems = [first]
        pass.forgivenTags = [first.tag]

        var section = MenuBarItemImageCache.CapturePass()
        section.captured[second.tag] = try Self.capture(width: 22)
        section.unreadable = [second]
        section.invalidatedTags = [second.tag]
        section.unconditionallyInvalidatedTags = [third.tag]
        section.failedCaptureItems = [second, third]
        section.recoveredItems = [second]
        section.forgivenTags = [third.tag]

        pass.absorb(section)

        #expect(Set(pass.captured.keys) == [first.tag, second.tag])
        #expect(pass.unreadable.map(\.windowID) == [1, 2])
        #expect(pass.invalidatedTags == [first.tag, second.tag])
        #expect(pass.unconditionallyInvalidatedTags == [first.tag, third.tag])
        #expect(pass.failedCaptureItems.map(\.windowID) == [1, 2, 3])
        #expect(pass.recoveredItems.map(\.windowID) == [1, 2])
        #expect(pass.forgivenTags == [first.tag, third.tag])
    }

    @Test("A later section's crop replaces an earlier one for the same item")
    func absorbPrefersTheLaterCrop() throws {
        let item = Self.item("A", windowID: 1)
        let earlier = try Self.capture(width: 20)
        let later = try Self.capture(width: 22)

        var pass = MenuBarItemImageCache.CapturePass()
        pass.captured[item.tag] = earlier
        var section = MenuBarItemImageCache.CapturePass()
        section.captured[item.tag] = later

        pass.absorb(section)

        #expect(pass.captured[item.tag] == later)
    }
}

/// Pins which items a capture pass still has to screenshot once the user has
/// asked for app icons instead of live previews.
///
/// Without narrowing, the capture loop keeps reading the bar to fill a cache
/// nothing consults. Narrowing wrongly is worse: an item skipped here that
/// some surface then draws from a capture falls back to a blank tile.
@Suite("Capture demand narrowing")
struct CaptureDemandNarrowingTests {
    private typealias Demand = MenuBarItemImageCache.CaptureDemand

    private static func item(
        _ namespace: MenuBarItemTag.Namespace,
        _ title: String
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, instanceIndex: 0),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private static let thirdParty = item(.string("com.example.app"), "Example")
    private static let systemModule = item(.controlCenter, "Wi-Fi")

    private static func demand(
        usesAppIcons: Bool,
        hasUnfilteredConsumer: Bool = false,
        alertRevealIdentifiers: Set<String> = []
    ) -> Demand {
        Demand(
            usesAppIcons: usesAppIcons,
            hasUnfilteredConsumer: hasUnfilteredConsumer,
            alertRevealIdentifiers: alertRevealIdentifiers
        )
    }

    @Test("Live previews capture everything")
    func livePreviewsCaptureEverything() {
        let items = [Self.thirdParty, Self.systemModule]
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            items,
            demand: Self.demand(usesAppIcons: false)
        )
        #expect(narrowed.count == 2)
    }

    @Test("App-icon mode keeps Apple modules and drops the rest")
    func appIconModeKeepsSystemPreviews() {
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            [Self.thirdParty, Self.systemModule],
            demand: Self.demand(usesAppIcons: true)
        )
        #expect(narrowed.map(\.tag) == [Self.systemModule.tag])
    }

    @Test("An item with no resolvable app icon keeps its capture")
    func unresolvedAppIconKeepsCapture() {
        let ownerless = MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .string("com.example.agent"),
                title: "Agent",
                instanceIndex: 0
            ),
            windowID: 3,
            ownerPID: 100,
            sourcePID: nil,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: "Agent",
            isOnScreen: true
        )
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            [Self.thirdParty, ownerless],
            demand: Self.demand(usesAppIcons: true)
        )
        #expect(narrowed.map(\.tag) == [ownerless.tag])
    }

    @Test("An item armed for alert reveal is captured in app-icon mode")
    func alertRevealSurvivesAppIconMode() {
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            [Self.thirdParty],
            demand: Self.demand(
                usesAppIcons: true,
                alertRevealIdentifiers: [Self.thirdParty.tag.tagIdentifier]
            )
        )
        #expect(narrowed.map(\.tag) == [Self.thirdParty.tag])
    }

    @Test("Search and the hotkey list read the cache directly, so nothing is dropped")
    func unfilteredConsumerDefeatsNarrowing() {
        let items = [Self.thirdParty, Self.systemModule]
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            items,
            demand: Self.demand(usesAppIcons: true, hasUnfilteredConsumer: true)
        )
        #expect(narrowed.count == 2)
    }
}

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

    @Test("The Layout pane on screen behind another app keeps its glyphs from the idle trim")
    func unfocusedLayoutPaneIsAConsumer() {
        let cache = MenuBarItemImageCache()
        let nav = navigation(frontmost: false)
        // The live refresh rests, but the trim must wait.
        #expect(!cache.hasVisibleCaptureConsumer(nav: nav))
        #expect(cache.hasUnfocusedCaptureConsumer(nav: nav))
    }

    @Test("Closed settings or a pane without glyphs still allows the idle trim")
    func otherStatesAllowTheTrim() {
        let cache = MenuBarItemImageCache()
        #expect(!cache.hasUnfocusedCaptureConsumer(nav: navigation(frontmost: false, settings: false)))
        #expect(!cache.hasUnfocusedCaptureConsumer(nav: navigation(pane: nil, frontmost: false)))
    }

    private func navigation(
        simpleMode: Bool = false,
        pane: SettingsNavigationIdentifier? = .menuBarLayout,
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
