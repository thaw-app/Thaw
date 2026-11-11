//
//  MenuBarSearchFooter.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// The shortcut bar under the list, when it is on, and the refusal notice
/// either way: a refused move from search has nowhere else to show.
struct MenuBarSearchFooter: View {
    @Environment(AppState.self) private var appState
    @Environment(MenuBarSearchModel.self) private var model
    @AppStorage(Defaults.Key.rememberSearchQuery.rawValue) private var rememberSearchQuery = Defaults.DefaultValue.rememberSearchQuery
    @AppStorage(Defaults.Key.showSearchShortcutBar.rawValue) private var showsShortcutBar = Defaults.DefaultValue.showSearchShortcutBar

    let panel: MenuBarSearchPanel

    var body: some View {
        VStack(spacing: 0) {
            // Shows only while a move from search was refused.
            LayoutRefusalNotice()
                .padding(.horizontal, ThawSpacing.inset)
            if showsShortcutBar {
                PanelBottomBar {
                    actionRow
                }
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        Button {
            panel.close()
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        } label: {
            Image(systemName: "gearshape")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(ThawSpacing.hairline)
        }
        .help("Open Settings")
        .accessibilityLabel("Open Settings")

        Toggle("Remember last search", isOn: $rememberSearchQuery)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()

        Spacer(minLength: 0)

        if let item = model.selectedResult?.item {
            if model.renameSession == nil {
                browsingButtons(for: item)
            } else {
                renamingButtons
            }
        }
    }

    @ViewBuilder
    private func browsingButtons(for item: MenuBarItem) -> some View {
        // Tab only means something while the list has sections.
        if model.results.first?.section != nil {
            ShortcutHintButton(title: String(localized: "Next Section")) {
                model.moveSelection(toSectionFromCurrentBy: 1)
            } hint: {
                KeyCapView(text: "⇥")
            }
            .help("Tab moves to the next section, Shift-Tab to the previous one.")
        }
        ShortcutHintButton(title: String(localized: "Rename…")) {
            panel.beginRenamingSelection()
        } hint: {
            KeyCapView(text: "⌘")
            KeyCapView(text: "E")
        }
        ShortcutHintButton(title: String(localized: "Actions…")) {
            panel.presentItemActions()
        } hint: {
            KeyCapView(text: "⌘")
            KeyCapView(text: "K")
        }
        .help("Rename, group or move the item. ⌘1, ⌘2 and ⌘3 move it to Visible, Hidden or Always Hidden.")
        // The actions menu hangs off this button, so an AppKit anchor sits
        // behind it and takes its frame.
        .background { ItemActionsMenuAnchor(panel: panel) }
        ShortcutHintButton(
            title: isEffectivelyVisible(item)
                ? String(localized: "Click Item")
                : String(localized: "Show Item")
        ) {
            panel.activate(item)
        } hint: {
            KeyCapView(systemImage: "return")
        }
    }

    @ViewBuilder
    private var renamingButtons: some View {
        ShortcutHintButton(title: String(localized: "Cancel")) {
            model.renameSession = nil
        } hint: {
            KeyCapView(text: "⎋", font: ThawType.detail)
        }
        .keyboardShortcut(.cancelAction)
        ShortcutHintButton(title: String(localized: "Rename")) {
            panel.commitRename()
        } hint: {
            KeyCapView(systemImage: "return")
        }
        .keyboardShortcut(.defaultAction)
    }

    /// "Click Item" or "Show Item", mirroring MenuBarItemManager.clickConcealedItem.
    /// The window list can't tell: macOS 27 items have synthetic window IDs.
    private func isEffectivelyVisible(_ item: MenuBarItem) -> Bool {
        let controller = appState.menuBarManager.sectionController
        guard controller.section(for: item) == .visible else {
            return false
        }
        // A visible-authored item can still be concealed by the automatic
        // overflow assertion, which the menu bar overlay also drives.
        return !controller.isEffectivelyConcealed(item)
    }
}

/// The AppKit view the actions menu pops up from, behind the Actions button or
/// under the field. A view needs no frame conversion, which can misplace the menu.
struct ItemActionsMenuAnchor: NSViewRepresentable {
    let panel: MenuBarSearchPanel

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        panel.itemActionsAnchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        // Re-registered on each update: the bar rebuilds this view as the
        // selection comes and goes.
        panel.itemActionsAnchor = nsView
    }
}
