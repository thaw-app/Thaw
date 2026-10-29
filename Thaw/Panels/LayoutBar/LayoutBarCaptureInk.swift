//
//  LayoutBarCaptureInk.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Which captures Layout draws in its own ink.
///
/// macOS inks each menu bar icon for the wallpaper behind it, and hidden icons
/// are captured over a different part of the bar than visible ones, so the same
/// row could show black and white glyphs side by side.
@MainActor
enum LayoutBarCaptureInk {
    /// The capture as drawn in the bar. A single-ink glyph becomes a template,
    /// which LayoutBarItemView draws in the bar's ink; a colour icon keeps its pixels.
    static func drawImage(for capture: MenuBarItemGlyphCapture) -> NSImage {
        let image = NSImage(cgImage: capture.cgImage, size: capture.pointSize)
        image.isTemplate = capture.isSingleInkGlyph
        return image
    }

    /// How opaquely a placeholder's app icon is drawn: a template a little
    /// lighter than a colour icon, and either one faded while disabled.
    static func placeholderFraction(isEnabled: Bool, isTemplate: Bool) -> CGFloat {
        guard isEnabled else { return 0.5 }
        return isTemplate ? 0.8 : 0.9
    }
}
