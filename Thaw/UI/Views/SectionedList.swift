//
//  SectionedList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - SectionedList

/// A scrollable list of items broken up by section.
///
/// Section headers are modeled as non-selectable items, so keyboard navigation
/// steps over them while arrowing through the selectable rows between them.
struct SectionedList<ItemID: Hashable, ItemContent: View>: View {
    @Binding var selection: ItemID?
    @Binding var items: [SectionedListItem<ItemID, ItemContent>]

    let isEditing: Bool

    private var contentPadding: CGFloat = 0

    /// Creates a sectioned list with the given selection and items.
    ///
    /// While isEditing is true, the list stops handling arrow and return
    /// keys so a text field elsewhere on screen can have them.
    init(selection: Binding<ItemID?>, items: Binding<[SectionedListItem<ItemID, ItemContent>]>, isEditing: Bool = false) {
        self._selection = selection
        self._items = items
        self.isEditing = isEditing
    }

    private var handlesKeys: Bool {
        selection != nil && !isEditing
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items, id: \.id) { item in
                        SectionedListItemView(selection: $selection, item: item)
                    }
                }
                .onChange(of: selection) {
                    guard let selection else { return }
                    proxy.scrollTo(selection)
                }
            }
        }
        .scrollIndicatorsFlash(onAppear: true)
        .contentMargins(.all, contentPadding, for: .scrollContent)
        .contentMargins(.all, -0.5, for: .scrollIndicators)
        .onKeyDown(key: .downArrow, isEnabled: handlesKeys) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyDown(key: .upArrow, isEnabled: handlesKeys) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyDown(key: .returnKey, isEnabled: handlesKeys) {
            items.first { $0.id == selection }?.action?()
            return .handled
        }
    }

    /// Sets the padding of the sectioned list's content.
    func contentPadding(_ length: CGFloat) -> SectionedList {
        var copy = self
        copy.contentPadding = length
        return copy
    }

    /// Walks from the current selection in steps of step and selects the
    /// first selectable item found, staying put if there is none.
    private func moveSelection(by step: Int) {
        guard let selectedIndex = items.firstIndex(where: { $0.id == selection }) else {
            return
        }
        var index = selectedIndex + step
        while items.indices.contains(index) {
            if items[index].isSelectable {
                selection = items[index].id
                return
            }
            index += step
        }
    }
}

// MARK: - SectionedListItem

/// An item in a sectioned list.
///
/// Unchecked Sendable because the content view is not Sendable; instances
/// live only on the main actor.
struct SectionedListItem<ID: Hashable, Content: View>: @unchecked Sendable {
    let content: Content
    let id: ID
    let isSelectable: Bool
    let action: (@MainActor @Sendable () -> Void)?
}

// MARK: - SectionedListItemView

private struct SectionedListItemView<ItemID: Hashable, ItemContent: View>: View {
    @Binding var selection: ItemID?
    @State private var isHovering = false

    let item: SectionedListItem<ItemID, ItemContent>

    private var isSelected: Bool {
        selection == item.id
    }

    /// Selection and hover paint the same shape the row is hit-tested
    /// against. Non-selectable items (section headers) square it off so their
    /// focus effect spans the full row.
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: item.isSelectable ? ThawRadius.control : 0, style: .continuous)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if item.isSelectable {
            if isSelected {
                // The opaque base keeps the panel's glass from refracting
                // behind the selected row's label and menu bar preview.
                rowShape
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        Color.clear
                            .thawGlass(.selection(.accentColor, strength: .selected), in: rowShape)
                    }
            } else if isHovering {
                Color.clear
                    .thawGlass(.selection(.accentColor, strength: .hover), in: rowShape)
            }
        }
    }

    var body: some View {
        Button {
            selection = item.id
        } label: {
            item.content
                .frame(minWidth: 22, minHeight: 22)
                .contentShape([.focusEffect, .interaction], rowShape)
                .background {
                    rowBackground
                }
        }
        .buttonStyle(.plain)
        // Under Differentiate Without Color the accent wash alone is not a
        // mark; the cue adds the leading bar and sets the selected trait.
        .thawSelectionCue(isSelected: isSelected && item.isSelectable)
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                item.action?()
            }
        )
        .accessibilityAction(named: Text("Open")) {
            item.action?()
        }
    }
}
