//
//  ThawType.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Thaw's shared typography tokens.
///
/// System typeface throughout, no custom font, differentiated by weight and
/// one rule: data reads monospaced. Any number a user might compare across
/// time or rows (item counts, intervals, percentages) uses metric, so digits
/// don't jitter as values change.
///
/// Every token maps to a macOS Dynamic Type text style, so it scales with the
/// user's "Larger Text" preference instead of staying at a fixed point size.
public enum ThawType {
    /// Pane titles in the settings window.
    ///
    /// .title2 (17pt at the default size) rather than .title (22pt), which
    /// would read heavier than pane titles should and out of proportion with
    /// heading below it.
    public static let display = Font.system(.title2, weight: .semibold)

    /// Section headers inside a pane.
    ///
    /// .headline is 13pt at the default size and semibold already; the weight
    /// is only spelled out.
    public static let heading = Font.system(.headline, weight: .semibold)

    /// Body copy, same as SwiftUI's default body; declared for completeness
    /// so call sites can express intent.
    public static let body = Font.body

    /// Row labels and links that want a little more presence than body copy:
    /// a reading page's path and footer links, the Swap bar's profile
    /// name, a descender's main readout.
    ///
    /// Only the weight distinguishes it from body.
    public static let label = Font.system(.body, weight: .medium)

    /// Detail copy one step under body: the second line of a descender, a
    /// search result group's header, the label inside a compact button.
    ///
    /// .callout, 12pt at the default size. Call sites add their own weight.
    public static let detail = Font.system(.callout)

    /// A standing note under a control: the drag instruction above the folded
    /// bars, a reset result line, the caption under an About row.
    ///
    /// One step under detail, filling the gap between detail and caption.
    public static let footnote = Font.footnote

    /// Annotations under controls (showSettingDescriptions copy).
    public static let caption = Font.caption

    /// The smallest legible size: disclosure chevrons, badge text, footnotes
    /// on a footnote.
    ///
    /// .caption2 matches caption at the default size (10pt) but stays a
    /// separate token because the two diverge as the user's text size grows,
    /// and a chevron should stay the smaller of the two.
    public static let micro = Font.caption2

    /// An SF Symbol used as an icon beside text or in a fixed button slot.
    ///
    /// Symbols scale with their text style, so .body matches the label next
    /// to it and grows with it. Call sites keep their weight and imageScale.
    public static let symbol = Font.system(.body)

    /// A large SF Symbol standing on its own: the glyph above an empty
    /// state's message.
    ///
    /// .title (22pt at the default size); .title2 would drop the glyph to
    /// 17pt and lose the "this is a placeholder, not a row" reading.
    public static let symbolLarge = Font.system(.title)

    /// The title of a reading page, and the app's own name on the About pane.
    ///
    /// .largeTitle is the biggest text style macOS offers (26pt at the
    /// default size).
    public static let hero = Font.system(.largeTitle, weight: .semibold)

    /// Numeric readouts: counts, intervals, percentages. Monospaced digits
    /// keep columns and changing values visually stable.
    public static let metric = Font.system(.callout, weight: .medium).monospacedDigit()
}
