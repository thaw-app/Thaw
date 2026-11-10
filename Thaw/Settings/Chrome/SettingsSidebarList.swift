//
//  SettingsSidebarList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: - SettingsSidebarList

/// Lightweight sidebar list matching `ThawSidebar` layout and keyboard behavior without `.scrollEdgeEffectStyle(.soft)`.
struct SettingsSidebarList<Page: Hashable, Icon: View>: View {
    typealias Row = ThawSidebarRow<Page>

    private let rows: [Row]
    private let current: Page
    private let showsSelection: Bool
    private let colors: ThawSidebarColors?
    private let select: (Page) -> Void
    private let title: (Page) -> Text
    private let isDimmed: (Page) -> Bool
    private let icon: (Page) -> Icon

    @FocusState private var isFocused: Bool
    @Environment(\.thawTheme) private var theme

    init(
        rows: [Row],
        current: Page,
        showsSelection: Bool = true,
        colors: ThawSidebarColors? = nil,
        select: @escaping (Page) -> Void,
        title: @escaping (Page) -> Text,
        isDimmed: @escaping (Page) -> Bool = { _ in false },
        @ViewBuilder icon: @escaping (Page) -> Icon
    ) {
        self.rows = rows
        self.current = current
        self.showsSelection = showsSelection
        self.colors = colors
        self.select = select
        self.title = title
        self.isDimmed = isDimmed
        self.icon = icon
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                    ForEach(identifiedRows, id: \.id) { entry in
                        rowView(entry.row)
                    }
                }
                .padding(.horizontal, ThawSpacing.row)
                .padding(.vertical, ThawSpacing.base)
            }
            .onChange(of: current, initial: true) { _, page in
                proxy.scrollTo(page)
            }
        }
        .thawKeyboardList(isFocused: $isFocused) { direction in
            if let page = Row.page(moving: direction, from: current, in: rows) {
                select(page)
            }
        }
    }

    private var identifiedRows: [(id: AnyHashable, row: Row)] {
        rows.enumerated().map { offset, row in
            switch row {
            case .gap: (AnyHashable("gap:\(offset)"), row)
            case let .heading(headingTitle): (AnyHashable("heading:\(offset):\(headingTitle)"), row)
            case .page: (AnyHashable(row), row)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case let .heading(heading):
            ThawListHeading(Text(verbatim: heading))
                .padding(.top, ThawSpacing.gutter)
                .padding(.bottom, ThawSpacing.tight)
                .padding(.leading, ThawSpacing.row)
        case .gap:
            Spacer(minLength: ThawSpacing.gutter)
                .frame(height: ThawSpacing.gutter)
        case let .page(page):
            let isSelected = showsSelection && page == current
            SettingsSidebarPageRow(
                title: title(page),
                icon: icon(page),
                isDimmed: isDimmed(page),
                isSelected: isSelected,
                showsFocus: isFocused,
                colors: colors ?? ThawSidebarColors(selection: theme.selection),
                select: { select(page) }
            )
            .id(page)
        }
    }
}

private struct SettingsSidebarPageRow<Icon: View>: View {
    let title: Text
    let icon: Icon
    let isDimmed: Bool
    let isSelected: Bool
    let showsFocus: Bool
    let colors: ThawSidebarColors
    let select: () -> Void

    private static var iconBox: CGFloat {
        18
    }

    private static var height: CGFloat {
        32
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThawRadius.row, style: .continuous)
    }

    var body: some View {
        Button(action: select) {
            Label {
                title
                    .font(ThawType.body)
                    .foregroundStyle(isDimmed ? colors.dimmedTitle : colors.title)
                    .lineLimit(1)
            } icon: {
                icon
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(colors.icon)
                    .opacity(isDimmed ? ThawInk.disabledOpacity : 1)
                    .frame(width: Self.iconBox, height: Self.iconBox)
            }
            .padding(.horizontal, ThawSpacing.row)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .modifier(SidebarSelectionFill(selection: colors.selection, isSelected: isSelected, shape: shape))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .thawSelectionCue(isSelected: isSelected, in: shape)
        .thawFocusRing(isSelected && showsFocus, in: shape)
    }
}

private struct SidebarSelectionFill<S: InsettableShape>: ViewModifier {
    let selection: ThawSidebarColors.Selection
    let isSelected: Bool
    let shape: S

    func body(content: Content) -> some View {
        switch selection {
        case let .tinted(tint):
            content.thawSelectedFill(isSelected, tint: tint, in: shape)
        case let .flat(fill, edge):
            content.background {
                if isSelected {
                    shape
                        .fill(fill)
                        .overlay {
                            if let edge {
                                shape.strokeBorder(edge, lineWidth: 1)
                            }
                        }
                }
            }
        }
    }
}
