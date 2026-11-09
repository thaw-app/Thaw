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
    /// Escape with an empty filter.
    var close: () -> Void = {}
    /// Gets the view behind the filter field, so the window can tell when the filter is being typed in.
    var filterAnchor: (NSView) -> Void = { _ in }

    @State private var anchors = LayoutItemListAnchors()
    /// The row the list's keys last landed on, and the selection's change count then.
    /// Lets Shift+arrow keep growing the range; see LayoutItemList.stepStart.
    @State private var keyboardHead: (id: String, atChangeCount: Int)?
    /// Bumped when an item changes section, which the item cache doesn't always reflect.
    @State private var membershipRevision = 0
    @State private var pageSize = 10
    @State private var motion = LayoutListMotion()
    @FocusState private var isFocused: Bool

    var body: some View {
        // Reading the item cache and the names' revision keeps the list current as the bar changes or an item is renamed.
        _ = appState.itemManager.itemCache
        _ = MenuBarItemCustomNamesRevision.shared.value
        _ = membershipRevision
        let enabled = LayoutItemList.enabledSections(appState: appState)
        let shownScope = scope.section.map(enabled.contains) ?? true ? scope : .all
        let sections = LayoutItemList.sections(appState: appState, query: query, scope: shownScope)
        let rows = sections.flatMap(\.rows)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: ThawSpacing.base) {
                SettingsFilterField(prompt: "Filter items", clearLabel: "Clear filter", text: $query)
                    .background(LayoutFilterAnchor(register: filterAnchor))
                HStack(spacing: ThawSpacing.base) {
                    ThawPillPicker(
                        "Show",
                        selection: Binding(get: { shownScope }, set: { scope = $0 }),
                        options: LayoutItemListScope.offered(enabled: enabled).map { ThawSegment($0, title: $0.title) }
                    )
                    .labelsHidden()
                    Spacer(minLength: 0)
                    SettingsSearchResultCount(Text(LayoutItemListText.count(rows.count, isFiltered: !query.trimmingCharacters(in: .whitespaces).isEmpty)))
                        .rollingNumber(rows.count)
                }
            }
            .padding(ThawSpacing.base)
            Divider()
            list(sections: sections, rows: rows)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu bar items")
        // The bars rebuild on the same signal; the next turn reads the committed assignment.
        .onReceive(appState.menuBarManager.sectionLayoutChanges.receive(on: RunLoop.main)) { _ in
            membershipRevision &+= 1
            motion.revealPending()
        }
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
                            LayoutItemListHeading(
                                name: name,
                                isFirst: section.id == sections.first?.id,
                                isEditable: isEditable,
                                selection: selection,
                                motion: motion
                            )
                        }
                        ForEach(section.rows) { row in
                            rowView(row, in: section, rows: rows)
                        }
                    }
                }
                .coordinateSpace(.named(LayoutCheckboxSweep.coordinateSpace))
                .padding(ThawSpacing.base)
            }
            .modifier(LayoutListScrollTracking(motion: motion, proxy: proxy))
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

    private func rowView(_ row: LayoutItemListRow, in section: LayoutItemListSection, rows: [LayoutItemListRow]) -> some View {
        LayoutItemListRowView(
            row: row,
            selection: selection,
            anchors: anchors,
            isEditable: isEditable,
            showsSectionBadge: section.name == nil || row.section == .alwaysHidden,
            motion: motion,
            shownRowIDs: { Set(rows.map(\.id)) },
            onTap: {
                // A click on a row leaves the filter, so Escape and the arrows reach the list.
                NSApp.keyWindow?.makeFirstResponder(nil)
                isFocused = true
            },
            onDragStart: { motion.startAutoscroll() },
            onMoved: { motion.noteMoved($0) },
            onSweep: { startY, y in sweepChanged(from: row.id, startY: startY, to: y, rows: rows) },
            onSweepEnd: { sweepEnded(rows: rows) }
        )
        .id(row.id)
        .onGeometryChange(for: ClosedRange<CGFloat>.self) { proxy in
            let frame = proxy.frame(in: .named(LayoutCheckboxSweep.coordinateSpace))
            return frame.minY ... frame.maxY
        } action: { motion.rowSpans[row.id] = $0 }
        // Off-screen rows aren't laid out, so their last span goes stale.
        .onDisappear { motion.rowSpans[row.id] = nil }
    }

    private func sweepRows(_ rows: [LayoutItemListRow]) -> [LayoutCheckboxSweep.Row] {
        let experimental = appState.settings.layout.enableExperimentalSystemItemHiding
        return rows.compactMap { row in
            guard let span = motion.rowSpans[row.id] else { return nil }
            let lock = LayoutItemVisibility.lockReason(for: row.item, in: row.section, experimentalSystemItemHiding: experimental)
            return LayoutCheckboxSweep.Row(
                id: row.id,
                span: span,
                isShown: LayoutItemVisibility.isShown(row.section),
                isLocked: !isEditable || lock != nil
            )
        }
    }

    private func sweepChanged(from rowID: String, startY: CGFloat, to y: CGFloat, rows: [LayoutItemListRow]) {
        let sweepRows = sweepRows(rows)
        if motion.sweep == nil {
            motion.sweep = LayoutCheckboxSweep(startingAt: rowID, rows: sweepRows)
            guard motion.sweep != nil else { return }
            motion.startAutoscroll(pointer: { contentY in
                // The rows' spans start inside the list's padding.
                sweepChanged(from: rowID, startY: startY, to: contentY - ThawSpacing.base, rows: rows)
            })
        }
        guard var sweep = motion.sweep else { return }
        let before = sweep.covered.count
        sweep.extend(from: startY, to: y, rows: sweepRows)
        // Only a change redraws the rows, not every mouse move.
        guard sweep != motion.sweep else { return }
        motion.sweep = sweep
        if sweep.covered.count > before {
            ThawHaptics.snap()
        }
    }

    /// Selects the rows the sweep changes and moves them in one batch, so one undo puts them back.
    private func sweepEnded(rows: [LayoutItemListRow]) {
        defer { motion.sweep = nil }
        guard let sweep = motion.sweep else { return }
        let changes = sweep.changes(in: sweepRows(rows))
        guard !changes.isEmpty else { return }
        motion.noteBatchSweepEnded()
        selection.select(changes)
        LayoutItemVisibility.moveSelection(
            to: sweep.target ? .visible : .hidden,
            selection: selection,
            appState: appState,
            onMoved: { motion.noteMoved($0) }
        )
    }

    private func perform(_ command: LayoutItemListCommand, extends: Bool, rows: [LayoutItemListRow], proxy: ScrollViewProxy) -> Bool {
        switch command {
        case let .step(delta):
            go(LayoutItemList.step(from: stepStart(), by: delta, in: rows), extends: extends, rows: rows, proxy: proxy)
        case let .page(direction):
            go(LayoutItemList.step(from: stepStart(), by: direction * pageSize, in: rows), extends: extends, rows: rows, proxy: proxy)
        case let .edge(first):
            go(first ? rows.first : rows.last, extends: extends, rows: rows, proxy: proxy)
        case .selectAll:
            selectAll(rows)
        case .showEditor:
            showEditorForSelection()
        case .menu:
            popUpMenu()
        case .escape:
            escape()
        case .undo, .redo, .nudge, .adjacentSection, .sectionNumber:
            change(command)
        }
    }

    /// The window's own key handler takes Escape first; this covers a responder it reads as typing.
    private func escape() -> Bool {
        if query.isEmpty {
            close()
        } else {
            query = ""
        }
        return true
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
        let actions = LayoutItemListActions(selection: selection, appState: appState, onMoved: { motion.noteMoved($0) })
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

    /// Where the next keyboard step starts; see LayoutItemList.stepStart.
    private func stepStart() -> String? {
        LayoutItemList.stepStart(head: keyboardHead, anchor: selection.anchorItemID, changeCount: selection.changeCount)
    }

    private func go(_ row: LayoutItemListRow?, extends: Bool, rows: [LayoutItemListRow], proxy: ScrollViewProxy) -> Bool {
        guard let row else { return false }
        selection.click(row.id, in: row.section, kind: extends ? .extend : .replace, among: Set(rows.map(\.id)))
        keyboardHead = (row.id, selection.changeCount)
        proxy.scrollTo(row.id)
        return true
    }
}

/// What follows the pointer while rows are dragged.
struct LayoutItemListDragPreview: View {
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

/// An empty view behind the filter field that reports itself, for LayoutDashboardKeys.isEditingFilter.
struct LayoutFilterAnchor: NSViewRepresentable {
    let register: (NSView) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        register(view)
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
