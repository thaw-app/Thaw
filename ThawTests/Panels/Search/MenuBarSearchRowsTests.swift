//
//  MenuBarSearchRowsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// The search list's rows in each face, and the model's colour sampling attachment.
@MainActor
@Suite("Search rows and model", .serialized, .scratchDefaults)
struct MenuBarSearchRowsTests {
    private typealias World = LayoutEditorWorld

    private func render(_ row: MenuBarSearchListContent, world: World, model: MenuBarSearchModel, panel: MenuBarSearchPanel?) throws -> (Data, CGSize) {
        let view = row
            .environment(world.appState)
            .environment(world.appState.imageCache)
            .environment(model)
            .environment(\.menuBarSearchPanel, panel)
            .frame(width: 320)
        let render = OffscreenRender(view, size: CGSize(width: 320, height: 80))
        return try (render.pixels(), render.host.fittingSize)
    }

    @Test("Launcher and assisted rows draw the owner only when given one, and the assisted row is taller")
    func paletteRows() throws {
        let world = World()
        let model = MenuBarSearchModel()
        let alpha = World.item("Alpha")
        let (launcher, launcherSize) = try render(.launcherItem(alpha, ownerName: nil), world: world, model: model, panel: nil)
        let (withOwner, _) = try render(.launcherItem(alpha, ownerName: "Owner App"), world: world, model: model, panel: nil)
        let (_, assistedSize) = try render(.assistedItem(alpha, ownerName: "Owner App"), world: world, model: model, panel: nil)
        #expect(launcher.contains { $0 != 0 })
        #expect(launcher != withOwner)
        #expect(assistedSize.height >= 44, "the assisted row keeps its minimum target")
        #expect(assistedSize.height > launcherSize.height)
    }

    @Test("A system agent's row and an item with no owner each draw an icon")
    func sourceIcons() throws {
        let world = World()
        let model = MenuBarSearchModel()
        let controlCenter = World.item(MenuBarItemTag(namespace: .controlCenter, title: "Battery", instanceIndex: 0))
        let ownerless = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.Ownerless"), title: "Ownerless", instanceIndex: 0),
            windowID: 4242,
            ownerPID: 0,
            sourcePID: nil,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: "Ownerless",
            isOnScreen: true
        )
        let (system, _) = try render(.launcherItem(controlCenter, ownerName: nil), world: world, model: model, panel: nil)
        let (placeholder, _) = try render(.launcherItem(ownerless, ownerName: nil), world: world, model: model, panel: nil)
        #expect(system.contains { $0 != 0 })
        #expect(placeholder.contains { $0 != 0 })
        #expect(system != placeholder)
    }

    @Test("An inspector row swaps its label for a rename field while it is being renamed")
    func inspectorRowRenames() throws {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = MenuBarSearchPanel()
        panel.performSetup(with: world.appState, displayInvalidations: PassthroughSubject<Void, Never>())
        let model = panel.model
        let (plain, _) = try render(.item(alpha), world: world, model: model, panel: panel)
        model.renameSession = .init(tag: alpha.tag, windowID: alpha.windowID, draft: "Draft name")
        let (renaming, _) = try render(.item(alpha), world: world, model: model, panel: panel)
        #expect(plain.contains { $0 != 0 })
        #expect(plain != renaming)
    }

    @Test("Detaching or hiding the panel leaves no sampled colour, and a display change clears it")
    func attachAndDetach() {
        let model = MenuBarSearchModel()
        let panel = MenuBarSearchPanel()
        let displays = PassthroughSubject<Void, Never>()
        model.attach(to: panel, displayInvalidations: displays)
        displays.send()
        #expect(model.averageColorInfo == nil)
        model.attach(to: panel, displayInvalidations: displays)
        model.detach()
        displays.send()
        #expect(model.averageColorInfo == nil)
        #expect(model.launcherCandidates.isEmpty)
    }
}
