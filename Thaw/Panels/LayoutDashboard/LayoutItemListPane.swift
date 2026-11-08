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
    @Binding var scope: LayoutItemListScope
    /// False while the window is away from the bar it edits: rows still read and select, but nothing moves.
    let isEditable: Bool
    /// Space on a row: bring the item's editor forward.
    let showEditor: () -> Void

    @State private var anchors = LayoutItemListAnchors()
    @State private var pageSize = 10
    @FocusState private var isFocused: Bool

    var body: some View {
        // Reading the item cache here keeps the list current as the bar changes.
        _ = appState.itemManager.itemCache
        let enabled = LayoutItemList.enabledSections(appState: appState)
        let shownScope = scope.section.map(enabled.contains) ?? true ? scope : .all
        let sections = LayoutItemList.sections(appState: appState, query: query, scope: shownScope)
        let rows = sections.flatMap(\.rows)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: ThawSpacing.base) {
                SettingsFilterField(prompt: "Filter items", clearLabel: "Clear filter", text: $query)
                HStack(spacing: ThawSpacing.base) {
                    ThawPillPicker(
                        "Show",
                        selection: Binding(get: { shownScope }, set: { scope = $0 }),
                        options: LayoutItemListScope.offered(enabled: enabled).map { ThawSegment($0, title: $0.title) }
                    )
                    .labelsHidden()
                    Spacer(minLength: 0)
                    SettingsSearchResultCount(Text(LayoutItemListText.count(rows.count, isFiltered: !query.trimmingCharacters(in: .whitespaces).isEmpty)))
                }
            }
            .padding(ThawSpacing.base)
            Divider()
            list(sections: sections, rows: rows)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu bar items")
        .onChange(of: query) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            AccessibilityAnnouncements.post(LayoutItemListText.count(rows.count, isFiltered: true))
        }
    }

    private func list(sections: [LayoutItemListSection], rows: [LayoutItemListRow]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        if let name = section.name {
                            heading(name, isFirst: section.id == sections.first?.id)
                        }
                        ForEach(section.rows) { row in
                            LayoutItemListRowView(
                                row: row,
                                selection: selection,
                                anchors: anchors,
                                isEditable: isEditable,
                                showsSectionBadge: section.name == nil || row.section == .alwaysHidden,
                                onTap: { isFocused = true }
                            )
                            .id(row.id)
                        }
                    }
                }
                .padding(ThawSpacing.base)
            }
            .onGeometryChange(for: Int.self) { geometry in
                max(1, Int(geometry.size.height / LayoutDashboardMetrics.rowHeight) - 1)
            } action: { pageSize = $0 }
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
            .onKeyPress(phases: .down) { press in
                guard let (command, extends) = LayoutItemListCommand.command(
                    for: press.key,
                    characters: press.characters,
                    modifiers: press.modifiers
                ) else { return .ignored }
                return perform(command, extends: extends, rows: rows, proxy: proxy) ? .handled : .ignored
            }
        }
    }

    /// ThawUI's list heading, as search's sections use. Dropping rows on it moves them to that section.
    private func heading(_ name: MenuBarSectionName, isFirst: Bool) -> some View {
        ListSectionHeading(title: name.localizedName, isFirst: isFirst)
            .accessibilityAddTraits(.isHeader)
            .onDrop(of: [LayoutItemListDrop.type], isTargeted: nil) { providers in
                guard isEditable else { return false }
                return LayoutItemListDrop.load(providers) { ids in
                    LayoutItemListDrop.dropOnSection(ids, section: name, selection: selection, appState: appState)
                }
            }
    }

    private func perform(_ command: LayoutItemListCommand, extends: Bool, rows: [LayoutItemListRow], proxy: ScrollViewProxy) -> Bool {
        switch command {
        case let .step(delta):
            go(LayoutItemList.step(from: selection.anchorItemID, by: delta, in: rows), extends: extends, proxy: proxy)
        case let .page(direction):
            go(LayoutItemList.step(from: selection.anchorItemID, by: direction * pageSize, in: rows), extends: extends, proxy: proxy)
        case let .edge(first):
            go(first ? rows.first : rows.last, extends: extends, proxy: proxy)
        case .selectAll:
            selectAll(rows)
        case .showEditor:
            showEditorForSelection()
        case .menu:
            popUpMenu()
        case .undo, .redo, .nudge, .adjacentSection, .sectionNumber:
            change(command)
        }
    }

    private func selectAll(_ rows: [LayoutItemListRow]) -> Bool {
        selection.selectAll(among: Set(rows.map(\.id)))
        return true
    }

    private func showEditorForSelection() -> Bool {
        guard selection.anchorItemID != nil else { return false }
        showEditor()
        return true
    }

    private func popUpMenu() -> Bool {
        guard isEditable, let id = selection.anchorItemID else { return false }
        anchors.popUpMenu(for: id)
        return true
    }

    /// Keys that change the layout. Away from the target they're taken and do nothing, so they
    /// can't reach anything behind the list.
    private func change(_ command: LayoutItemListCommand) -> Bool {
        guard isEditable else { return true }
        let actions = LayoutItemListActions(selection: selection, appState: appState)
        switch command {
        case .undo: appState.layoutUndo.undo()
        case .redo: appState.layoutUndo.redo()
        case let .nudge(left): actions.nudge(left: left)
        case let .adjacentSection(up): actions.moveToAdjacentSection(up: up)
        case let .sectionNumber(number): actions.moveToSection(number: number)
        default: return false
        }
        return true
    }

    private func go(_ row: LayoutItemListRow?, extends: Bool, proxy: ScrollViewProxy) -> Bool {
        guard let row else { return false }
        selection.click(row.id, in: row.section, kind: extends ? .extend : .replace)
        proxy.scrollTo(row.id)
        return true
    }
}

