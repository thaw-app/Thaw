//
//  SectionDividerStyle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The display style for section divider control items.
nonisolated enum SectionDividerStyle: Int, CaseIterable, Identifiable {
    case noDivider = 0
    case chevron = 1
    case line = 2
    case dot = 3
    case slash = 4
    case custom = 5

    var id: Int {
        rawValue
    }

    var localized: LocalizedStringKey {
        switch self {
        case .noDivider: "None"
        case .chevron: "Chevron"
        case .line: "Line"
        case .dot: "Dot"
        case .slash: "Slash"
        case .custom: "Custom"
        }
    }

    /// The image a divider in this style draws, or nil when it draws none.
    var image: ControlItemImage.ImageBuiltinName? {
        switch self {
        case .noDivider: nil
        case .chevron: .chevronSmall
        case .line: .dividerLine
        case .dot: .dividerDot
        case .slash: .dividerSlash
        case .custom: nil
        }
    }
}

/// The image a Custom section divider draws, chosen in Layout.
nonisolated struct SectionDividerCustomMark: Equatable, Sendable {
    let data: Data
    /// Drawn in the menu bar's own color, like Apple's icons, instead of its colors.
    let isTemplate: Bool
}
