//
//  LayoutItemListRowView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

/// One row: checkbox, picture, name, owner and, where the heading doesn't say it, the section.
/// Its own view, so a selection change redraws the rows and not the whole list.
struct LayoutItemListRowView: View {
    @Environment(AppState.self) private var appState
    let row: LayoutItemListRow
    let selection: LayoutSelectionModel
    let anchors: LayoutItemListAnchors
    let isEditable: Bool
    let showsSectionBadge: Bool
    /// The state a checkbox sweep is showing for this row, or nil when no sweep covers it.
    let sweepPreview: Bool?
    let onTap: () -> Void
    /// The sweep's start and current height in the list's coordinates.
    let onSweep: (CGFloat, CGFloat) -> Void
    let onSweepEnd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTarget = false

    var body: some View {
        let isSelected = selection.contains(row.id)
        let showsGap = isDropTarget && isEditable
        HStack(spacing: PanelRow.iconSpacing) {
            visibilityCheckbox
            content
        }
        .padding(.horizontal, PanelRow.inset)
        .frame(minHeight: LayoutDashboardMetrics.rowHeight)
        .modifier(SearchRowBackground(selected: isSelected))
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
        // A drop opens a gap above this row, with the insertion line in it. The gap is part of the
        // row's drop area, so the pointer stays on this row as the row slides down.
        .padding(.top, showsGap ? LayoutDashboardMetrics.dropGap : 0)
        .overlay(alignment: .top) {
            if showsGap {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.top, LayoutDashboardMetrics.dropGap / 2 - 1)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [LayoutItemListDrop.type], isTargeted: $isDropTarget) { providers in
            guard isEditable else { return false }
            return LayoutItemListDrop.load(providers) { ids in
                LayoutItemListDrop.drop(ids, before: row, selection: selection, appState: appState)
            }
        }
        .animation(reduceMotion ? nil : ThawMotion.interactive, value: showsGap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(Text(row.section.localizedName))
    }

    /// Everything but the checkbox. A drag starts here, so a drag on the checkbox can sweep instead.
    private var content: some View {
        HStack(spacing: PanelRow.iconSpacing) {
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
        .frame(maxWidth: .infinity, minHeight: LayoutDashboardMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onDrag {
            LayoutItemListDrop.provider(for: row.id, in: row.section, selection: selection)
        } preview: {
            LayoutItemListDragPreview(name: row.name, count: selection.contains(row.id) ? selection.count : 1)
        }
    }

    /// Checked is Visible; unchecking hides into Hidden, so an Always Hidden item checked and
    /// unchecked again ends in Hidden. With several rows selected, one checkbox moves them all.
    private var visibilityCheckbox: some View {
        let lock = LayoutItemVisibility.lockReason(
            for: row.item,
            in: row.section,
            experimentalSystemItemHiding: appState.settings.layout.enableExperimentalSystemItemHiding
        )
        let isShown = LayoutItemVisibility.isShown(row.section)
        let shownNow = lock == nil ? sweepPreview ?? isShown : isShown
        return Toggle(isOn: Binding(get: { shownNow }, set: { shown in
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
        // Dragging down the checkboxes sets every row it passes, as the first one flips to.
        .simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(LayoutCheckboxSweep.coordinateSpace))
                .onChanged { onSweep($0.startLocation.y, $0.location.y) }
                .onEnded { _ in onSweepEnd() }
        )
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
