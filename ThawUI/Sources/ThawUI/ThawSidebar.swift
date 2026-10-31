//
//  ThawSidebar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// One row of a ThawSidebar: a page to select, the heading over a group, or
/// the space before a group without one.
public enum ThawSidebarRow<Page: Hashable>: Hashable {
    case heading(String)
    case gap
    case page(Page)

    /// The page a click selects; nil for a heading or a gap.
    public var page: Page? {
        if case let .page(page) = self {
            return page
        }
        return nil
    }

    /// The page above or below current, past the headings and gaps, or nil at
    /// either end, for left and right, or when current isn't in rows.
    public static func page(moving direction: MoveCommandDirection, from current: Page, in rows: [Self]) -> Page? {
        let pages = rows.compactMap(\.page)
        guard let index = pages.firstIndex(of: current) else { return nil }
        let next = switch direction {
        case .up: index - 1
        case .down: index + 1
        default: index
        }
        return next != index && pages.indices.contains(next) ? pages[next] : nil
    }

    /// Rows with identities that stay unique across repeated gaps and headings, and stay put for a page as others come and go.
    static func identified(_ rows: [Self]) -> [(id: AnyHashable, row: Self)] {
        rows.enumerated().map { offset, row in
            switch row {
            case .gap: (AnyHashable("gap:\(offset)"), row)
            case let .heading(title): (AnyHashable("heading:\(offset):\(title)"), row)
            case .page: (AnyHashable(row), row)
            }
        }
    }
}

extension ThawSidebarRow: Sendable where Page: Sendable {}

/// The colours of a sidebar. Layout, focus and the keyboard stay the same in every app. An app's selection normally
/// comes from ThawTheme; the sidebar's colors parameter is for one that differs from the rest of its app.
public struct ThawSidebarColors: Equatable, Sendable {
    public enum Selection: Equatable, Sendable {
        /// The shared see-through fill of thawSelectedFill, in this tint.
        case tinted(Color)
        /// A flat fill, with an optional edge, for a selection that doesn't take the accent colour.
        case flat(fill: Color, edge: Color? = nil)
    }

    public var selection: Selection
    public var title: Color
    public var dimmedTitle: Color
    public var icon: Color

    public init(
        selection: Selection = .tinted(.accentColor),
        title: Color = .primary,
        dimmedTitle: Color = .secondary,
        icon: Color = .secondary
    ) {
        self.selection = selection
        self.title = title
        self.dimmedTitle = dimmedTitle
        self.icon = icon
    }
}

/// A settings sidebar of grouped pages, stepped through with the arrow keys once focused. With showsSelection
/// false no row looks selected, so during a search a click on any row, the current page's included, can end it.
///
/// Hand-built rows: a List draws its own selection, and its Sections crash AppKit on macOS 27.0 and 27.2
/// (a freed row view in sizeLastColumnToFit).
public struct ThawSidebar<Page: Hashable, Icon: View>: View {
    public typealias Row = ThawSidebarRow<Page>

    public static var width: CGFloat {
        220
    }

    private let rows: [Row]
    private let current: Page
    private let showsSelection: Bool
    private let colors: ThawSidebarColors?
    private let select: (Page) -> Void
    private let title: (Page) -> Text
    private let icon: (Page) -> Icon
    private let isDimmed: (Page) -> Bool

    @FocusState private var isFocused: Bool
    @Environment(\.thawTheme) private var theme

    public init(
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

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                    ForEach(Row.identified(rows), id: \.id) { entry in
                        rowView(entry.row)
                    }
                }
                .padding(.horizontal, ThawSpacing.row)
                .padding(.vertical, ThawSpacing.base)
            }
            // The opening page, and one chosen by the arrow keys, a search result or a link, stays in sight.
            .onChange(of: current, initial: true) { _, page in
                proxy.scrollTo(page)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .thawKeyboardList(isFocused: $isFocused) { direction in
            if let page = Row.page(moving: direction, from: current, in: rows) {
                select(page)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case let .heading(heading):
            ThawListHeading(Text(verbatim: heading))
                // Room above each group, so the groups read apart.
                .padding(.top, ThawSpacing.gutter)
                .padding(.bottom, ThawSpacing.tight)
                .padding(.leading, ThawSpacing.row)
        case .gap:
            // The same room a heading leaves above its group.
            Spacer(minLength: ThawSpacing.gutter)
                .frame(height: ThawSpacing.gutter)
        case let .page(page):
            let isSelected = showsSelection && page == current
            ThawSidebarPageRow(
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

/// A page's row on the selection fill, with the focus ring while the sidebar has focus.
private struct ThawSidebarPageRow<Icon: View>: View {
    let title: Text
    let icon: Icon
    let isDimmed: Bool
    let isSelected: Bool
    let showsFocus: Bool
    let colors: ThawSidebarColors
    let select: () -> Void

    /// The box the icons share, so the names line up.
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
            .modifier(SelectionFill(selection: colors.selection, isSelected: isSelected, shape: shape))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .thawSelectionCue(isSelected: isSelected, in: shape)
        .thawFocusRing(isSelected && showsFocus, in: shape)
    }
}

/// A selection's fill behind a selected row, and nothing behind any other.
struct SelectionFill<S: InsettableShape>: ViewModifier {
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
