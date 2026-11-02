//
//  MenuBarModuleDirectory.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The Apple-owned menu extras the OS lets an app switch off, looked up by the
/// identifier Thaw stores them under.
///
/// Switched-off extras keep their assignment but have no live element, so the
/// layout editor needs the title to show a placeholder instead of dropping it.
public protocol MenuBarModuleDirectory: Sendable {
    /// The menu extra title identifier names, or nil when it names something
    /// other than a governable Apple extra.
    func governableMenuExtraTitle(forItemIdentifier identifier: String) -> String?
}
