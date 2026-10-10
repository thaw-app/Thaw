//
//  ThawSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

public struct ThawSection<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer
    private let isBordered: Bool

    public init(
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

    public init(
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

    public init(
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

    public init(
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

    public init(
        _ title: LocalizedStringKey,
        isBordered: Bool = true,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(isBordered: isBordered) {
            Text(title)
        } content: {
            content()
        }
    }

    public var body: some View {
        // Native grouped sections supply cards, row insets and separators; clear row backgrounds to opt out of the card.
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
