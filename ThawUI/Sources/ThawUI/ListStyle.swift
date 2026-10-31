//
//  ListStyle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// The settings sidebar's touches, for every list: the shared icon box, the selected fill and the group headings.
/// The panel's lists keep their own glass selection. thawKeyboardList gives a list the arrow keys.
public enum ListStyle {
    /// The box every row's icon sits in, so the names line up whatever the icon.
    public static let iconBox: CGFloat = 18
    /// An app's or an extension's own icon is a little smaller than the box, to weigh what a symbol weighs.
    public static let imageSize: CGFloat = 16
    public static let symbolFont = Font.system(size: 15, weight: .regular)
    public static let rowHeight: CGFloat = 32
    public static let rowShape = RoundedRectangle(cornerRadius: ThawRadius.row, style: .continuous)
    /// How much an icon that is off fades: as much as a disabled control.
    public static let dimmedIconOpacity = ThawInk.disabledOpacity
}

/// A row's icon in the shared box: a symbol in the secondary colour, or an icon of its own a little smaller.
public struct ListRowIcon: View {
    public init(
        source: Source,
        isDimmed: Bool = false
    ) {
        self.source = source
        self.isDimmed = isDimmed
    }

    public enum Source {
        case symbol(String)
        /// An icon the app draws itself, such as an extension's or another app's.
        case custom(AnyView)
    }

    public let source: Source
    public var isDimmed = false

    public var body: some View {
        Group {
            switch source {
            case let .symbol(name):
                Image(systemName: name)
                    .font(ListStyle.symbolFont)
                    .foregroundStyle(.secondary)
            case let .custom(icon):
                icon.frame(width: ListStyle.imageSize, height: ListStyle.imageSize)
            }
        }
        .opacity(isDimmed ? ListStyle.dimmedIconOpacity : 1)
        .frame(width: ListStyle.iconBox, height: ListStyle.iconBox)
    }
}

/// The sidebar's selected row, in the theme's selection, the same whether the window is key or not,
/// under a label that keeps its own colour. The row answers clicks across the whole shape.
public struct SelectedRowBackground: ViewModifier {
    public let isSelected: Bool

    @Environment(\.thawTheme) private var theme

    public init(
        isSelected: Bool
    ) {
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        content
            .modifier(SelectionFill(selection: theme.selection, isSelected: isSelected, shape: ListStyle.rowShape))
            .contentShape(ListStyle.rowShape)
            // A fill alone can be missed; Differentiate Without Color adds a bar, and VoiceOver hears the state.
            .thawSelectionCue(isSelected: isSelected)
    }
}

extension View {
    public func selectedRowBackground(_ isSelected: Bool) -> some View {
        modifier(SelectedRowBackground(isSelected: isSelected))
    }
}

/// The small uppercase name over a group of rows. Room above it sets the groups apart, except over the first,
/// which has the list's own margin.
public struct ListSectionHeading: View {
    public let title: String
    public var isFirst = false
    /// A few words after the name, as written: an extension's section subtitle.
    public var detail: String?

    public init(
        title: String,
        isFirst: Bool = false,
        detail: String? = nil
    ) {
        self.title = title
        self.isFirst = isFirst
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.compact) {
            ThawListHeading(Text(title))
            if let detail {
                Text(detail)
                    .font(ThawType.sublabel)
                    .foregroundStyle(ThawInk.supporting)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, isFirst ? ThawSpacing.tight : ThawSpacing.gutter)
        .padding(.bottom, ThawSpacing.tight)
        .padding(.leading, ThawSpacing.row)
    }
}
