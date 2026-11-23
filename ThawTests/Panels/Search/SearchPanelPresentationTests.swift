//
//  SearchPanelPresentationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import CoreGraphics
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// The search panel's two layouts and the window they share.
@Suite("Search panel layouts")
struct SearchPresentationTests {
    @Test("Raw values are the stored names")
    func rawValuesAreStorage() {
        #expect(SearchPresentation.allCases.map(\.rawValue) == ["extended", "compact"])
        #expect(SearchPresentation(rawValue: "spotlight") == nil)
    }

    @Test("The three panel styles before the launcher migrate to a layout", arguments: [
        ("inspector", SearchPresentation.extended),
        ("assisted", .extended),
        ("launcher", .compact),
        ("extended", .extended),
        ("compact", .compact),
    ])
    func storedValuesMigrate(stored: String, layout: SearchPresentation) {
        #expect(SearchPresentation(storedValue: stored) == layout)
    }

    @Test("An unknown stored value reads as nothing, so the default stands")
    func unknownStoredValue() {
        #expect(SearchPresentation(storedValue: "spotlight") == nil)
    }

    @Test("Only Compact with nothing typed collapses to the field")
    func collapsing() {
        #expect(SearchPresentation.compact.isCollapsed(query: ""))
        #expect(SearchPresentation.compact.isCollapsed(query: "  "))
        #expect(!SearchPresentation.compact.isCollapsed(query: "wi"))
        #expect(!SearchPresentation.extended.isCollapsed(query: ""))
    }

    @Test("The panel is Floe's launcher: 750 by 474 open, the field's piece alone collapsed")
    func geometry() {
        #expect(SearchPanelGeometry.contentSize(isCollapsed: false) == CGSize(width: 750, height: 474))
        #expect(SearchPanelGeometry.contentSize(isCollapsed: true).height == PanelPieceHeights.launcherField)
        let open = SearchPanelGeometry.windowSize(isCollapsed: false)
        #expect(open.width == 750 + SearchPanelGeometry.margin * 2)
        #expect(open.height == 474 + SearchPanelGeometry.margin * 2)
    }

    @Test("Collapsing keeps the field where it is: the window's top stays put")
    func collapsingKeepsTheTop() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        let open = SearchPanelGeometry.frame(isCollapsed: false, in: visible)
        let collapsed = SearchPanelGeometry.frame(isCollapsed: true, in: visible)
        #expect(open.maxY == collapsed.maxY)
        #expect(open.midX == visible.midX)
        #expect(collapsed.height < open.height)
    }
}

/// The search panel follows the menu bar's look, as Floe does when it follows Thaw.
@Suite("Search panel look")
struct SearchLauncherLookTests {
    private func look(_ configure: (inout MenuBarAppearancePartialConfiguration) -> Void) -> LauncherLook {
        var configuration = MenuBarAppearancePartialConfiguration.defaultConfiguration
        configure(&configuration)
        return SharedAppearance(configuration: configuration, shapeKind: .full, hasRoundedShape: true, isDark: true).launcherLook()
    }

    @Test("A plain bar leaves the launcher's own glass, with no tint, border or shadow")
    func plainBar() {
        let look = look { configuration in
            configuration.tintKind = .noTint
            configuration.backgroundKind = .none
            configuration.hasBorder = false
            configuration.hasShadow = false
        }
        #expect(look.glass.style == .regular)
        #expect(look.tint.kind == .none)
        #expect(look.border == nil)
        #expect(!look.hasShadow)
    }

    @Test("The bar's Dynamic Glass, border and shadow carry over")
    func dynamicGlass() {
        let look = look { configuration in
            configuration.tintKind = .glass
            configuration.tintGlassFinish = MenuBarGlassFinish(style: .dynamic, isTinted: false)
            configuration.hasBorder = true
            configuration.borderWidth = 2
            configuration.hasShadow = true
        }
        #expect(look.glass.style == .dynamic)
        #expect(look.tint.kind == .none, "a glass is not a tint")
        #expect(look.border?.width == 2)
        #expect(look.hasShadow)
    }

    @Test("A solid tint becomes the launcher's tint, at its opacity")
    func solidTint() {
        let look = look { configuration in
            configuration.tintKind = .solid
            configuration.tintColor = CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)
            configuration.tintOpacity = 0.4
        }
        #expect(look.tint.kind == .solid)
        #expect(look.tint.opacity == 0.4)
        #expect(look.tint.solid.red == 1)
        #expect(look.tint.backgroundStyle != nil)
    }

    @Test("A gradient takes its outermost stops and its angle")
    func gradientTint() {
        let look = look { configuration in
            configuration.tintKind = .gradient
            configuration.tintGradient = ThawGradient(stops: [
                .stop(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), location: 0),
                .stop(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), location: 0.5),
                .stop(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), location: 1),
            ])
        }
        #expect(look.tint.kind == .gradient)
        #expect(look.tint.gradient.start.red == 1)
        #expect(look.tint.gradient.end.blue == 1)
    }

    @Test("An adaptive tint has no colour to copy, so the launcher keeps its own")
    func adaptiveTintIsNotCopied() {
        let look = look { configuration in
            configuration.tintKind = .adaptive
            configuration.backgroundKind = .none
        }
        #expect(look.tint == LauncherTint())
    }
}

