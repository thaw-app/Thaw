//
//  ThawEmptyState.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Shared empty / loading / error placeholder for a pane, list, or panel with
/// nothing to show.
///
/// A centered symbol or spinner, a title, and an optional caption. No glass,
/// background or border: empty states sit on a surface.
public struct ThawEmptyState: View {
    private let systemImage: String
    private let title: LocalizedStringKey
    private let caption: LocalizedStringKey?
    private let isLoading: Bool
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - systemImage: SF Symbol shown above the title. Ignored while
    ///     isLoading is true, when a ProgressView takes its place.
    ///   - title: Primary message, e.g. "No settings found".
    ///   - caption: Optional supporting detail shown under the title.
    ///   - isLoading: When true, shows a spinner instead of systemImage,
    ///     use for "waiting on data" states rather than "nothing here" states.
    ///   - actionTitle: The one step that fixes the state, when there is one.
    ///     An empty state that names a problem should say what to do next.
    ///   - action: Runs when the step is chosen.
    public init(
        systemImage: String,
        title: LocalizedStringKey,
        caption: LocalizedStringKey? = nil,
        isLoading: Bool = false,
        actionTitle: LocalizedStringKey? = nil,
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
        VStack(spacing: 10) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
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
