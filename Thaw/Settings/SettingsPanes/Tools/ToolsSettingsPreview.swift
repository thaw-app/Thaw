//
//  ToolsSettingsPreview.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

#if DEBUG
    import SwiftUI
    import ThawUI

    /// Only for the canvas: redirects process-wide defaults before creating the preview's model.
    /// No settings setup runs and the log rotation policy is never sent to the real logger.
    @MainActor
    enum ToolsPreviewSettings {
        static let defaultSuiteName = "com.stonerl.Thaw.tools-previews"

        static func make(suiteName domain: String = defaultSuiteName) -> ToolsSettings {
            guard let store = UserDefaults(suiteName: domain) else {
                preconditionFailure("Could not create the Tools preview preferences")
            }
            store.removePersistentDomain(forName: domain)
            Defaults.store = store
            let settings = ToolsSettings()
            // A changed value would otherwise prune the real log folder.
            settings.sendRotationPolicy = { _ in /* Preview only. */ }
            return settings
        }
    }

    /// Gives the Tools rows interactive state and the same form layout they use in Settings.
    struct ToolsSettingsPreview<Content: View>: View {
        @State private var settings: ToolsSettings
        private let content: (ToolsSettings) -> Content

        init(
            suiteName: String = ToolsPreviewSettings.defaultSuiteName,
            @ViewBuilder content: @escaping (ToolsSettings) -> Content
        ) {
            _settings = State(initialValue: ToolsPreviewSettings.make(suiteName: suiteName))
            self.content = content
        }

        var body: some View {
            ThawForm {
                ThawSection {
                    content(settings)
                }
            }
            .frame(width: 680, height: 360)
        }
    }

    extension NativeVisibilityRecoveryModel {
        /// Sample records only. Nothing here reads or writes real visibility settings,
        /// and the model never reports another app as running.
        static func preview(unreadableRecord: Bool = false) -> NativeVisibilityRecoveryModel {
            struct UnreadableRecord: Error {}
            return NativeVisibilityRecoveryModel(environment: Environment(
                conflictingApplications: { [] },
                disableNativeHiding: { /* Preview only. */ },
                requestAccess: { true },
                inspect: {
                    if unreadableRecord {
                        throw UnreadableRecord()
                    }
                    return (
                        disabled: ["com.example.Clock", "com.example.Notes", "com.example.Weather"],
                        recorded: ["com.example.Clock"]
                    )
                },
                restore: { _ in 0 },
                displayName: { $0.split(separator: ".").last.map(String.init) ?? $0 },
                isUnreadableRecord: { $0 is UnreadableRecord },
                setAsideUnreadableRecords: { [] }
            ))
        }
    }
#endif
