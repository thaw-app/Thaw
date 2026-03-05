//
//  DynamicItemOverrides.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Namespace-only matching overrides for apps that generate dynamic menu bar item titles.
///
/// Apps like Dato or Raycast's calendar plugin change their menu bar item text on
/// every appearance (e.g. "Meeting at 2pm", "Standup at 3pm"). Exact
/// `namespace:title` matching fails for these items because the title is never
/// the same twice. Registering a namespace here opts the app into a fallback
/// that matches by bundle ID alone, so the user's preferred section is
/// preserved regardless of the displayed text.
///
/// ## Adding a new app
/// If users report that a specific app's item always resets to the wrong section
/// after each appearance, add its bundle ID to `knownDynamicNamespaces`.
enum DynamicItemOverrides {
    /// Bundle identifiers of apps known to display dynamic menu bar item titles.
    private static let knownDynamicNamespaces: Set<String> = [
        "com.p0deje.Dato", // Dato — calendar & world clock entries
        "com.raycast.macos", // Raycast — calendar plugin items
        "com.flexibits.fantastical2.mac", // Fantastical — upcoming event label
        "com.flexibits.fantastical2.mac.setapp", // Fantastical (Setapp) — upcoming event label
    ]

    /// Returns `true` if the given namespace belongs to a known dynamic app.
    static func isDynamic(_ namespace: String) -> Bool {
        knownDynamicNamespaces.contains(namespace)
    }
}
