//
//  LanguageRow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The app language picker, with a relaunch button once the language changes.
struct LanguageRow: View {
    @State private var languageOverrideChanged = false

    /// Sentinel for following the system language (no override).
    private static let systemLanguageTag = "system"

    /// The app's own language override, kept under the AppleLanguages key that macOS owns.
    private var currentLanguageOverride: String {
        guard let stored = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first else {
            return Self.systemLanguageTag
        }
        // en-GB selects the en localization at runtime but matches no picker tag.
        return Self.availableLocalization(matching: stored) ?? Self.systemLanguageTag
    }

    /// The bundle localization a stored AppleLanguages value resolves to, or nil when none ships.
    private static func availableLocalization(matching identifier: String) -> String? {
        let localizations = Bundle.main.localizations.filter { $0 != "Base" }
        if localizations.contains(identifier) {
            return identifier
        }
        guard let languageCode = Locale(identifier: identifier).language.languageCode?.identifier else {
            return nil
        }
        // The bare language first (en for en-GB), then a regional variant (pt-BR for pt), as macOS does.
        return localizations.first { $0 == languageCode }
            ?? localizations.first { Locale(identifier: $0).language.languageCode?.identifier == languageCode }
    }

    var body: some View {
        let localizations = Bundle.main.localizations
            .filter { $0 != "Base" }
            .sorted { lhs, rhs in
                displayName(forLanguage: lhs) < displayName(forLanguage: rhs)
            }

        IcePicker(
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
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Relaunch Now") {
                    relaunchApp()
                }
                .buttonStyle(.thawSecondary)
            }
        }
    }

    /// The language's own name for itself (endonym), falling back to the code.
    private func displayName(forLanguage code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.localizedCapitalized ?? code
    }

    private func relaunchApp() {
        // Reopen only after this process exits, or two copies can run.
        // Foundation Process, since a Subprocess child dies with the app.
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$1\"",
            // sh -c takes the first operand as $0, so the path goes second, outside the script text.
            "thaw-relaunch",
            bundlePath,
        ]
        try? process.run()
        NSApp.terminate(nil)
    }
}
