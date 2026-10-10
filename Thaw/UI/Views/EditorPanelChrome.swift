//
//  EditorPanelChrome.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The title and bottom bar the quick-edit popovers (Layout, Appearance) put
/// around their pane, so the two read as one family.
///
/// No glass of its own. The popover already draws its material, and a glass
/// card inside it layers a second one over the first; the bars sit in the
/// safe area instead, where the scroll edge effect keeps the content that
/// scrolls under them legible.
struct EditorPanelChrome<Content: View, BottomBar: View>: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let content: Content
    private let bottomBar: BottomBar

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        content
            .scrollEdgeEffectStyle(.automatic, for: .vertical)
            .safeAreaBar(edge: .top, spacing: 0) { heading }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                HStack(spacing: ThawSpacing.base) {
                    bottomBar
                }
                .buttonBorderShape(.capsule)
                .padding(.horizontal, ThawSpacing.gutter)
                .padding(.top, ThawSpacing.base)
                .padding(.bottom, ThawSpacing.gutter)
            }
    }

    private var heading: some View {
        VStack(spacing: ThawSpacing.hairline) {
            Text(title)
                .font(ThawType.display)
            // A popover is summoned by a gesture, not navigated to, so it
            // cannot rely on the Settings sidebar to say what it is for.
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