/// One row: checkbox, picture, name, owner and, where the heading doesn't say it, the section.
/// Its own view, so a selection change redraws the rows and not the whole list.
private struct LayoutItemListRowView: View {
    @Environment(AppState.self) private var appState
    let row: LayoutItemListRow
    let selection: LayoutSelectionModel
    let anchors: LayoutItemListAnchors
    let isEditable: Bool
    let showsSectionBadge: Bool
    let onTap: () -> Void

    @State private var isDropTarget = false

    var body: some View {
        let isSelected = selection.contains(row.id)
        HStack(spacing: PanelRow.iconSpacing) {
            visibilityCheckbox
            MenuBarItemRowImage(
                item: row.item,
                columnWidth: LayoutDashboardMetrics.pictureColumnWidth,
                glyphHeight: LayoutDashboardMetrics.pictureHeight
            )
            // ThawType has no step between body and display; Title 3 still follows Larger Text.
            Text(row.name)
                .font(.title3)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let owner = row.ownerName {
                Text(verbatim: owner)
                    .font(ThawType.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if showsSectionBadge, row.section != .visible {
                ThawBadge(LayoutItemListText.sectionBadge(row.section))
            }
        }
        .padding(.horizontal, PanelRow.inset)
        .frame(minHeight: LayoutDashboardMetrics.rowHeight)
        .modifier(SearchRowBackground(selected: isSelected))
        .overlay(alignment: .top) {
            // Where a drop lands: just above this row.
            if isDropTarget, isEditable {
                Capsule().fill(Color.accentColor).frame(height: 2)
            }
        }
        .background {
            LayoutItemListMenuHost(rowID: row.id, anchors: anchors) { isEditable ? menu() : nil }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
            let flags = NSEvent.modifierFlags
            let kind = LayoutSelection.Click(command: flags.contains(.command), shift: flags.contains(.shift))
            selection.click(row.id, in: row.section, kind: kind)
        }
        .onDrag {
            LayoutItemListDrop.provider(for: row.id, in: row.section, selection: selection)
        } preview: {
            LayoutItemListDragPreview(name: row.name, count: selection.contains(row.id) ? selection.count : 1)
        }
        .onDrop(of: [LayoutItemListDrop.type], isTargeted: $isDropTarget) { providers in
            guard isEditable else { return false }
            return LayoutItemListDrop.load(providers) { ids in
                LayoutItemListDrop.drop(ids, before: row, selection: selection, appState: appState)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(Text(row.section.localizedName))
    }

    /// Checked is Visible; unchecked is Hidden or Always Hidden, which the badge tells apart.
    /// Checking an Always Hidden item makes it Visible, and unchecking it again makes it Hidden.
    /// One of several selected rows applies to them all.
    private var visibilityCheckbox: some View {
        let lock = LayoutItemVisibility.lockReason(
            for: row.item,
            in: row.section,
            experimentalSystemItemHiding: appState.settings.layout.enableExperimentalSystemItemHiding
        )
        let isShown = LayoutItemVisibility.isShown(row.section)
        return Toggle(isOn: Binding(get: { isShown }, set: { shown in
            LayoutItemVisibility.setShown(shown, rowID: row.id, in: row.section, selection: selection, appState: appState)
        })) {
            // The style draws any label beside the box; the name is already in the row.
            EmptyView()
        }
        .toggleStyle(.thawCheckbox)
        .controlSize(.large)
        .accessibilityLabel(Text("Show \(row.name) in the menu bar"))
        .fixedSize()
        .disabled(lock != nil || !isEditable)
        // On a wrapper, so a disabled checkbox still explains itself.
        .frame(width: LayoutDashboardMetrics.checkboxColumnWidth)
        .contentShape(Rectangle())
        .help(lock ?? (isShown ? String(localized: "Shown in the menu bar") : row.section.localizedName))
    }

    /// The bars' menus: the selection's moves for one of several selected rows, otherwise the item's own.
    private func menu() -> NSMenu? {
        if selection.count > 1, selection.contains(row.id) {
            return LayoutSelectionActions(selection: selection, appState: appState).menu()
        }
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        return LayoutBarItemMenu.menu(
            subject: .item(row.item),
            section: row.section,
            orderedItems: LayoutDisplayedItems.items(in: row.section, appState: appState, runningApplications: running),
            appState: appState
        )
    }
}

/// What follows the pointer while rows are dragged.
private struct LayoutItemListDragPreview: View {
    let name: String
    let count: Int

    var body: some View {
        Text(count > 1 ? LayoutItemListText.dragged(count) : name)
            .font(ThawType.label)
            .padding(.horizontal, ThawSpacing.inset)
            .padding(.vertical, ThawSpacing.tight)
            .background(.regularMaterial, in: Capsule())
    }
}

/// The list's own words, kept apart so tests can read them.
enum LayoutItemListText {
    static func count(_ count: Int, isFiltered: Bool) -> String {
        isFiltered
            ? inflected(AttributedString(localized: "^[\(count) match](inflect: true)", comment: "How many Layout list rows match the filter"))
            : inflected(AttributedString(localized: "^[\(count) item](inflect: true)", comment: "How many items the Layout list shows"))
    }

    static func sectionBadge(_ section: MenuBarSectionName) -> LocalizedStringResource {
        switch section {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }

    static func dragged(_ count: Int) -> String {
        inflected(AttributedString(localized: "^[\(count) item](inflect: true)", comment: "Label on several Layout list rows being dragged"))
    }

    private static func inflected(_ text: AttributedString) -> String {
        String(text.characters)
    }
}
