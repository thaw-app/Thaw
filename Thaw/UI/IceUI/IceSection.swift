//
//  IceSection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct IceSectionOptions: OptionSet {
    let rawValue: Int

    static let isBordered = IceSectionOptions(rawValue: 1 << 0)
    static let hasDividers = IceSectionOptions(rawValue: 1 << 1)

    static let plain: IceSectionOptions = []
    static let defaultValue: IceSectionOptions = [.isBordered, .hasDividers]
}

struct IceSection<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer
    private let spacing: CGFloat
    private let options: IceSectionOptions

    private var isBordered: Bool {
        options.contains(.isBordered)
    }

    private var hasDividers: Bool {
        options.contains(.hasDividers)
    }

    init(
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .defaultValue,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.spacing = spacing
        self.options = options
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    init(
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .defaultValue,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(spacing: spacing, options: options) {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .defaultValue,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(spacing: spacing, options: options) {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .defaultValue,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(spacing: spacing, options: options) {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        _ title: LocalizedStringKey,
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .defaultValue,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(spacing: spacing, options: options) {
            Text(title).font(.headline)
        } content: {
            content()
        }
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                headerView

                if isBordered {
                    IceGroupBox {
                        contentLayout
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.quaternary)
                    )
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
                } else {
                    contentLayout
                }

                footerView
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var contentLayout: some View {
        if hasDividers {
            _VariadicView.Tree(IceSectionLayout(spacing: spacing)) {
                content.frame(maxWidth: .infinity)
            }
        } else {
            content.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if Header.self != EmptyView.self {
            header
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 8)
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        if Footer.self != EmptyView.self {
            footer
                .padding([.bottom, .leading], 8)
                .padding(.top, 2)
        }
    }
}

// MARK: - IceSectionLayout

private struct IceSectionLayout: _VariadicView_UnaryViewRoot {
    let spacing: CGFloat

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(children) { child in
                child
                    .transition(.opacity.combined(with: .scale(scale: 0.98))) // Smooth Tahoe-style transitions

                if child.id != last {
                    IceSectionDivider()
                }
            }
        }
        .padding(8)
    }
}

// MARK: - IceSectionDivider

private struct IceSectionDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 4)
    }
}

extension CGFloat {
    /// The default spacing for an ``IceSection``.
    static let iceSectionDefaultSpacing: CGFloat = 8
}
