//
//  MenuBarItemTag+WidgetMigration.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension MenuBarItemTag {
    /// The fixed accessibility identifier of Thaw's widget, which is also its autosave name.
    public static let thawWidgetIdentifier = "Thaw.Widget.Preview"

    /// Thaw's widget used to be named by its label, which carries the live readings, so every
    /// saved entry under a "Thaw widget…" label now means the widget's fixed identifier.
    static func migratedWidgetTitle(bundleID: String, title: String) -> String? {
        guard bundleID == "com.stonerl.Thaw" || bundleID == "com.stonerl.Thaw.debug", title.hasPrefix("Thaw widget")
        else { return nil }
        return thawWidgetIdentifier
    }
}
