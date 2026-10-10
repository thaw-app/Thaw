//
//  SearchViews.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - SearchResultsList

/// Scrollable, grouped search results for the settings sidebar.
struct SearchResultsList: View {
    let groups: [SearchGroup]
    let onSelect: (SearchEntry) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Divider()
                            .opacity(0.45)
                            .padding(.horizontal, ThawSpacing.compact)
                            .padding(.vertical, ThawSpacing.base)
                    }

                    SearchGroupSection(group: group, onSelect: onSelect)
                }
            }
            .padding(.horizontal, ThawSpacing.row)
            .padding(.bottom, ThawSpacing.inset)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - SearchGroupSection

private struct SearchGroupSection: View {
    let group: SearchGroup
    let onSelect: (SearchEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.tight) {
            HStack(spacing: ThawSpacing.compact) {
                // The same glyph the sidebar row shows, so a result group
                // names its pane the way the sidebar does.
                group.pane.iconResource.image
                    .font(ThawType.symbol.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 16)

                Text(group.pane.localized)
                    .font(ThawType.detail.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ThawSpacing.compact)
            .padding(.vertical, ThawSpacing.tight)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: ThawSpacing.hairline) {
                ForEach(group.entries) { entry in
                    SearchResultButton(entry: entry) {
                        onSelect(entry)
                    }
                }
            }
        }
    }
}

// MARK: - SearchResultRowAppearance

private enum SearchResultRowAppearance {
    static let shape = RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
}

// MARK: - SearchResultButton

/// Interactive search result row with hover and pressed feedback.
private struct SearchResultButton: View {
    let entry: SearchEntry
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            SearchResultRowContent(
                entry: entry,
                isHovering: isHovering
            )
        }
        .buttonStyle(
            SearchResultButtonStyle(
                isHovering: isHovering,
                rowShape: SearchResultRowAppearance.shape
            )
        )
        .onHover { isHovering = $0 }
        .thawAnimation(ThawMotion.quick, value: isHovering)
    }
}

// MARK: - SearchResultRowContent

private struct SearchResultRowContent: View {
    let entry: SearchEntry
    let isHovering: Bool

    var body: some View {
        HStack(alignment: .center, spacing: ThawSpacing.base) {
            VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                Text(entry.titleKey)
                    .font(ThawType.body.weight(isHovering ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                // Section says where the row lives, description what it does.
                if let sectionKey = entry.sectionKey {
                    Text(sectionKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let descriptionText = entry.descriptionText {
                    Text(descriptionText)
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
        .contentShape(SearchResultRowAppearance.shape)
    }
}

// MARK: - SearchResultButtonStyle

private struct SearchResultButtonStyle: ButtonStyle {
    let isHovering: Bool
    let rowShape: RoundedRectangle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                // Same selection wash as the sidebar pill, stronger on press.
                if let strength = strength(isPressed: configuration.isPressed) {
                    Color.clear
                        .thawGlass(.selection(.accentColor, strength: strength), in: rowShape)
                }
            }
            .opacity(configuration.isPressed ? 0.92 : 1)
            .thawAnimation(ThawMotion.instant, value: configuration.isPressed)
    }

    private func strength(isPressed: Bool) -> ThawGlass.SelectionStrength? {
        if isPressed {
            return .selected
        }
        return isHovering ? .hover : nil
    }
}

// MARK: - SearchEmptyView

/// Empty state shown when a query returns no matches.
struct SearchEmptyView: View {
    /// The query that came up empty, quoted back so the reader can see
    /// what was actually searched, typos included.
    var query: String = ""

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        ThawEmptyState(
            systemImage: "magnifyingglass",
            title: trimmed.isEmpty ? "No settings found" : "No settings match “\(trimmed)”",
            caption: "Try a shorter or broader term."
        )
    }
}
