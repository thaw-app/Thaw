//
//  LayoutBanner.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The one warning the Layout pane shows above its bars.
///
/// Several can be true at once, and stacked they push the bars off the first screen. The pane shows the
/// most serious and leaves the rest until it is dealt with.
nonisolated enum LayoutBanner: Equatable {
    /// macOS has Thaw switched off in its menu bar settings, so nothing in the pane can work.
    case deniedBySystem
    /// Some running apps' items cannot be read.
    case outOfReach
    /// Icons are drawn from app icons because Screen Recording is off.
    case noScreenRecording

    static func mostSerious(
        isDeniedBySystem: Bool,
        hasItemsOutOfReach: Bool,
        hasScreenRecording: Bool
    ) -> LayoutBanner? {
        if isDeniedBySystem { return .deniedBySystem }
        if hasItemsOutOfReach { return .outOfReach }
        return hasScreenRecording ? nil : .noScreenRecording
    }

    /// Whether tips may sit beside this warning. A tip under a warning that something is broken is noise.
    static func allowsTips(beside banner: LayoutBanner?) -> Bool {
        banner == nil || banner == .noScreenRecording
    }
}
