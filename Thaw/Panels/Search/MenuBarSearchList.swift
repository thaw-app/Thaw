//
//  MenuBarSearchList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// The results in ThawUI's launcher list. The keys stay with the panel; a
/// click selects, a double click opens.
struct MenuBarSearchList: View {
    @Environment(\.menuBarSearchPanel) private var panel
    @Environment(MenuBarSearchModel.self) private var model

    var body: some View {
        let results = model.results
        LauncherResultList(
            rows: results,
            selection: model.selectedIndex ?? -1,
            section: \.section,
            select: { model.selection = results[$0].id },
            activate: { panel?.activate(results[$0].item) },
            rowContent: { result, selected in
                MenuBarSearchRow(result: result, selected: selected)
            }
        )
    }
}

/// One item as a Floe palette row: picture, name, owning app. A rename puts
/// a field in the name's place.
private struct MenuBarSearchRow: View {
    @Environment(MenuBarSearchModel.self) private var model
    /// Grows with Larger Text, as the row's text does.
    @ScaledMetric(relativeTo: .body) private var rowHeight = PanelRow.height

    let result: MenuBarSearchResult
    let selected: Bool

    var body: some View {
        let item = result.item
        let name = MenuBarItemDisplayName.displayName(for: item)
        let isRenaming = model.renameSession?.targets(item) == true
        // PaletteRow's measures, with an image slot that widens for an item
        // as wide as the clock instead of squeezing it into a square.
        HStack(spacing: PanelRow.iconSpacing) {
            MenuBarItemRowImage(item: item)
            if isRenaming {
                MenuBarItemRenameField(item: item)
                    .font(ThawType.body)
            } else {
                Text(name)
                    .font(ThawType.body)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !isRenaming, let ownerName = result.ownerName, ownerName != name {
                Text(verbatim: ownerName)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, PanelRow.inset)
        .frame(minHeight: rowHeight)
        .modifier(SearchRowBackground(selected: selected))
        .accessibilityElement(children: isRenaming ? .contain : .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Rename field

/// The field a row shows in place of its name while renaming: Return saves, Escape cancels.
private struct MenuBarItemRenameField: View {
    @Environment(\.menuBarSearchPanel) private var panel
    @Environment(MenuBarSearchModel.self) private var model
    @FocusState private var isEditing: Bool

    let item: MenuBarItem

    var body: some View {
        TextField(item.autoDetectedName, text: renameDraft)
            .textFieldStyle(.plain)
            .foregroundStyle(.primary)
            .focused($isEditing)
            .textContentType(.none)
            .autocorrectionDisabled(true)
            .onSubmit {
                panel?.commitRename()
            }
            .onExitCommand {
                model.renameSession = nil
            }
            .onAppear {
                isEditing = true
            }
            .onDisappear {
                isEditing = false
            }
    }

    /// Binding into the draft of the active rename. Writes that arrive after
    /// the session has ended are dropped.
    private var renameDraft: Binding<String> {
        Binding(
            get: { model.renameSession?.draft ?? "" },
            set: { model.renameSession?.draft = $0 }
        )
    }
}
