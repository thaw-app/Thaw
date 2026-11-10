//
//  LayoutBarsSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

struct LayoutBarsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager

    var body: some View {
        // A header avoids row clipping 20pt below the card's top edge; no rows means no card obscuring the first bar.
        Section {
            EmptyView()
        } header: {
            FoldedMenuBar(itemManager: itemManager, arrangement: .spaced)
                .textCase(nil)
                .font(nil)
                .foregroundStyle(.primary)
                // Grouped Form rows stop growing at a fixed width; size from the scroll view less the Form's 20pt insets, but never set the Form's minimum.
                .containerRelativeFrame(.horizontal) { width, _ in width - 40 }.frame(minWidth: 0, maxWidth: .infinity)
        } footer: {
            HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.base) {
                Text("Drag items between sections. Hold ⌘ Command to drag in the menu bar.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ThawSpacing.base)
                HiddenItemCaptureButton()
                if showsPopOutButton {
                    popOutButton
                }
            }
        }

        layoutRefusalNotice
    }

    /// Not inside the pop-out itself.
    private var showsPopOutButton: Bool {
        !appState.navigationState.isLayoutEditorPresented
    }

    private var popOutButton: some View {
        Button("Pop Out Editor", systemImage: "rectangle.portrait.and.arrow.right") {
            guard let screen = MenuBarLayoutEditorPanel.defaultScreen else { return }
            let menuBarManager = appState.menuBarManager
            menuBarManager.layoutEditorPanel.show(on: screen, usesReorderEditor: true) {
                menuBarManager.dismissLayoutEditorPanel()
            }
        }
        .buttonStyle(.settingsGlass)
        .help("Opens the reorder editor in its own window.")
    }

    /// A refused group move snaps back with no other explanation, so the
    /// reason appears here rather than in a modal that would cover the bars.
    @ViewBuilder
    private var layoutRefusalNotice: some View {
        if let refusal = appState.layoutFeedback.refusal {
            VStack(alignment: .leading, spacing: ThawSpacing.inset) {
                Text("macOS 27 does not let \(Constants.displayName) hide some system items.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsWarningPill(
                    title: LocalizedStringResource(String.LocalizationValue(refusal.title)),
                    message: LocalizedStringResource(String.LocalizationValue(refusal.message)),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    actionTitle: "Dismiss"
                ) {
                    appState.layoutFeedback.clear()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.fade(reduceMotion: reduceMotion))
        }
    }
}
