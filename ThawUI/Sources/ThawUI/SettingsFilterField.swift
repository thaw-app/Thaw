//
//  SettingsFilterField.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// A page's own search: a filled field as wide as the page, so it reads apart from the settings search at
/// the top of the sidebar. Escape and the clear button empty it.
public struct SettingsFilterField: View {
    public let prompt: LocalizedStringResource
    public let clearLabel: LocalizedStringResource
    @Binding public var text: String
    @FocusState private var isFocused: Bool

    public init(
        prompt: LocalizedStringResource,
        clearLabel: LocalizedStringResource,
        text: Binding<String>
    ) {
        self.prompt = prompt
        self.clearLabel = clearLabel
        _text = text
    }

    public var body: some View {
        HStack(spacing: ThawSpacing.tight) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($isFocused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(clearLabel))
            }
        }
        .padding(.horizontal, ThawSpacing.inset)
        .frame(height: 36)
        .background(.quaternary.opacity(0.6), in: Self.shape)
        // A click anywhere on the field, the glass included, puts the cursor in it.
        .contentShape(Self.shape)
        .onTapGesture { isFocused = true }
    }

    private static let shape = RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
}

/// What a page's filter shows when nothing matches, in the empty state the rest of Settings uses.
public struct NoMatchesState: View {
    public let query: String
    /// Takes the query with its surrounding spaces gone.
    private let title: (String) -> LocalizedStringResource
    /// For a query of nothing but spaces, when there is no text to quote back.
    private let emptyQueryTitle: LocalizedStringResource?
    let caption: LocalizedStringResource

    public init(
        query: String,
        title: @escaping (_ query: String) -> LocalizedStringResource,
        emptyQueryTitle: LocalizedStringResource? = nil,
        caption: LocalizedStringResource
    ) {
        self.query = query
        self.title = title
        self.emptyQueryTitle = emptyQueryTitle
        self.caption = caption
    }

    var resolvedTitle: LocalizedStringResource {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, let emptyQueryTitle {
            return emptyQueryTitle
        }
        return title(trimmed)
    }

    public var body: some View {
        ThawEmptyState(
            systemImage: "magnifyingglass",
            title: resolvedTitle,
            caption: caption
        )
    }
}
