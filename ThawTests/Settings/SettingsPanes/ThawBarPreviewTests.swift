//
//  ThawBarPreviewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// The Thaw Bar preview and the strip under it, drawn off screen against an AppState that is never
/// started. The preview sits on a display number no Mac has, so it never samples a real wallpaper,
/// and the buttons that open the real bar are looked for and never pressed.
@MainActor
@Suite("Thaw Bar preview", .serialized, .scratchDefaults)
struct ThawBarPreviewTests {
    private typealias World = LayoutEditorWorld
    private typealias Page = OffscreenRender<AnyView>

    private static let size = CGSize(width: 640, height: 480)
    /// A display ID no Mac is given, so the preview has no screen to read.
    private static let missingDisplay = CGDirectDisplayID(0x00FF_FF00)

    private func render(_ view: some View, appState: AppState) -> Page {
        OffscreenRender(
            AnyView(
                view
                    .environment(appState)
                    .environment(\.settingsPaneTitle, nil)
                    .frame(width: Self.size.width, height: Self.size.height)
            ),
            size: Self.size
        )
    }

    private func preview(
        _ world: World,
        layout: ThawBarLayout = .horizontal,
        columns: Int = 3,
        useThawBar: Bool = true,
        displayID: CGDirectDisplayID? = ThawBarPreviewTests.missingDisplay
    ) -> Page {
        render(
            ThawBarPreview(
                itemManager: world.appState.itemManager,
                layout: layout,
                gridColumns: columns,
                useThawBar: useThawBar,
                displayID: displayID,
                itemSpacingOffset: 0,
                itemScale: 1
            ),
            appState: world.appState
        )
    }

    private func drawn(_ page: Page) async throws -> Data {
        await page.settle { (try? page.pixels())?.contains { $0 != 0 } == true }
        return try page.pixels()
    }

    private func seatHidden(_ world: World, _ titles: [String]) {
        world.seat(titles.map(World.item), in: .hidden)
    }

    @Test("With nothing hidden the preview says so, and Open Layout goes to the Layout page")
    func emptyPreview() async throws {
        let world = World()
        let page = preview(world)
        _ = try await drawn(page)
        let message = "Nothing in Hidden to preview. Drag items into Hidden in Layout to see them here."
        #expect(page.texts().contains(message))

        world.appState.navigationState.settingsNavigationIdentifier = .displays
        try page.press("Open Layout")
        #expect(world.appState.navigationState.settingsNavigationIdentifier == .menuBarLayout)
    }

    @Test("Hidden items replace the message, and each arrangement draws them its own way")
    func arrangements() async throws {
        let world = World()
        seatHidden(world, ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"])
        let empty = try await drawn(preview(World()))

        var drawings: [ThawBarLayout: Data] = [:]
        for layout in [ThawBarLayout.horizontal, .vertical, .grid] {
            let page = preview(world, layout: layout)
            let pixels = try await drawn(page)
            #expect(!page.texts().contains { $0.hasPrefix("Nothing in Hidden") }, "\(layout) shows the items")
            #expect(pixels != empty, "\(layout) draws something other than the empty message")
            drawings[layout] = pixels
        }
        #expect(drawings[.horizontal] != drawings[.vertical])
        #expect(drawings[.horizontal] != drawings[.grid])
        #expect(drawings[.vertical] != drawings[.grid])

        let twoColumns = try await drawn(preview(world, layout: .grid, columns: 2))
        let fiveColumns = try await drawn(preview(world, layout: .grid, columns: 5))
        #expect(twoColumns != fiveColumns, "the grid follows its column count")
    }

    @Test("With Always Hidden on, the preview can show either section, and says when one is empty")
    func alwaysHiddenSection() async throws {
        let world = World()
        world.appState.settings.layout.enableAlwaysHiddenSection = true
        seatHidden(world, ["Alpha", "Beta"])
        let page = preview(world)
        let hidden = try await drawn(page)
        #expect(!page.texts().contains { $0.hasPrefix("Nothing in") })

        let always = try #require(page.elements().first {
            OffscreenAccessibility.role(of: $0) == .radioButton && OffscreenAccessibility.label(of: $0) == "Always Hidden"
        })
        OffscreenAccessibility.press(always)
        let message = "Nothing in Always Hidden to preview. Drag items into Always Hidden in Layout to see them here."
        await page.settle { page.texts().contains(message) }
        #expect(page.texts().contains(message))
        #expect(try page.pixels() != hidden)

