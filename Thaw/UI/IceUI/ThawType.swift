//
//  ThawType.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Thaw's text styles. Each maps to a macOS text style, so it follows the
/// user's text size instead of a fixed point size.
enum ThawType {
    /// Section headers inside a pane (13pt at the default size).
    static let heading = Font.system(.headline, weight: .semibold)

    /// Body copy (13pt).
    static let body = Font.body

    /// Detail one step under body (12pt). Call sites add their own weight.
    static let detail = Font.system(.callout)

    /// Annotations under controls.
    static let caption = Font.caption

    /// The smallest legible size: disclosure chevrons, badge text.
    static let micro = Font.caption2

    /// An SF Symbol beside text; scales with the label next to it.
    static let symbol = Font.system(.body)

    /// A large SF Symbol standing on its own, above an empty state.
    static let symbolLarge = Font.system(.title)
}
