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
    @State private var languageOverrideChanged = false
    @State private var relaunchErrorMessage: String?

    var body: some View {
        ThawForm {
            ThawSection("App") {
                appOptions
            }
            ThawSection("Language and theme") {
                languageRow
                settingsAppearanceOptions
            }
            ThawSection("\(Constants.displayName) icon") {
                thawIconOptions
            }
            ThawSection("Menu bar behavior") {
                AppMenuHidingRow(settings: settings)
                Toggle("Right-click the menu bar for the \(Constants.displayName) menu", isOn: $settings.enableSecondaryContextMenu)
                    .settingsSearchAnchor("advanced.enableSecondaryContextMenu")
                    .annotation(
                        "Right-click an empty area of the menu bar to open a minimal version of \(Constants.displayName)'s menu. If macOS opens its own menu instead, hold Option as you right-click.",
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
        Toggle("Simple Mode", isOn: $settings.simpleMode)
            .settingsSearchAnchor("general.simpleMode")
            .annotation("Shows only the essential settings, with a preview of your sections. Everything else keeps working as you set it.")
        Toggle("Show Dock icon while Settings is open", isOn: $settings.showDockIconWithSettings)
            .settingsSearchAnchor("general.showDockIconWithSettings")
            .annotation("Off, \(Constants.displayName) stays out of the Dock and its recent apps.")
    }

    // MARK: Theme

    @ViewBuilder
    private var settingsAppearanceOptions: some View {
        ThawPillPicker("Theme", selection: $settings.settingsAppearance, values: SettingsAppearance.allCases, title: \.localized)
            .settingsSearchAnchor("general.settingsAppearance")
            .annotation("Applies to Settings and onboarding. Black suits OLED displays.")
        Toggle("Show setting descriptions", isOn: $settings.showSettingDescriptions)
            .settingsSearchAnchor("general.showSettingDescriptions")
            .annotation("Explains what a setting does directly beneath it, like this text.")
    }

    // MARK: Language

    /// Sentinel for following the system language (no override).
    static let systemLanguageTag = "system"

    /// The localizations Thaw ships, without Base.
    private static var availableLanguages: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }
    }

    /// The picker's tag for the app's own AppleLanguages override. Only Thaw's domain counts:
    /// UserDefaults.standard falls back to the system list, whose "en-US" matches no tag.
    private var currentLanguageOverride: String {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        return Self.languageTag(forOverride: domain?["AppleLanguages"] as? [String], available: Self.availableLanguages)
    }

    /// Maps an override such as "en-US" onto a shipped localization, or System Default when none matches.
    static func languageTag(forOverride override: [String]?, available: [String]) -> String {
        guard let preferred = override?.first else { return systemLanguageTag }
        if available.contains(preferred) { return preferred }
        let language = Locale(identifier: preferred).language.languageCode?.identifier
        let match = available
            .filter { Locale(identifier: $0).language.languageCode?.identifier == language }
            .min { $0.count < $1.count }
        return match ?? systemLanguageTag
    }

    @ViewBuilder
    private var languageRow: some View {
        let localizations = Self.availableLanguages
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
        .settingsSearchAnchor("general.appLanguage")
        .annotation("Use \(Constants.displayName) in a different language than the system.")

        if languageOverrideChanged {
            HStack {
                Text("The language change applies after \(Constants.displayName) relaunches.")
                    .font(ThawType.detail)
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
            settings: GeneralSettings()
        )
        .frame(width: 600, height: 500)
    }
#endif
