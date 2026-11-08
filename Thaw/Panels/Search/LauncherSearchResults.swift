//
//  LauncherSearchResults.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// Compact search's results in ThawUI's launcher list, Floe's: palette rows
/// under section headings, with the highlight kept in view.
///
/// The search model lists headings as rows of their own; the launcher list
/// wants a section name on each row instead, and a position for the
/// highlight. The keys stay with the panel, which moves model.selection.
struct LauncherSearchResults: View {
    @Environment(MenuBarSearchModel.self) private var model

    /// One selectable row and the heading it sits under.
    struct Row: Identifiable {
        let item: SectionedListItem<MenuBarSearchModel.ItemID, MenuBarSearchListContent>
        let section: String?

        var id: MenuBarSearchModel.ItemID {
            item.id
        }
    }

    /// The model's rows with their headings folded into the rows under them.
    static func rows(from items: [SectionedListItem<MenuBarSearchModel.ItemID, MenuBarSearchListContent>]) -> [Row] {
        var section: String?
        var rows = [Row]()
        for item in items {
            guard !item.isSelectable else {
                rows.append(Row(item: item, section: section))
                continue
            }
            switch item.content {
            case let .header(name): section = name.localizedName
            case let .label(text): section = text
            default: break
            }
        }
        return rows
    }

    var body: some View {
        let rows = Self.rows(from: model.displayedItems)
        LauncherResultList(
            rows: rows,
            selection: rows.firstIndex { $0.id == model.selection } ?? -1,
            section: \.section,
            select: { model.selection = rows[$0].id },
            activate: { rows[$0].item.action?() },
            rowContent: { row, selected in
                LauncherItemRow(content: row.item.content, selected: selected)
            }
        )
    }
}

/// An item drawn as every Floe result is: its app's icon, its name, and the
/// app that owns it at the right.
private struct LauncherItemRow: View {
    @Environment(MenuBarSearchModel.self) private var model

    let content: MenuBarSearchListContent
    let selected: Bool

    var body: some View {
        switch content {
        case let .launcherItem(item, ownerName), let .assistedItem(item, ownerName):
            itemRow(item, ownerName: ownerName)
        default:
            content
        }
    }

    @ViewBuilder
    private func itemRow(_ item: MenuBarItem, ownerName: String?) -> some View {
        let name = MenuBarItemDisplayName.displayName(for: item)
        if model.renameSession?.targets(item) == true {
            // The same measures as PaletteRow, which has no field of its own.
            HStack(spacing: PanelRow.iconSpacing) {
                MenuBarItemSourceIcon(item: item, length: PanelRow.iconBox)
                MenuBarItemRenameField(item: item)
                    .font(ThawType.body)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PanelRow.inset)
            .frame(minHeight: PanelRow.height)
            .modifier(SearchRowBackground(selected: selected))
        } else {
            PaletteRow(title: name, selected: selected) {
                MenuBarItemSourceIcon(item: item, length: PanelRow.iconBox)
            } trailing: {
                if let ownerName, ownerName != name {
                    Text(verbatim: ownerName)
                        .font(ThawType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        }
    }
}
