//
//  IceMenu.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct IceMenu<Title: View, Label: View, Content: View>: View {
    private let title: Title
    private let label: Label
    private let content: Content

    /// Creates a menu with the given content, title, and label.
    ///
    /// - Parameters:
    ///   - content: A group of menu items.
    ///   - title: A view to display inside the menu.
    ///   - label: A view to display as an external label for the menu.
    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder title: () -> Title,
        @ViewBuilder label: () -> Label
    ) {
        self.title = title()
        self.label = label()
        self.content = content()
    }

    /// Creates a menu with the given content, title, and label key.
    ///
    /// - Parameters:
    ///   - labelKey: A string key for the menu's external label.
    ///   - content: A group of menu items.
    ///   - title: A view to display inside the menu.
    init(
        _ labelKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content,
        @ViewBuilder title: () -> Title
    ) where Label == Text {
        self.init {
            content()
        } title: {
            title()
        } label: {
            Text(labelKey)
        }
    }

    var body: some View {
        LabeledContent {
            Menu {
                content
                    .labelStyle(.titleAndIcon)
                    .toggleStyle(.automatic)
            } label: {
                title
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .labelsHidden()
            .fixedSize()
        } label: {
            label
        }
    }
}
