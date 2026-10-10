//
//  ScriptsSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Placeholder for the upcoming script-driven bar modules surface.
///
/// The pane exists so the destination is discoverable (sidebar and search)
/// before the feature lands; it holds no settings yet.
struct ScriptsSettingsPane: View {
    var body: some View {
        ThawEmptyState(
            systemImage: "curlybraces",
            title: "In development",
            caption: "Script-driven bar modules are not built yet. There is nothing to configure here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
