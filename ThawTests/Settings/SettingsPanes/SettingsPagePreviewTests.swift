//
//  SettingsPagePreviewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

#if DEBUG
    import AppKit
    import SwiftUI
    import Testing
    @testable import Thaw

    /// SettingsRemote.current is main actor state that suites outside the scratch gate read too,
    /// ModuleHostTests among them. Each test puts it back before its first suspension point, so no
    /// other test can see the preview's link.
    @MainActor
    @Suite("Settings page previews", .serialized, .scratchDefaults)
    struct SettingsPagePreviewTests {
        private static let size = CGSize(width: 760, height: 720)

        /// A scratch suite and profiles folder, removed after body.
        private func withScratch(_ body: (_ suite: String, _ profiles: URL) async throws -> Void) async rethrows {
            let suite = ScratchDefaults.name("settings-previews")
            let profiles = FileManager.default.temporaryDirectory
                .appending(path: "ThawTestProfiles/\(UUID().uuidString)", directoryHint: .isDirectory)
            defer {
                ScratchDefaults.remove(suite)
                try? FileManager.default.removeItem(at: profiles)
            }
            try await body(suite, profiles)
        }

        /// Runs body, which must not suspend, and puts the settings link back after it.
        private func withPreviewLink<T>(_ body: () -> T) -> T {
            let previous = SettingsRemote.current
            defer { SettingsRemote.current = previous }
            return body()
        }

        @Test("A preview app state keeps settings, profiles, spacing and the settings link away from the Mac")
        func appStateIsIsolated() async throws {
            try await withScratch { suite, profiles in
                let original = Defaults.store
                let key = Defaults.Key.lastSettingsPane.rawValue
                let (appState, linked, presentation) = withPreviewLink {
                    let appState = SettingsPreviewApp.make(suiteName: suite, profilesDirectory: profiles)
                    return (appState, SettingsRemote.current === SettingsPreviewApp.link, MenuBarPresentationProvider.forSettings)
                }

                #expect(linked, "pages reach no app")
                #expect(presentation === RemoteMenuBarPresentation.shared, "the Spaces controls ask over the link, not the menu bar agent")
                Defaults.set("preview", forKey: .lastSettingsPane)
                #expect(UserDefaults(suiteName: suite)?.string(forKey: key) == "preview", "settings go to the preview's own suite")
                #expect(original.string(forKey: key) == nil, "and not to the store that was there before")
                #expect(FileManager.default.fileExists(atPath: profiles.path), "profiles go to the folder given")
                #expect(appState.settings.displaySettings.spacingHost == nil, "never started, so a spacing change can't relaunch apps")
                #expect(appState.spacingManager.spacingApplyMode == .writeOnly, "and the spacing manager wouldn't relaunch them anyway")
                try await appState.spacingManager.store.write("NSStatusItemSpacing", 20)
                #expect(appState.spacingManager.store.read("NSStatusItemSpacing") == nil, "spacing is kept nowhere")
            }
        }

        @Test("A new preview app state starts from empty settings and profiles")
        func leftoversAreDiscarded() async throws {
            try await withScratch { suite, profiles in
                _ = withPreviewLink { SettingsPreviewApp.make(suiteName: suite, profilesDirectory: profiles) }
                Defaults.set("old preview", forKey: .lastSettingsPane)
                let leftover = profiles.appending(path: "leftover.json")
                try Data("{}".utf8).write(to: leftover)

                _ = withPreviewLink { SettingsPreviewApp.make(suiteName: suite, profilesDirectory: profiles) }

                #expect(Defaults.string(forKey: .lastSettingsPane) == nil, "preview settings are discarded")
                #expect(!FileManager.default.fileExists(atPath: leftover.path), "preview profiles are discarded")
            }
        }

        @Test("The Displays and Thaw Bar previews show their tabs and controls in light and dark mode", arguments: [ColorScheme.light, .dark])
        func pagesDraw(scheme: ColorScheme) async throws {
            try await withScratch { suite, profiles in
                let displays = render(scheme: scheme) {
                    SettingsPagePreview(
                        suiteName: suite,
                        profilesDirectory: profiles,
                        prepare: { $0.settings.displaySettings.addPreviewSavedDisplay() },
                        page: { DisplaySettingsPane(displaySettings: $0.settings.displaySettings) }
                    )
                }
                try await expectShows(["Spacing", "Template", "Spaces", "Wide Displays", "Not connected"], on: displays, named: "displays", scheme: scheme)

                let thawBar = render(scheme: scheme) {
                    SettingsPagePreview(
                        suiteName: suite,
                        profilesDirectory: profiles,
                        prepare: { $0.settings.displaySettings.addPreviewSavedDisplay() },
                        page: { ThawBarSettingsPane(displaySettings: $0.settings.displaySettings) }
                    )
                }
                try await expectShows(["Display", "Look", "All Displays", "Always show hidden items"], on: thawBar, named: "thaw-bar", scheme: scheme)
            }
        }

        /// Makes the preview and lays it out off screen, then puts the settings link back. The page
        /// keeps the link only for what it read while being built; anything it reads later sees the
        /// test process's own. So only read labels here: don't press controls or open a tab, since the
        /// Spaces tab, for one, would then reach the live menu bar agent.
        private func render(scheme: ColorScheme, _ preview: () -> some View) -> OffscreenRender<AnyView> {
            withPreviewLink {
                OffscreenRender(AnyView(preview().preferredColorScheme(scheme)), size: Self.size)
            }
        }

        /// Waits for the page to show labels, checks it does, and keeps a picture of it.
        private func expectShows(
            _ labels: [String],
            on page: OffscreenRender<AnyView>,
            named name: String,
            scheme: ColorScheme,
            sourceLocation: SourceLocation = #_sourceLocation
        ) async throws {
            await page.settle { labels.allSatisfy { page.texts().contains($0) } }
            let missing = labels.filter { !page.texts().contains($0) }
            #expect(missing.isEmpty, "\(name) shows \(missing)", sourceLocation: sourceLocation)
            let bitmap = try #require(page.host.bitmapImageRepForCachingDisplay(in: page.host.bounds))
            page.host.cacheDisplay(in: page.host.bounds, to: bitmap)
            Attachment.record(try #require(bitmap.representation(using: .png, properties: [:])), named: "\(name)-\(scheme).png")
        }
    }
#endif
