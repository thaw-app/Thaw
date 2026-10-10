//
//  ThawForm.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

struct ThawForm<Content: View>: View {
    /// How the form's content is measured against the detail pane's width.
    enum ReadingWidth {
        /// Width beyond SettingsDetailLayout.columnMaxWidth becomes symmetric
        /// gutters.
        case column
        /// The pane's full width, for inherently wide content such as the
        /// layout editor's drag rows.
        case full
    }

    @Environment(\.settingsPaneTitle) private var settingsPaneTitle
    @State private var formWidth: CGFloat = 0

    private let readingWidth: ReadingWidth
    private let content: Content

    init(readingWidth: ReadingWidth = .column, @ViewBuilder content: () -> Content) {
        self.readingWidth = readingWidth
        self.content = content()
    }

    var body: some View {
        // The Form scrolls full-width so the scrollbar tracks the window edge;
        // reading width comes from gutters, not a narrower scroll view.
        VStack(alignment: .leading, spacing: 0) {
            if let settingsPaneTitle {
                // Settings passes nil and draws its own header; this is for
                // hosts like the What's New window.
                Text(settingsPaneTitle)
                    .font(ThawType.display)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, SettingsDetailLayout.titleTopInset)
                    .padding(.horizontal, SettingsDetailLayout.titleHorizontalInset)
                    .padding(.bottom, 12)
            }

            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ThawFormWidthKey.self,
                        value: proxy.size.width
                    )
                }
            }
            .onPreferenceChange(ThawFormWidthKey.self) { width in
                formWidth = width
            }
            .contentMargins(.horizontal, readingGutter, for: .scrollContent)
            .contentMargins(.vertical, 8, for: .scrollContent)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
    }

    /// Extra inset so grouped cards stay near SettingsDetailLayout.columnMaxWidth
    /// on wide windows without pinning the scrollbar to that column. Full-width
    /// forms take none.
    private var readingGutter: CGFloat {
        guard readingWidth == .column else { return 0 }
        let available = formWidth - (SettingsDetailLayout.titleHorizontalInset * 2)
        let overflow = available - SettingsDetailLayout.columnMaxWidth
        guard overflow > 0 else {
            return 0
        }
        // Quantized to 8pt so a live resize does not relayout the whole form
        // on every pixel.
        return (overflow / 2 / 8).rounded(.down) * 8
    }
}

private struct ThawFormWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
