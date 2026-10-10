//
//  IceForm.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct IceForm<Content: View>: View {
    @State private var formWidth: CGFloat = 0

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        // The title lives in the toolbar; repeating it here doubled the header.
        // Form scrolls full-width so the scrollbar sits at the window edge.
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onFrameChange { frame in
            formWidth = frame.width
        }
        .contentMargins(.horizontal, readingGutter, for: .scrollContent)
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
