//
//  ScriptsSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

/// Scripts that run before and after a profile switch. They live in the
/// Scripts module; this pane switches it on or off and opens it.
struct ScriptsSettingsPane: View {
    var body: some View {
        ThawForm {
            scriptsSection
        }
    }

    private var scriptsSection: some View {
        ThawSection {
            ModuleOpenRow(
                module: .scripts,
                title: "Before and after a profile switches",
                detail: "Scripts run in the Scripts module, which comes with \(Constants.displayName)."
            )
        }
    }
}
