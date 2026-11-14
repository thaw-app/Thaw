//
//  VisibilitySettingsPreview.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

#if DEBUG
    import SwiftUI
    import ThawUI

    /// Only for the canvas: redirects process-wide defaults before creating the preview's model.
    /// No settings setup or menu bar managers are started.
    @MainActor
    enum VisibilityPreviewSettings {
        static let defaultSuiteName = "com.stonerl.Thaw.visibility-previews"

        /// Tests pass a scratch suite so no preferences file is left behind.
        static func make(suiteName domain: String = defaultSuiteName) -> VisibilitySettings {
            guard let store = UserDefaults(suiteName: domain) else {
                preconditionFailure("Could not create the Visibility preview preferences")
            }
            store.removePersistentDomain(forName: domain)
            Defaults.store = store
            let settings = VisibilitySettings()
            settings.showOnHover = true
            settings.showMenuBarTooltips = true
            settings.autoRehide = true
            settings.rehideStrategy = .timed
            settings.enableRecordingWatch = true
            return settings
        }
    }

    /// Gives the Visibility rows interactive state and the same form layout they use in Settings.
    struct VisibilitySettingsPreview<Content: View>: View {
        @State private var settings: VisibilitySettings
        private let content: (VisibilitySettings) -> Content

        init(
            suiteName: String = VisibilityPreviewSettings.defaultSuiteName,
            @ViewBuilder content: @escaping (VisibilitySettings) -> Content
        ) {
            _settings = State(initialValue: VisibilityPreviewSettings.make(suiteName: suiteName))
            self.content = content
        }

        var body: some View {
            ThawForm {
                ThawSection {
                    content(settings)
                }
            }
            .frame(width: 680, height: 560)
        }
    }
#endif
