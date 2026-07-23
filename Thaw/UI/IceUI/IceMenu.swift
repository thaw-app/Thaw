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
    private let primaryAction: (() -> Void)?

    /// Creates a menu with the given content, title, and label.
    ///
    /// - Parameters:
    ///   - content: A group of menu items.
    ///   - title: A view to display inside the menu.
    ///   - label: A view to display as an external label for the menu.
    ///   - primaryAction: An optional action invoked when the menu button is
    ///     clicked (items still open via the menu indicator).
    init(
        primaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder title: () -> Title,
        @ViewBuilder label: () -> Label
    ) {
        self.title = title()
        self.label = label()
        self.content = content()
        self.primaryAction = primaryAction
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

    /// Creates a compact glass menu with no external leading label — for
    /// inline row/toolbar actions such as "Update" or an ellipsis control.
    init(
        primaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder title: () -> Title
    ) where Label == EmptyView {
        self.init(primaryAction: primaryAction) {
            content()
        } title: {
            title()
        } label: {
            EmptyView()
        }
    }

    var body: some View {
        if Label.self == EmptyView.self {
            menuButton
        } else {
            LabeledContent {
                menuButton
            } label: {
                label
            }
        }
    }

    private var menuButton: some View {
        menu
            .menuStyle(.button)
            .buttonStyle(.glass)
            .labelsHidden()
            .fixedSize()
    }

    @ViewBuilder
    private var menu: some View {
        if let primaryAction {
            Menu {
                menuContent
            } label: {
                title
            } primaryAction: {
                primaryAction()
            }
        } else {
            Menu {
                menuContent
            } label: {
                title
            }
        }
    }

    private var menuContent: some View {
        content
            .labelStyle(.titleAndIcon)
            .toggleStyle(.automatic)
    }
}
