//
//  TriggersSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

/// Everything that shows a hidden item on its own. Icon changes are watched by Thaw, which captures
/// the icons, and only while the Triggers module is on.
struct TriggersSettingsPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ThawForm {
            ThawSection {
                ModuleOpenRow(
                    module: .triggers,
                    title: "When an app runs",
                    detail: "Triggers run in the Triggers module, which comes with \(Constants.displayName)."
                )
            }
            if appState.moduleHost.isEnabled(.triggers) {
                ThawSection("When an icon changes") {
                    AlertRevealItemList()
                }
            }
        }
    }
}
