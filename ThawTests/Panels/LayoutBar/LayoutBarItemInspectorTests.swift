//
//  LayoutBarItemInspectorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import PlatformRuntimeKit
import SwiftUI
import Testing
@testable import Thaw

/// The item inspector popover and the icon picker, rendered off screen against throwaway settings.
@MainActor
@Suite("Layout bar inspector and icon picker", .serialized, .scratchDefaults)
struct LayoutBarItemInspectorTests {
    private typealias World = LayoutEditorWorld

    private func inspector(
        _ item: MenuBarItem,
        orderedItems: [MenuBarItem],
        world: World,
        onShowAllActions: @escaping () -> Void = {}
    ) -> some View {
        LayoutBarItemInspector(
            item: item,
            section: .hidden,
            orderedItems: orderedItems,
            appState: world.appState,
            onShowAllActions: onShowAllActions
        )
    }

    @Test("The inspector lays out at its fixed width and grows a line for the item's position")
    func inspectorLayout() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        world.seat([alpha, beta], in: .hidden)

        let placed = OffscreenRender(inspector(alpha, orderedItems: [beta, alpha], world: world), size: CGSize(width: 268, height: 400))
        let unplaced = OffscreenRender(inspector(alpha, orderedItems: [], world: world), size: CGSize(width: 268, height: 400))
        #expect(placed.host.fittingSize.width == 268)
        #expect(placed.host.fittingSize.height > unplaced.host.fittingSize.height, "the Position line adds a row")
        #expect(try placed.pixels().contains { $0 != 0 })
    }

    @Test("A custom name and a reveal switch the user turned on are what the inspector opens with")
    func inspectorReadsStoredState() throws {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = "Renamed"
        MenuBarItemAlertReveals.setEnabled(true, for: alpha.tag.tagIdentifier)
        let size = CGSize(width: 268, height: 400)
        let stored = try OffscreenRender(inspector(alpha, orderedItems: [alpha], world: world), size: size).pixels()

        alpha.customName = nil
        MenuBarItemAlertReveals.setEnabled(false, for: alpha.tag.tagIdentifier)
        let plain = try OffscreenRender(inspector(alpha, orderedItems: [alpha], world: world), size: size).pixels()
        #expect(stored != plain)
    }

    @Test("Closing the inspector keeps a name the user did not change")
    func closingKeepsTheName() async {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = "Kept"
        let render = OffscreenRender(AnyView(inspector(alpha, orderedItems: [alpha], world: world)), size: CGSize(width: 268, height: 400))
        render.host.rootView = AnyView(EmptyView())
        await render.settle(within: .milliseconds(200)) { false }
        #expect(alpha.customName == "Kept")
    }

    @Test("The icon picker offers the app's icons, or says it found none")
    func iconPicker() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let size = CGSize(width: 460, height: 420)
        let icon = try #require(NSImage(systemSymbolName: "star", accessibilityDescription: nil))
        let candidates = [
            BundledStatusIcon.Candidate(name: "star", image: icon, isLoose: true),
            BundledStatusIcon.Candidate(name: "star2", image: icon, isLoose: false),
        ]
        let withIcons = try OffscreenRender(
            ItemIconPickerView(item: alpha, candidates: candidates, onDone: {}).environment(world.appState),
            size: size
        ).pixels()
        let empty = try OffscreenRender(
            ItemIconPickerView(item: alpha, candidates: [], onDone: {}).environment(world.appState),
            size: size
        ).pixels()
        #expect(withIcons.contains { $0 != 0 })
        #expect(withIcons != empty)
    }
}

/// The inspector's header glyph and its warning for system modules, rendered off screen.
@MainActor
@Suite("Layout bar inspector header and module warning", .serialized, .scratchDefaults)
struct LayoutBarItemInspectorHeaderTests {
    private typealias World = LayoutEditorWorld
    private static let size = CGSize(width: 268, height: 400)

    private func render(_ item: MenuBarItem, world: World) -> OffscreenRender<LayoutBarItemInspector> {
        OffscreenRender(
            LayoutBarItemInspector(item: item, section: .visible, orderedItems: [item], appState: world.appState) {},
            size: Self.size
        )
    }

    private static func capture() throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil, width: 60, height: 36, bitsPerComponent: 8, bytesPerRow: 60 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 36))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 2)
    }

    @Test("The header shows the item's capture in place of its app icon")
    func headerUsesTheCapture() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let iconOnly = try render(alpha, world: world).pixels()
        try world.appState.imageCache.setCapture(Self.capture(), for: alpha.tag)
        defer { world.appState.imageCache.removeCapture(for: alpha.tag) }
        let captured = try render(alpha, world: world).pixels()
        #expect(captured != iconOnly)
    }

    @Test("A Control Center module the inspector can hide warns that hiding turns off its System Settings switch")
    func governableModuleWarns() throws {
        let module = try #require(
            RuntimeModuleController.moduleKeysByMenuExtraTitle.keys.sorted()
                .map { World.item(MenuBarItemTag(namespace: .string("com.apple.controlcenter"), title: $0, instanceIndex: 0)) }
                .first { RuntimeModuleController.isGovernable(itemIdentifier: $0.uniqueIdentifier) },
            "some Control Center module is governable"
        )
        let app = World.item(MenuBarItemTag(namespace: .string("com.apple.controlcenter"), title: "com.apple.menuextra.thawtest", instanceIndex: 0))
        #expect(!RuntimeModuleController.isGovernable(itemIdentifier: app.uniqueIdentifier))

        let world = World()
        let warned = render(module, world: world).host.fittingSize.height
        let plain = render(app, world: world).host.fittingSize.height
        #expect(warned > plain, "the warning adds lines below the facts")
    }

    @Test("A picked image is drawn 18 points tall at its own aspect ratio, and an empty one as a square")
    func pickedImageSize() {
        #expect(ItemIconPickerView.menuBarSize(for: CGSize(width: 512, height: 256)) == CGSize(width: 32, height: 16))
        #expect(ItemIconPickerView.menuBarSize(for: CGSize(width: 9, height: 9)) == CGSize(width: 16, height: 16))
        #expect(ItemIconPickerView.menuBarSize(for: CGSize(width: 40, height: 0)) == CGSize(width: 16, height: 16))
    }
}
