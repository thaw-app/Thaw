//
//  SettingsSearchViews.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.

import SwiftUI

// MARK: - SettingsSearchResultText

/// What a search result's row says.
public struct SettingsSearchResultText {
    public let title: Text
    /// Where the setting lives.
    public let section: Text?
    /// What the setting does.
    public let detail: Text?

    public init(title: Text, section: Text? = nil, detail: Text? = nil) {
        self.title = title
        self.section = section
        self.detail = detail
    }
}

// MARK: - SettingsSearchResultsList

/// Scrollable, grouped search results for the settings window, under a header that scrolls with them.
/// The groups and entries, and their index and ranking, are the host app's.
public struct SettingsSearchResultsList<ResultGroup: Identifiable, Entry: Identifiable, Icon: View, Header: View>: View {
    private let groups: [ResultGroup]
    private let entries: (ResultGroup) -> [Entry]
    private let highlighted: Entry.ID?
    private let hoverTint: Color?
    private let onSelect: (Entry) -> Void
    private let groupTitle: (ResultGroup) -> Text
    private let result: (Entry) -> SettingsSearchResultText
    private let groupIcon: (ResultGroup) -> Icon
    private let header: Header

    /// Entries run best first, and the highlighted one stays in sight. The header scrolls above them. The hover tint
    /// defaults to the theme's. The group icon is its pane's sidebar glyph; a bare symbol takes the heading's size and colour.
    public init(
        groups: [ResultGroup],
        entries: @escaping (ResultGroup) -> [Entry],
        highlighted: Entry.ID? = nil,
        hoverTint: Color? = nil,
        onSelect: @escaping (Entry) -> Void,
        groupTitle: @escaping (ResultGroup) -> Text,
        result: @escaping (Entry) -> SettingsSearchResultText,
        @ViewBuilder groupIcon: @escaping (ResultGroup) -> Icon,
        @ViewBuilder header: () -> Header
    ) {
        self.groups = groups
        self.entries = entries
        self.highlighted = highlighted
        self.hoverTint = hoverTint
        self.onSelect = onSelect
        self.groupTitle = groupTitle
        self.result = result
        self.groupIcon = groupIcon
        self.header = header()
    }

    public var body: some View {
        ScrollViewReader { proxy in
            list
                // The result the arrows moved to stays in sight.
                .onChange(of: highlighted) {
                    if let highlighted {
                        proxy.scrollTo(highlighted)
                    }
                }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Divider()
                            .opacity(0.45)
                            .padding(.horizontal, ThawSpacing.compact)
                            .padding(.vertical, ThawSpacing.base)
                    }

                    section(for: group)
                }
            }
            .padding(.horizontal, ThawSpacing.row)
            .padding(.bottom, ThawSpacing.inset)
        }
        .scrollContentBackground(.hidden)
    }

    private func section(for group: ResultGroup) -> some View {
        VStack(alignment: .leading, spacing: ThawSpacing.tight) {
            HStack(spacing: ThawSpacing.compact) {
                groupIcon(group)
                    .font(ThawType.symbol.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: ListStyle.iconBox, height: ListStyle.iconBox)

                ThawListHeading(groupTitle(group))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ThawSpacing.compact)
            .padding(.vertical, ThawSpacing.tight)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: ThawSpacing.hairline) {
                ForEach(entries(group)) { entry in
                    SettingsSearchResultRow(
                        result(entry),
                        isHighlighted: entry.id == highlighted,
                        hoverTint: hoverTint
                    ) {
                        onSelect(entry)
                    }
                    .id(entry.id)
                }
            }
        }
    }
}

public extension SettingsSearchResultsList where Header == EmptyView {
    init(
        groups: [ResultGroup],
        entries: @escaping (ResultGroup) -> [Entry],
        highlighted: Entry.ID? = nil,
        hoverTint: Color? = nil,
        onSelect: @escaping (Entry) -> Void,
        groupTitle: @escaping (ResultGroup) -> Text,
        result: @escaping (Entry) -> SettingsSearchResultText,
        @ViewBuilder groupIcon: @escaping (ResultGroup) -> Icon
    ) {
        self.init(
            groups: groups,
            entries: entries,
            highlighted: highlighted,
            hoverTint: hoverTint,
            onSelect: onSelect,
            groupTitle: groupTitle,
            result: result,
            groupIcon: groupIcon,
            header: { EmptyView() }
        )
    }
}

// MARK: - SettingsSearchResultRow

/// Interactive search result row with hover and pressed feedback, and the sidebar's selected fill while the
/// arrow keys are on it.
public struct SettingsSearchResultRow: View {
    private let text: SettingsSearchResultText
    private let isHighlighted: Bool
    private let hoverTint: Color?
    private let action: () -> Void

    @State private var isHovering = false
    @Environment(\.thawTheme) private var theme

    public init(
        _ text: SettingsSearchResultText,
        isHighlighted: Bool = false,
        hoverTint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.isHighlighted = isHighlighted
        self.hoverTint = hoverTint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(SettingsSearchResultButtonStyle(isHovering: isHovering, tint: hoverTint ?? theme.hoverTint))
        .selectedRowBackground(isHighlighted)
        .onHover { isHovering = $0 }
        .thawAnimation(ThawMotion.quick, value: isHovering)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: ThawSpacing.base) {
            VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                text.title
                    .font(ThawType.body.weight(isHovering ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                if let section = text.section {
                    section
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let detail = text.detail {
                    detail
                        .font(.caption)
                        // .tertiary (~25% alpha) fails the text contrast floor.
                        .foregroundStyle(ThawInk.supporting)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(ThawType.micro.weight(.semibold))
                // Vibrancy tiers rather than a hand-set opacity, so the
                // chevron adapts to whatever is behind the glass.
                .foregroundStyle(isHovering ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .offset(x: isHovering ? 1 : 0)
        }
        .padding(.horizontal, ThawSpacing.row)
        .padding(.vertical, ThawSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(ListStyle.rowShape)
    }
}

// MARK: - SettingsSearchResultButtonStyle

struct SettingsSearchResultButtonStyle: ButtonStyle {
    let isHovering: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                // The sidebar's selection wash, stronger on press.
                if let strength = Self.strength(isPressed: configuration.isPressed, isHovering: isHovering) {
                    Color.clear
                        .thawGlass(.selection(tint, strength: strength), in: ListStyle.rowShape)
                }
            }
            .opacity(configuration.isPressed ? 0.92 : 1)
            .thawAnimation(ThawMotion.instant, value: configuration.isPressed)
    }

    static func strength(isPressed: Bool, isHovering: Bool) -> ThawGlass.SelectionStrength? {
        if isPressed {
            return .selected
        }
        return isHovering ? .hover : nil
    }
}

// MARK: - SettingsSearchResultCount

/// How many results a search found, which makes a long list read as bounded and tells the
/// reader whether narrowing the query is worth it.
public struct SettingsSearchResultCount: View {
    private let text: Text

    public init(_ text: Text) {
        self.text = text
    }

    public var body: some View {
        text
            .font(ThawType.detail.weight(.medium))
            .foregroundStyle(ThawInk.supporting)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
