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
    /// The Layout window's selection, shared with its item list.
    var selection: LayoutSelectionModel?
    /// In the Layout window: a one-line hint, without the controls its toolbar already has.
    var isInLayoutWindow = false

    var body: some View {
        // A header avoids row clipping 20pt below the card's top edge; no rows means no card obscuring the first bar.
        Section {} header: {
            FoldedMenuBar(itemManager: itemManager, arrangement: .spaced, sharedSelection: selection)
                .textCase(nil)
                .font(nil)
                .foregroundStyle(.primary)
                // Grouped Form rows stop growing at a fixed width; size from the scroll view less the Form's 20pt insets, but never set the Form's minimum.
                .containerRelativeFrame(.horizontal) { width, _ in width - 40 }.frame(minWidth: 0, maxWidth: .infinity)
        } footer: {
            if isInLayoutWindow {
                // The window's toolbar has Capture and the notice; one line keeps the bars close to the list.
                Text("Drag to move items. ⌘- or ⇧-click selects several.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                    .help(Self.dragHint)
                    // The same width as the bars, which the form would otherwise centre at its row width.
                    .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in width - 40 }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.base) {
                    Text(Self.dragHint)
                        .font(ThawType.footnote)
                        .foregroundStyle(ThawInk.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ThawSpacing.base)
                    HiddenItemCaptureButton()
                        .settingsSearchAnchor("layout.captureHiddenItems")
                    if showsPopOutButton {
                        popOutButton
                    }
                }
            }
        }

        if !isInLayoutWindow {
            LayoutRefusalNotice()
        }
    }

    private static let dragHint: LocalizedStringKey = "Drag items between sections, or ⌥-arrows to move the selected one. ⌘- or ⇧-click selects several. Hold ⌘ Command to drag in the menu bar."

    /// Not inside the pop-out itself.
    private var showsPopOutButton: Bool {
        !appState.navigationState.isLayoutEditorPresented
    }

    private var popOutButton: some View {
        Button("Pop Out Editor", systemImage: "rectangle.portrait.and.arrow.right") {
            guard let screen = MenuBarLayoutEditorPanel.defaultScreen else { return }
            appState.menuBarManager.layoutEditorPanel.showWindow(on: screen)
        }
        .buttonStyle(.settingsGlass)
        .help("Opens Layout in a window that stays on this menu bar while you work.")
    }
}
