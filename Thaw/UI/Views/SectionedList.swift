//
//  SectionedList.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SectionedList

/// A scrollable list of items broken up by section.
struct SectionedList<ItemID: Hashable, ItemContent: View>: View {
    @Binding var selection: ItemID?
    @Binding var items: [SectionedListItem<ItemID, ItemContent>]
    @State private var scrollIndicatorsFlashTrigger = 0

    let spacing: CGFloat
    let isEditing: Bool

    private(set) var contentPadding = EdgeInsets()

    private var nextSelectableItem: SectionedListItem<ItemID, ItemContent>? {
        guard
            let index = items.firstIndex(where: { $0.id == selection }),
            items.indices.contains(index + 1)
        else {
            return nil
        }
        return items[(index + 1)...].first { $0.isSelectable }
    }

    private var previousSelectableItem: SectionedListItem<ItemID, ItemContent>? {
        guard
            let index = items.firstIndex(where: { $0.id == selection }),
            items.indices.contains(index - 1)
        else {
            return nil
        }
        return items[...(index - 1)].last { $0.isSelectable }
    }

    /// Creates a sectioned list with the given selection, spacing, and items.
    init(selection: Binding<ItemID?>, items: Binding<[SectionedListItem<ItemID, ItemContent>]>, spacing: CGFloat = 0, isEditing: Bool = false) {
        self._selection = selection
        self._items = items
        self.spacing = spacing
        self.isEditing = isEditing
    }

    var body: some View {
        scrollView
            .contentMargins(.all, contentPadding, for: .scrollContent)
            .contentMargins(.all, -0.5, for: .scrollIndicators)
    }

    private var scrollView: some View {
        ScrollViewReader { scrollView in
            ScrollView {
                scrollContent(scrollView: scrollView)
            }
        }
        .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
        .onKeyDown(key: .downArrow, isEnabled: selection != nil && !isEditing) {
            if let nextSelectableItem {
                selection = nextSelectableItem.id
            }
            return .handled
        }
        .onKeyDown(key: .upArrow, isEnabled: selection != nil && !isEditing) {
            if let previousSelectableItem {
                selection = previousSelectableItem.id
            }
            return .handled
        }
        .onKeyDown(key: .returnKey, isEnabled: selection != nil && !isEditing) {
            items.first { $0.id == selection }?.action?()
            return .handled
        }
        .task {
            scrollIndicatorsFlashTrigger += 1
        }
    }

    private func scrollContent(scrollView: ScrollViewProxy) -> some View {
        LazyVStack(spacing: spacing) {
            ForEach(items, id: \.id) { item in
                SectionedListItemView(
                    selection: $selection,
                    item: item
                )
                .id(item.id)
            }
        }
        .onChange(of: selection) {
            guard let selection else { return }
            scrollView.scrollTo(selection)
        }
    }
}

// MARK: SectionedList Content Padding

extension SectionedList {
    /// Sets the padding of the sectioned list's content.
    func contentPadding(_ insets: EdgeInsets) -> SectionedList {
        withMutableCopy(of: self) { copy in
            copy.contentPadding = insets
        }
    }

    /// Sets the padding of the sectioned list's content.
    func contentPadding(_ length: CGFloat) -> SectionedList {
        contentPadding(EdgeInsets(top: length, leading: length, bottom: length, trailing: length))
    }
}

// MARK: - SectionedListItem

/// An item in a sectioned list.
///
/// `@unchecked Sendable` is required because `Content` (an arbitrary SwiftUI
/// `View`) is not itself `Sendable`. Instances are only ever created,
/// mutated, and read on the main actor (they live in `@Published` arrays on
/// `@MainActor` models such as `MenuBarSearchModel`), so this is safe.
struct SectionedListItem<ID: Hashable, Content: View>: @unchecked Sendable {
    let content: Content
    let id: ID
    let isSelectable: Bool
    let action: (@MainActor @Sendable () -> Void)?
}

// MARK: - SectionedListItemView

private struct SectionedListItemView<ItemID: Hashable, ItemContent: View>: View {
    @Environment(\.self) private var environment
    @Binding var selection: ItemID?
    @State private var isHovering = false

    let item: SectionedListItem<ItemID, ItemContent>

    private var foregroundStyle: some ShapeStyle {
        if
            environment.colorScheme == .light,
            selection == item.id
        {
            Color.primary.resolve(in: withMutableCopy(of: environment) { $0.colorScheme = .dark })
        } else {
            Color.primary.resolve(in: environment)
        }
    }

    private var borderShape: some InsettableShape {
        if !item.isSelectable {
            RoundedRectangle(cornerRadius: 0, style: .circular)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        }
    }

    private var borderOpacity: CGFloat {
        guard item.isSelectable else {
            return 0
        }
        if selection == item.id {
            return 0.5
        }
        if isHovering {
            return 0.25
        }
        return 0
    }

    var body: some View {
        Button {
            selection = item.id
        } label: {
            ZStack {
                borderShape
                    .fill(Color.accentColor.opacity(borderOpacity))
                item.content
                    .foregroundStyle(foregroundStyle)
            }
            .frame(minWidth: 22, minHeight: 22)
            .contentShape([.focusEffect, .interaction], borderShape)
        }
        .buttonStyle(.plain)
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
