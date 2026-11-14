//
//  AlwaysHiddenBarSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Zach
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

@MainActor
@Suite("Always Hidden bar settings", .serialized, .scratchDefaults)
struct AlwaysHiddenBarSettingsTests {
    @Test("Bar controls are available for either section, and absent when both are inline", arguments: [false, true], [false, true])
    func controls(useThawBar: Bool, alwaysHidden: Bool) async throws {
        for scheme in [ColorScheme.light, .dark] {
            let view = ThawForm {
                ThawSection("Behavior") {
                    ThawBarConfigurationControls(
                        alwaysShowHiddenItems: .constant(true),
                        useThawBar: .constant(useThawBar),
                        location: .constant(.dynamic),
                        layout: .constant(.grid),
                        gridColumns: .constant(4),
                        itemScale: .constant(1),
                        shortcutPlacement: .constant(.pointer),
                        useThawBarForAlwaysHidden: alwaysHidden,
                        context: .display
                    )
                }
            }
            .frame(width: 760, height: 1100)
            .preferredColorScheme(scheme)
            let page = OffscreenRender(view, size: CGSize(width: 760, height: 1100))
            await page.settle { page.texts().contains("Always show hidden items") }
            let texts = page.texts()
            let showsControls = useThawBar || alwaysHidden
            for label in ["Location", "Arrangement", "Columns", "When opened by a shortcut", "Item size"] {
                #expect(texts.contains(label) == showsControls, "\(label) follows either bar choice")
            }
            let bitmap = try #require(page.host.bitmapImageRepForCachingDisplay(in: page.host.bounds))
            page.host.cacheDisplay(in: page.host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            Attachment.record(png, named: "bar-controls-\(useThawBar)-\(alwaysHidden)-\(scheme).png")
        }
    }

    @Test("Always Hidden alone previews its own items and falls back when the section is disabled")
    func previewSection() async throws {
        let world = LayoutEditorWorld()
        world.appState.settings.layout.enableAlwaysHiddenSection = true
        world.seat([LayoutEditorWorld.item("Hidden item")], in: .hidden)
        let view = ThawBarPreview(
            itemManager: world.appState.itemManager,
            layout: .horizontal, gridColumns: 4, useThawBar: false,
            displayID: 0x00FF_FF00, itemSpacingOffset: 0, itemScale: 1,
            useThawBarForAlwaysHidden: true
        ).environment(world.appState)
        let page = OffscreenRender(view, size: CGSize(width: 640, height: 480))
        let empty = "Nothing in Always Hidden to preview. Drag items into Always Hidden in Layout to see them here."
        await page.settle { page.texts().contains(empty) }
        #expect(page.texts().contains(empty), "Hidden has an item, but Always Hidden is empty")
        #expect(page.elements(role: .radioButton, label: "Hidden").isEmpty,
                "a section that opens inline is not offered as the bar preview")

        world.appState.itemManager.itemCache[.alwaysHidden] = [LayoutEditorWorld.item("Always Hidden item")]
        await page.settle { !page.texts().contains(empty) }
        #expect(!page.texts().contains(empty))

        world.appState.settings.layout.enableAlwaysHiddenSection = false
        world.appState.itemManager.itemCache[.hidden] = []
        let hiddenEmpty = "Nothing in Hidden to preview. Drag items into Hidden in Layout to see them here."
        await page.settle { page.texts().contains(hiddenEmpty) }
        #expect(page.texts().contains(hiddenEmpty), "a dormant Always Hidden choice does not take effect")
    }

    @Test("Always Hidden alone offers to open its section without turning on Hidden")
    func footer() async throws {
        try requireDisplay()
        let world = LayoutEditorWorld()
        let footer = ThawBarPreviewFooter(
            useThawBar: false, displayID: try #require(NSScreen.screens.first?.displayID), alwaysHiddenOnly: true
        )
        #expect(footer.sectionToOpen == .alwaysHidden)
        #expect(ThawBarPreviewFooter(useThawBar: true, displayID: nil).sectionToOpen == .hidden)
        let page = OffscreenRender(footer.environment(world.appState), size: CGSize(width: 640, height: 160))
        await page.settle { !page.elements(role: .button, label: "Open \(Constants.displayName) Bar").isEmpty }
        #expect(page.texts().contains("Preview uses the current Always Hidden section. Open the real \(Constants.displayName) Bar to use it."))
        #expect(!page.elements(role: .button, label: "Open \(Constants.displayName) Bar").isEmpty)
        #expect(page.elements(role: .button, label: "Turn On & Open").isEmpty)
    }
}
