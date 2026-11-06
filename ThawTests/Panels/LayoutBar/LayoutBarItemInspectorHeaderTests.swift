//
//  LayoutBarItemInspectorHeaderTests.swift
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
        #expect(ItemIconPickerView.menuBarSize(for: CGSize(width: 512, height: 256)) == CGSize(width: 36, height: 18))
        #expect(ItemIconPickerView.menuBarSize(for: CGSize(width: 9, height: 9)) == CGSize(width: 18, height: 18))
        #expect(ItemIconPickerView.menuBarSize(for: CGSize(width: 40, height: 0)) == CGSize(width: 18, height: 18))
    }
}
