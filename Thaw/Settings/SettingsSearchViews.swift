//
//  SettingsSearchViews.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsSearchField

/// Compact search field pinned above the settings sidebar content.
struct SettingsSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        let fieldShape = Capsule(style: .continuous)

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(text: $text, prompt: Text("Search settings…")) {
                Text("Search settings…")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .textContentType(.none)
            .autocorrectionDisabled(true)
            .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular.interactive(), in: fieldShape)
        .overlay(
            fieldShape.strokeBorder(.separator.opacity(isFocused ? 0.65 : 0.35), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

// MARK: - SettingsSearchResultsList

/// Scrollable, grouped search results for the settings sidebar.
struct SettingsSearchResultsList: View {
    let groups: [SettingsSearchGroup]
    let onSelect: (SettingsSearchEntry) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Divider()
                            .opacity(0.45)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                    }

                    SettingsSearchGroupSection(group: group, onSelect: onSelect)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - SettingsSearchGroupSection

private struct SettingsSearchGroupSection: View {
    let group: SettingsSearchGroup
    let onSelect: (SettingsSearchEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                group.pane.iconResource.view
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)

                Text(group.pane.localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 2) {
                ForEach(group.entries) { entry in
                    SettingsSearchResultButton(entry: entry) {
                        onSelect(entry)
                    }
                }
            }
        }
    }
}

// MARK: - SettingsSearchResultButton

/// Interactive search result row with hover and pressed feedback.
private struct SettingsSearchResultButton: View {
    let entry: SettingsSearchEntry
    let action: () -> Void

    @State private var isHovering = false

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            SettingsSearchResultRowContent(
                entry: entry,
                isHovering: isHovering
            )
        }
        .buttonStyle(
            SettingsSearchResultButtonStyle(
                isHovering: isHovering,
                rowShape: rowShape
            )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - SettingsSearchResultRowContent

private struct SettingsSearchResultRowContent: View {
    let entry: SettingsSearchEntry
    let isHovering: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.titleKey)
                    .font(.system(size: 13, weight: isHovering ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                if let sectionKey = entry.sectionKey {
                    Text(sectionKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let descriptionText = entry.descriptionText {
                    Text(descriptionText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovering ? Color.accentColor : Color.secondary.opacity(0.55))
                .offset(x: isHovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(rowShape)
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

// MARK: - SettingsSearchResultButtonStyle

private struct SettingsSearchResultButtonStyle: ButtonStyle {
    let isHovering: Bool
    let rowShape: RoundedRectangle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack {
                    rowShape
                        .fill(.quaternary.opacity(fillOpacity(isPressed: configuration.isPressed)))

                    rowShape
                        .fill(Color.accentColor.opacity(accentOpacity(isPressed: configuration.isPressed)))
                }
            }
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func fillOpacity(isPressed: Bool) -> Double {
        if isPressed { return 0.65 }
        if isHovering { return 0.42 }
        return 0
    }

    private func accentOpacity(isPressed: Bool) -> Double {
        if isPressed { return 0.28 }
        if isHovering { return 0.16 }
        return 0
    }
}

// MARK: - SettingsSearchEmptyView

/// Empty state shown when a query returns no matches.
struct SettingsSearchEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No settings found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}
