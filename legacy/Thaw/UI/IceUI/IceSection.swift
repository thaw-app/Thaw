//
//  IceSection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct IceSection<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer
    private let isBordered: Bool

    init(
        isBordered: Bool = true,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.isBordered = isBordered
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    init(
        isBordered: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(isBordered: isBordered) {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        isBordered: Bool = true,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(isBordered: isBordered) {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        isBordered: Bool = true,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(isBordered: isBordered) {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        _ title: LocalizedStringKey,
        isBordered: Bool = true,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(isBordered: isBordered) {
            // No explicit font; the native grouped Section header styles it.
            Text(title)
        } content: {
            content()
        }
    }

    var body: some View {
        // Native grouped Section: the OS draws the card, insets, and separators.
        // `isBordered == false` drops the card by clearing the row background.
        //
        // - Important: an `IceSection` must be a direct child of a `List`/`Form`
        //   (e.g. inside ``IceForm``). Inside a `VStack` it collapses to one plain row.
        if isBordered {
            nativeSection
        } else {
            nativeSection
                .listRowBackground(Color.clear)
        }
    }

    private var nativeSection: some View {
        Section {
            content
        } header: {
            headerView
        } footer: {
            footerView
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if Header.self != EmptyView.self {
            header
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        if Footer.self != EmptyView.self {
            footer
        }
    }
}
