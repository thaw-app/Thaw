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
        .sectionedListKeys(selection: $selection, items: items, isEnabled: !isEditing)
    }

    /// Sets the padding of the sectioned list's content.
    func contentPadding(_ length: CGFloat) -> SectionedList {
        var copy = self
        copy.contentPadding = length
        return copy
    }
}

// MARK: - Keyboard

/// Steps through a sectioned list's selectable rows, skipping the headers.
nonisolated enum SectionedListNavigation {
    /// The first selectable row step rows from the selection, or the selection
    /// itself when there is none that way.
    static func step<ID: Hashable>(from selection: ID?, by step: Int, in rows: [(id: ID, isSelectable: Bool)]) -> ID? {
        guard let selectedIndex = rows.firstIndex(where: { $0.id == selection }) else {
            return selection
        }
        var index = selectedIndex + step
        while rows.indices.contains(index) {
            if rows[index].isSelectable {
                return rows[index].id
            }
            index += step
        }
        return selection
    }

    /// What a key the list listens for does: open the selected row, or step through the rows.
    struct Command: Equatable {
        /// Rows to step, or nil to open the selected row.
        let step: Int?
    }

    /// Nil for an arrow with Shift, Command, Option or Control, which the focused search field uses to select text.
    /// The keypad and function flags macOS sets on every arrow press don't count.
    static func command(for key: KeyEquivalent, modifiers: EventModifiers) -> Command? {
        if key == .return {
            return Command(step: nil)
        }
        guard modifiers.isDisjoint(with: [.shift, .command, .option, .control]) else { return nil }
        return Command(step: key == .downArrow ? 1 : -1)
    }
}

extension View {
    /// Arrow keys move the selection and Return opens the selected row. A search field above
    /// the list uses it too, since the field keeps the focus while the user types.
    func sectionedListKeys<ItemID: Hashable>(
        selection: Binding<ItemID?>,
        items: [SectionedListItem<ItemID, some View>],
        isEnabled: Bool = true
    ) -> some View {
        onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
            guard isEnabled, selection.wrappedValue != nil,
                  let command = SectionedListNavigation.command(for: press.key, modifiers: press.modifiers)
            else { return .ignored }
            if let step = command.step {
                let rows = items.map { (id: $0.id, isSelectable: $0.isSelectable) }
                selection.wrappedValue = SectionedListNavigation.step(from: selection.wrappedValue, by: step, in: rows)
            } else {
                items.first { $0.id == selection.wrappedValue }?.action?()
            }
            return .handled
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