        world.appState.itemManager.itemCache[.alwaysHidden] = [World.item("Zeta")]
        await page.settle { !page.texts().contains(message) }
        #expect(!page.texts().contains(message), "an item in Always Hidden fills the section")
    }

    @Test("A border in the bar's appearance is drawn around the preview")
    func borderIsDrawn() async throws {
        let world = World()
        seatHidden(world, ["Alpha", "Beta"])
        var configuration = world.appState.appearanceManager.configuration
        configuration.thawBarAppearance.overridesMenuBar = true
        configuration.thawBarAppearance.hasBorder = false
        configuration.thawBarAppearance.borderWidth = 4
        configuration.thawBarAppearance.borderColor = NSColor.systemRed.cgColor
        world.appState.appearanceManager.configuration = configuration
        let page = preview(world)
        let plain = try await drawn(page)

        configuration.thawBarAppearance.hasBorder = true
        world.appState.appearanceManager.configuration = configuration
        await page.settle { (try? page.pixels()) != plain }
        #expect(try page.pixels() != plain, "the border stroke changes the drawing")
    }

    @Test("Under the preview, the strip says where the real bar opens")
    func footerWithoutDisplay() async throws {
        let world = World()
        let none = render(ThawBarPreviewFooter(useThawBar: true, displayID: nil), appState: world.appState)
        _ = try await drawn(none)
        #expect(none.texts().contains("Pick a connected display to open the \(Constants.displayName) Bar."))
        #expect(none.texts().contains("Preview uses the current hidden section. The real \(Constants.displayName) Bar opens on a connected display."))
        #expect(none.elements().allSatisfy { OffscreenAccessibility.role(of: $0) != .button }, "there is nothing to open")

        let gone = render(ThawBarPreviewFooter(useThawBar: true, displayID: Self.missingDisplay), appState: world.appState)
        _ = try await drawn(gone)
        #expect(gone.texts().contains("Reconnect this display to open the \(Constants.displayName) Bar."))
        #expect(gone.elements().allSatisfy { OffscreenAccessibility.role(of: $0) != .button })
    }

    @Test("On a connected display the strip offers to open the bar, or to turn it on first")
    func footerWithDisplay() async throws {
        try requireDisplay()
        let world = World()
        let displayID = try #require(NSScreen.screens.first?.displayID)
        let on = render(ThawBarPreviewFooter(useThawBar: true, displayID: displayID), appState: world.appState)
        _ = try await drawn(on)
        #expect(!on.elements(role: .button, label: "Open \(Constants.displayName) Bar").isEmpty)
        #expect(on.elements(role: .button, label: "Turn On & Open").isEmpty)
        #expect(on.texts().contains("Preview uses the current hidden section. Open the real \(Constants.displayName) Bar to use it."))

        let off = render(ThawBarPreviewFooter(useThawBar: false, displayID: displayID), appState: world.appState)
        _ = try await drawn(off)
        #expect(!off.elements(role: .button, label: "Turn On & Open").isEmpty)
        #expect(off.elements(role: .button, label: "Open \(Constants.displayName) Bar").isEmpty)
        #expect(off.texts().contains("Preview uses the current hidden section. The \(Constants.displayName) Bar is off on this display."))
    }

    @Test("The stage draws a plain backdrop when the display has no wallpaper to show")
    func stageWithoutWallpaper() async throws {
        let world = World()
        let page = render(
            ThawBarPreviewStage(displayID: Self.missingDisplay) { Text(verbatim: "Inside") },
            appState: world.appState
        )
        _ = try await drawn(page)
        #expect(page.texts().contains("Inside"))
    }
}
