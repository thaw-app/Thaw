//
//  WidgetsSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

/// Small things that show you something at a glance: the widget icon, which
/// lives in the Thaw Widgets module, and the panel behind Thaw's icon, which
/// Thaw runs itself, so the pane stays while the module is off.
struct WidgetsSettingsPane: View {
    @Bindable var settings: AdvancedSettings

    var body: some View {
        ThawForm {
            ThawSection {
                ModuleOpenRow(
                    module: .widgets,
                    title: "Widget icon",
                    detail: "One menu bar icon that combines battery, Wi-Fi and other readings. It runs in Thaw Widgets, a module that comes with \(Constants.displayName)."
                )
            }

            ThawSection("\(Constants.displayName)'s menu and icon") {
                enableControlItemPanel
            }
        }
    }

    /// The status menu as a panel. Alpha: it carries only the commands with a
    /// state worth seeing, so the menu is still the complete list.
    private var enableControlItemPanel: some View {
        Toggle(isOn: $settings.enableControlItemPanel) {
            HStack(spacing: ThawSpacing.compact) {
                Text("Panel instead of the status menu")
                ThawBadge.alpha
            }
        }
        .annotation(
            "Right-click \(Constants.displayName)’s icon to get a panel of controls instead of a menu of text.",
            more: "The panel shows the sections, Zen Mode, the active profile and the Swap Bar. Everything else stays in the menu, which comes back when this is off."
        )
    }
}
