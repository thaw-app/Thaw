//
//  EditorPanelChrome.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The title and bottom bar the quick-edit popovers (Layout, Appearance) put around their pane.
/// No glass: it would stack on the popover's material. In the safe area, the scroll edge effect keeps content legible.
public struct EditorPanelChrome<Content: View, BottomBar: View>: View {
    private let title: LocalizedStringResource
    private let subtitle: LocalizedStringResource?
    private let content: Content
    private let bottomBar: BottomBar

    public init(
        _ title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.bottomBar = bottomBar()
    }

    public var body: some View {
        content
            .scrollEdgeEffectStyle(.automatic, for: .vertical)
            .safeAreaBar(edge: .top, spacing: 0) { heading }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                HStack(spacing: ThawSpacing.base) {
                    bottomBar
                }
                .padding(.horizontal, ThawSpacing.gutter)
                .padding(.top, ThawSpacing.base)
                .padding(.bottom, ThawSpacing.gutter)
            }
            // Capsule buttons throughout, as in Settings.
            .buttonBorderShape(.capsule)
    }

    private var heading: some View {
        VStack(spacing: ThawSpacing.hairline) {
            Text(title)
                .font(ThawType.display)
            // A popover has no Settings sidebar to say what it is for.
            if let subtitle {
                Text(subtitle)
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, ThawSpacing.gutter)
        .padding(.top, ThawSpacing.gutter)
        .padding(.bottom, ThawSpacing.base)
    }
}
