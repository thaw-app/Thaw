//
//  VisibilitySettingsPreviewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Zach
//  Licensed under the GNU GPLv3

#if DEBUG
    import AppKit
    import SwiftUI
    import Testing
    @testable import Thaw

    @MainActor
    @Suite("Visibility settings previews", .serialized, .scratchDefaults)
    struct VisibilitySettingsPreviewTests {
        @Test("Preview interactions write to their own preferences, and a new preview starts fresh")
        func preferencesAreIsolated() {
            let suite = ScratchDefaults.name("visibility-previews")
            defer { ScratchDefaults.remove(suite) }
            let original = Defaults.store
            let key = Defaults.Key.showOnHover.rawValue
            original.set(false, forKey: key)
            let settings = VisibilityPreviewSettings.make(suiteName: suite)
            #expect(Defaults.store !== original)
            #expect(settings.showOnHover)
            settings.showOnHover = false
            #expect(!Defaults.bool(forKey: .showOnHover))
            settings.showOnHover = true
            #expect(Defaults.bool(forKey: .showOnHover))
            #expect(!original.bool(forKey: key), "preview edits leave the original domain alone")
            Defaults.set("old preview", forKey: .lastSettingsPane)
            _ = VisibilityPreviewSettings.make(suiteName: suite)
            #expect(Defaults.string(forKey: .lastSettingsPane) == nil, "preview leftovers are discarded")
        }

        @Test("Timing and recording previews show their controls in light and dark mode", arguments: [ColorScheme.light, .dark])
        func rowsDraw(scheme: ColorScheme) async throws {
            let suite = ScratchDefaults.name("visibility-previews")
            defer { ScratchDefaults.remove(suite) }
            let timing = VisibilitySettingsPreview(suiteName: suite) { settings in
                HoverDelayRow(settings: settings)
                TooltipDelayRow(settings: settings)
                RehideDelayRow(settings: settings)
                SwapOnIconClickToggle(settings: settings)
            }
            let alerts = VisibilitySettingsPreview(suiteName: suite) { settings in
                RecordingAlertRows(settings: settings)
            }
            for (name, view, labels) in [
                ("timing", AnyView(timing), ["Hover delay", "Name delay", "Hide after", "Click the \(Constants.displayName) icon to swap"]),
                ("recording", AnyView(alerts), ["Alert when the camera or microphone turns on", "Show alerts on", "Alert position"]),
            ] {
                let page = OffscreenRender(view.preferredColorScheme(scheme), size: CGSize(width: 680, height: 560))
                await page.settle { labels.allSatisfy { page.texts().contains($0) } }
                #expect(labels.allSatisfy { page.texts().contains($0) })
                let bitmap = try #require(page.host.bitmapImageRepForCachingDisplay(in: page.host.bounds))
                page.host.cacheDisplay(in: page.host.bounds, to: bitmap)
                Attachment.record(try #require(bitmap.representation(using: .png, properties: [:])), named: "visibility-\(name)-\(scheme).png")
            }
        }
    }

#endif
