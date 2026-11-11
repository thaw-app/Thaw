//
//  LayoutSectionOptions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

struct LayoutSectionOptions: View {
    @Bindable var settings: LayoutSettings
    let isHidingUnavailable: Bool

    var body: some View {
        ThawSection {
            Text("Sections")
        } content: {
            // Arrangement leads because it gates the section controls.
            ThawPillPicker(
                "Item arrangement",
                selection: $settings.menuBarArrangementMode,
                values: MenuBarArrangementMode.allCases,
                title: \.localized
            )
            .settingsSearchAnchor("advanced.menuBarArrangementMode")
            .annotation(settings.menuBarArrangementMode.explanation)

            Toggle(
                "Always Hidden",
                isOn: $settings.enableAlwaysHiddenSection
            )
            .settingsSearchAnchor("advanced.enableAlwaysHiddenSection")
            .annotation("Adds a third section for items you rarely need. They stay out of sight when you show your Hidden items.")
            ThawPicker("Section divider style", selection: $settings.sectionDividerStyle) {
                ForEach(SectionDividerStyle.allCases) { style in
                    Text(style.localized).tag(style)
                }
            }
            .settingsSearchAnchor("advanced.sectionDividerStyle")
            if settings.sectionDividerStyle == .custom {
                CustomSectionDividerControls(settings: settings)
            }
            Toggle("Show every section while dragging", isOn: $settings.showAllSectionsOnUserDrag)
                .settingsSearchAnchor("layout.showAllSectionsOnUserDrag")
                .annotation("While you ⌘-drag an item in the menu bar, hidden sections open so you can drop it into any of them.")
        } footer: {
            if isHidingUnavailable {
                SettingsWarningPill(
                    title: "Hiding unavailable",
                    message: "This version of macOS doesn't let \(Constants.displayName) hide items. You can still reorder them in the bars above."
                )
            }
        }
    }
}
