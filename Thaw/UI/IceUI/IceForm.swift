//
//  IceForm.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct IceForm<Content: View>: View {
    @Environment(\.settingsPaneTitle) private var settingsPaneTitle
    @State private var formWidth: CGFloat = 0

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        // Page title sits above the Form (not in a grouped row/card). Form
        // scrolls full-width so the scrollbar tracks the detail pane / window
        // edge; reading width is enforced with symmetric gutters instead of
        // shrinking the scroll view itself.
        VStack(alignment: .leading, spacing: 0) {
            if let settingsPaneTitle {
                Text(settingsPaneTitle)
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, SettingsDetailLayout.titleTopInset)
                    .padding(.horizontal, SettingsDetailLayout.titleHorizontalInset)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }

            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: IceFormWidthKey.self,
                        value: proxy.size.width
                    )
                }
            }
            .onPreferenceChange(IceFormWidthKey.self) { width in
                formWidth = width
            }
            .contentMargins(.horizontal, readingGutter, for: .scrollContent)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
    }

    /// Extra inset so grouped cards stay near ``SettingsDetailLayout/columnMaxWidth``
    /// on wide windows without pinning the scrollbar to that column.
    private var readingGutter: CGFloat {
        let available = formWidth - (SettingsDetailLayout.titleHorizontalInset * 2)
        let overflow = available - SettingsDetailLayout.columnMaxWidth
        guard overflow > 0 else {
            return 0
        }
        return overflow / 2
    }
}

private struct IceFormWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
