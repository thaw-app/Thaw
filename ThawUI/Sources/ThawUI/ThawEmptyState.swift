//
//  ThawEmptyState.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Empty, loading or error placeholder for a pane, list or panel: a symbol or spinner, a title and
/// an optional caption. No glass, background or border: empty states sit on a surface.
public struct ThawEmptyState: View {
    private let systemImage: String
    private let title: LocalizedStringResource
    private let caption: LocalizedStringResource?
    private let isLoading: Bool
    private let actionTitle: LocalizedStringResource?
    private let action: (() -> Void)?

    /// isLoading swaps the symbol for a spinner, for "waiting on data" states rather than "nothing here" states. The action
    /// title is the one step that fixes the state, when there is one: an empty state naming a problem should say what to do next.
    public init(
        systemImage: String,
        title: LocalizedStringResource,
        caption: LocalizedStringResource? = nil,
        isLoading: Bool = false,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.caption = caption
        self.isLoading = isLoading
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: ThawSpacing.row) {
            symbol

            Text(title)
                .font(ThawType.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let caption {
                Text(caption)
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .padding(.top, ThawSpacing.tight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ThawSpacing.gutter)
        .padding(.vertical, ThawSpacing.section)
        // Combined only when there is nothing to press: a combined element
        // would swallow the button.
        .accessibilityElement(children: actionTitle == nil ? .combine : .contain)
    }

    @ViewBuilder
    private var symbol: some View {
        if isLoading {
            ProgressView()
                .controlSize(.regular)
        } else {
            Image(systemName: systemImage)
                .font(ThawType.symbolLarge.weight(.light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