/// The bar under the search list, with the shortcut bar on and off.
@MainActor
@Suite("Search panel footer", .serialized, .scratchDefaults)
struct MenuBarSearchFooterTests {
    private typealias World = LayoutEditorWorld

    private struct Hosted: View {
        let world: World
        let panel: MenuBarSearchPanel

        var body: some View {
            MenuBarSearchFooter(panel: panel)
                .environment(world.appState)
                .environment(panel.model)
                .defaultAppStorage(Defaults.store)
        }
    }

    private static func render(_ world: World, _ panel: MenuBarSearchPanel) -> OffscreenRender<Hosted> {
        OffscreenRender(Hosted(world: world, panel: panel), size: CGSize(width: 480, height: 160))
    }

    @Test("With the shortcut bar off, nothing is drawn until a move is refused, and then the notice is")
    func hiddenBarKeepsTheNotice() async {
        Defaults.set(false, forKey: .showSearchShortcutBar)
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = MenuBarSearchPanel()
        panel.performSetup(with: world.appState, displayInvalidations: PassthroughSubject<Void, Never>())
        panel.model.results = [MenuBarSearchResult(item: alpha, ownerName: nil, section: nil)]
        panel.model.selection = MenuBarSearchModel.ItemID(alpha)
        let render = Self.render(world, panel)
        #expect(render.host.fittingSize.height == 0, "no bar, no notice")
        #expect(panel.itemActionsAnchor == nil, "the Actions button is not there to anchor ⌘K")

        world.appState.layoutFeedback.post(LayoutBarFeedbackCenter.itemNotMovable(itemName: "Alpha"))
        await render.settle { render.host.fittingSize.height > 0 }
        #expect(render.host.fittingSize.height > 0, "the refusal still shows")
    }

    @Test("With the shortcut bar on, it draws for the highlighted row and anchors ⌘K's menu")
    func shownBar() async {
        Defaults.set(true, forKey: .showSearchShortcutBar)
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = MenuBarSearchPanel()
        panel.performSetup(with: world.appState, displayInvalidations: PassthroughSubject<Void, Never>())
        panel.model.results = [MenuBarSearchResult(item: alpha, ownerName: nil, section: nil)]
        panel.model.selection = MenuBarSearchModel.ItemID(alpha)
        let render = Self.render(world, panel)
        await render.settle { panel.itemActionsAnchor != nil }
        #expect(render.host.fittingSize.height > 0)
        #expect(panel.itemActionsAnchor != nil)
    }
}

@MainActor
@Suite("Search VoiceOver announcements", .serialized, .scratchDefaults)
struct MenuBarSearchAnnouncementTests {
    private typealias World = LayoutEditorWorld

    private func result(_ title: String, section: String?) -> MenuBarSearchResult {
        let item = World.item(title)
        Defaults.set([item.uniqueIdentifier: title], forKey: .menuBarItemCustomNames)
        return MenuBarSearchResult(item: item, ownerName: nil, section: section)
    }

    @Test("A row is read with its section, and alone without one")
    func row() {
        #expect(MenuBarSearchAnnouncement.row(result("Alpha", section: "Hidden")) == "Alpha, Hidden")
        #expect(MenuBarSearchAnnouncement.row(result("Alpha", section: nil)) == "Alpha")
    }

    @Test("Results are read as a count and the first match")
    func results() {
        let alpha = result("Alpha", section: nil)
        #expect(MenuBarSearchAnnouncement.results([alpha]) == "1 result. Alpha")
        #expect(MenuBarSearchAnnouncement.results([alpha, alpha]) == "2 results. Alpha")
        #expect(MenuBarSearchAnnouncement.results([]) == "0 results")
    }
}

/// A search that matched nothing left no way back but deleting the query by hand.
@MainActor
@Suite("Search empty states")
struct SearchEmptyStatesTests {
    @Test("No matches draws taller with its Clear Search button than without one")
    func noMatchesOffersClearSearch() {
        let withAction = NSHostingView(rootView: ThawEmptyState.noSearchMatches {}.frame(width: 320))
        let withoutAction = NSHostingView(rootView: ThawEmptyState(
            systemImage: "magnifyingglass",
            title: "No items match",
            caption: "Try part of the item's name or the app that owns it."
        ).frame(width: 320))
        withAction.layoutSubtreeIfNeeded()
        withoutAction.layoutSubtreeIfNeeded()
        #expect(withAction.fittingSize.height > withoutAction.fittingSize.height)
    }
}
