//
//  GeneralSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

struct GeneralSettingsPane: View {
    @Bindable var settings: GeneralSettings
    @Bindable var advancedSettings: AdvancedSettings
    @State private var languageOverrideChanged = false
    @State private var relaunchErrorMessage: String?

    var body: some View {
        ThawForm {
            ThawSection("App") {
                appOptions
            }
            ThawSection("\(Constants.displayName) icon") {
                thawIconOptions
            }
            ThawSection("Menu bar behavior") {
                Toggle("Hide app menus when showing menu bar items", isOn: $advancedSettings.hideApplicationMenus)
                    .annotation(
                        "Make more room in the menu bar by hiding the current app menus if needed.",
                        more: "macOS requires \(Constants.displayName) to make itself visible in the Dock while this setting is in effect."
                    )
                Toggle("Right-click the menu bar for the \(Constants.displayName) menu", isOn: $advancedSettings.enableSecondaryContextMenu)
                    .annotation(
                        "Right-click an empty area of the menu bar to open a minimal version of \(Constants.displayName)'s menu.",
                        more: "Turn this off if another app also uses right-clicks on the menu bar."
                    )
            }
        }
        .errorAlert("Couldn’t relaunch \(Constants.displayName)", message: $relaunchErrorMessage)
    }

    // MARK: App Options

    @ViewBuilder
    private var appOptions: some View {
        LaunchAtLoginRow()
        languageRow
        Toggle("Simple Mode", isOn: $settings.simpleMode)
            .annotation("Shows only the essential settings. All features keep working and keep their configuration.")
        Toggle("Show setting descriptions", isOn: $settings.showSettingDescriptions)
            .annotation("Explains what a setting does directly beneath it, like this text.")
    }

    // MARK: Language

    /// Sentinel for following the system language (no override).
    private static let systemLanguageTag = "system"

    /// The app's per-app language override, via the standard AppleLanguages
    /// mechanism. Not a Defaults.Key, the key name is owned by macOS.
    private var currentLanguageOverride: String {
        (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
            ?? Self.systemLanguageTag
    }

    @ViewBuilder
    private var languageRow: some View {
        let localizations = Bundle.main.localizations
            .filter { $0 != "Base" }
            .sorted { lhs, rhs in
                displayName(forLanguage: lhs) < displayName(forLanguage: rhs)
            }

        ThawPicker(
            "App language",
            selection: Binding(
                get: { currentLanguageOverride },
                set: { newValue in
                    if newValue == Self.systemLanguageTag {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    }
                    languageOverrideChanged = true
                }
            )
        ) {
            Text("System Default").tag(Self.systemLanguageTag)
            ForEach(localizations, id: \.self) { code in
                Text(displayName(forLanguage: code)).tag(code)
            }
        }
        .annotation("Use \(Constants.displayName) in a different language than the system. Takes effect after a relaunch.")

        if languageOverrideChanged {
            HStack {
                Text("The language change applies after \(Constants.displayName) relaunches.")
                    .font(.callout)
                    .foregroundStyle(ThawInk.supporting)
                Spacer()
                Button("Relaunch Now") {
                    relaunchApp()
                }
                .buttonStyle(.settingsGlass)
            }
        }
    }

    /// The language's own name for itself (endonym), falling back to the code.
    private func displayName(forLanguage code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.localizedCapitalized ?? code
    }

    private func relaunchApp() {
        do {
            try AppRelauncher.relaunch()
        } catch {
            relaunchErrorMessage = error.localizedDescription
        }
    }

    // MARK: Thaw Icon Options

    private var thawIconOptions: some View {
        ShowThawIconRow(settings: settings)
    }
}

// #Preview bodies are compiled in release too, so the preview is guarded.
#if DEBUG
    #Preview {
        GeneralSettingsPane(
            settings: GeneralSettings(),
            advancedSettings: AdvancedSettings()
        )
        .frame(width: 600, height: 500)
    }
#endif
