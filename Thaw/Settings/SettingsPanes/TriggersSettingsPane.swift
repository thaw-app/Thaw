//
//  TriggersSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

/// App triggers live in the Thaw Triggers module; this pane opens its
/// window and switches the module on or off.
struct TriggersSettingsPane: View {
    var body: some View {
        ThawForm {
            ThawSection {
                ModuleOpenRow(
                    module: .triggers,
                    title: "When an app runs",
                    detail: "Triggers run in Thaw Triggers, a module that comes with \(Constants.displayName)."
                )
            }
        }
    }
}
