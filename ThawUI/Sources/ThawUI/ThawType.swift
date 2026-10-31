//
//  ThawType.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Shared typography tokens: the system typeface, differentiated by weight. Numbers a user might compare use
/// metric so digits don't jitter. Every token maps to a Dynamic Type text style, so it scales with "Larger Text".
public enum ThawType {
    /// Pane titles. .title2 (17pt) because .title (22pt) reads too heavy and out of proportion with heading.
    public static let display = Font.system(.title2, weight: .semibold)

    /// Section headers inside a pane. .headline is already semibold at 13pt; the weight is only spelled out.
    public static let heading = Font.system(.headline, weight: .semibold)

    /// Same as SwiftUI's default body, so call sites can express intent.
    public static let body = Font.body

    /// Row labels and links that want more presence than body copy. Only the weight differs.
    public static let label = Font.system(.body, weight: .medium)

    /// Detail copy one step under body. .callout, 12pt at the default size; call sites add their own weight.
    public static let detail = Font.system(.callout)

    /// A small label over a value, or a line under a heading. .subheadline, 11pt at the default size.
    public static let sublabel = Font.subheadline

    /// A standing note under a control, between detail and caption.
    public static let footnote = Font.footnote

    /// Annotations under controls (showSettingDescriptions copy).
    public static let caption = Font.caption

    /// The smallest legible size: chevrons, badge text. Matches caption at the default 10pt, but the two
    /// diverge as the user's text size grows, and a chevron should stay the smaller.
    public static let micro = Font.caption2

    /// An SF Symbol beside text or in a fixed button slot. .body matches the label next to it and grows
    /// with it; call sites keep their weight and imageScale.
    public static let symbol = Font.system(.body)

    /// A large SF Symbol above an empty state's message. .title (22pt); .title2 (17pt) would lose
    /// the "this is a placeholder, not a row" reading.
    public static let symbolLarge = Font.system(.title)

    /// A reading page's title, and the app's name on the About pane. .largeTitle, the biggest macOS text style (26pt).
    public static let hero = Font.system(.largeTitle, weight: .semibold)

    /// Numeric readouts: counts, intervals, percentages. Monospaced digits keep changing values stable.
    public static let metric = Font.system(.callout, weight: .medium).monospacedDigit()
}
