//
//  LayoutItemListPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

/// The Layout window's item list. It selects through the same model as the bars, so a row
/// and its glyph highlight together, and its menus and moves are the bars' own.
struct LayoutItemListPane: View {
    @Environment(AppState.self) private var appState
    let selection: LayoutSelectionModel
    @Binding var query: String

    @State private var anchors = LayoutItemListAnchors()
    @FocusState private var isFocused: Bool

    var body: some View {
        // Reading the item cache here keeps the list current as the bar changes.
        _ = appState.itemManager.itemCache
        let sections = LayoutItemList.sections(appState: appState, query: query)
        let rows = sections.flatMap(\.rows)
        return VStack(spacing: 0) {
            SettingsFilterField(prompt: "Filter items", clearLabel: "Clear filter", text: $query)
                .padding(ThawSpacing.base)
            Divider()
            list(sections: sections, rows: rows)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu bar items")
    }

    private func list(sections: [LayoutItemListSection], rows: [LayoutItemListRow]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        heading(section.name, isFirst: section.id == sections.first?.id)
                        ForEach(section.rows) { row in
                            rowView(row, in: section.name)
                                .id(row.id)
                        }
                    }
                }
                .padding(ThawSpacing.base)
            }
            .overlay {
                if sections.isEmpty {
                    ThawEmptyState(
                        systemImage: "magnifyingglass",
                        title: query.isEmpty ? "No items to list" : "No items match",
                        caption: query.isEmpty ? nil : "Try part of the item's name or the app that owns it."
                    )
                }
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard let next = LayoutItemList.step(
                    from: selection.anchorItemID,
                    by: press.key == .downArrow ? 1 : -1,
                    in: rows
                ) else { return .ignored }
                select(next, in: rows, sections: sections, kind: press.modifiers.contains(.shift) ? .extend : .replace)
                proxy.scrollTo(next.id)
                return .handled
            }
            .onKeyPress(.return) {
                guard let id = selection.anchorItemID else { return .ignored }
                anchors.popUpMenu(for: id)
                return .handled
            }
            .onKeyPress(characters: ["a"]) { press in
                guard press.modifiers == .command else { return .ignored }
                selection.selectAll()
                return .handled
            }
        }
    }

    /// ThawUI's list heading, as search's sections use.
    private func heading(_ name: MenuBarSectionName, isFirst: Bool) -> some View {
        ListSectionHeading(title: name.localizedName, isFirst: isFirst)
            .accessibilityAddTraits(.isHeader)
    }

    private func rowView(_ row: LayoutItemListRow, in section: MenuBarSectionName) -> some View {
        let isSelected = selection.contains(row.id)
        return HStack(spacing: PanelRow.iconSpacing) {
            visibilityCheckbox(row, in: section)
            MenuBarItemRowImage(item: row.item, columnWidth: LayoutDashboardMetrics.pictureColumnWidth)
            Text(row.name)
                .font(ThawType.label)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let owner = row.ownerName {
                Text(verbatim: owner)
                    .font(ThawType.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, PanelRow.inset)
        .frame(minHeight: LayoutDashboardMetrics.rowHeight)
        .modifier(SearchRowBackground(selected: isSelected))
        .background {
            LayoutItemListMenuHost(rowID: row.id, anchors: anchors) { menu(for: row, in: section) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
            let flags = NSEvent.modifierFlags
            let kind = LayoutSelection.Click(command: flags.contains(.command), shift: flags.contains(.shift))
            selection.click(row.id, in: section, kind: kind)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Checked is Visible. One of several selected rows applies to them all.
    private func visibilityCheckbox(_ row: LayoutItemListRow, in section: MenuBarSectionName) -> some View {
        let lock = LayoutItemVisibility.lockReason(
            for: row.item,
            in: section,
            experimentalSystemItemHiding: appState.settings.layout.enableExperimentalSystemItemHiding
        )
        let isShown = LayoutItemVisibility.isShown(section)
        return Toggle(isOn: Binding(get: { isShown }, set: { shown in
            LayoutItemVisibility.setShown(shown, rowID: row.id, in: section, selection: selection, appState: appState)
        })) {
            // The style draws any label beside the box; the name is already in the row.
            EmptyView()
        }
        .toggleStyle(.thawCheckbox)
        .controlSize(.large)
        .accessibilityLabel(Text("Show \(row.name) in the menu bar"))
        .fixedSize()
        .disabled(lock != nil)
        // On a wrapper, so a disabled checkbox still explains itself.
        .frame(width: LayoutDashboardMetrics.checkboxColumnWidth)
        .contentShape(Rectangle())
        .help(lock ?? (isShown ? String(localized: "Shown in the menu bar") : String(localized: "Hidden")))
    }

    private func select(_ row: LayoutItemListRow, in _: [LayoutItemListRow], sections: [LayoutItemListSection], kind: LayoutSelection.Click) {
        guard let section = sections.first(where: { $0.rows.contains { $0.id == row.id } })?.name else { return }
        selection.click(row.id, in: section, kind: kind)
    }

    /// The bars' menus: the selection's moves for one of several selected rows, otherwise the item's own.
    private func menu(for row: LayoutItemListRow, in section: MenuBarSectionName) -> NSMenu? {
        if selection.count > 1, selection.contains(row.id) {
            return LayoutSelectionActions(selection: selection, appState: appState).menu()
        }
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        return LayoutBarItemMenu.menu(
            subject: .item(row.item),
            section: section,
            orderedItems: LayoutDisplayedItems.items(in: section, appState: appState, runningApplications: running),
            appState: appState
        )
    }
}
