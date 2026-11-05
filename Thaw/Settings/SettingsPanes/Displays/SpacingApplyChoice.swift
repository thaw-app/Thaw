//
//  SpacingApplyChoice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The one choice the Displays pane offers for a spacing change. It is stored as the apply
/// mode and the confirmation switch, which other code reads, so both keep their meaning.
nonisolated enum SpacingApplyChoice: Hashable, CaseIterable {
    case askFirst
    case relaunchNow
    case waitForRestart

    init(mode: SpacingApplyMode, confirms: Bool) {
        switch mode {
        case .writeOnly: self = .waitForRestart
        case .relaunchApps: self = confirms ? .askFirst : .relaunchNow
        }
    }

    var mode: SpacingApplyMode {
        self == .waitForRestart ? .writeOnly : .relaunchApps
    }

    /// Nil when the choice doesn't relaunch, which leaves the stored switch as it was.
    var confirms: Bool? {
        switch self {
        case .askFirst: true
        case .relaunchNow: false
        case .waitForRestart: nil
        }
    }
}

nonisolated extension SpacingApplyChoice {
    /// The one notice on the Spacing tab that says what applying spacing does under this choice.
    /// Other spacing controls keep short notes and point here instead of repeating it.
    var relaunchNotice: (title: LocalizedStringResource, message: LocalizedStringResource) {
        switch self {
        case .askFirst:
            (
                "Changing spacing restarts menu bar apps",
                "macOS only reads the spacing when an app starts, so Thaw quits and reopens every app with a menu bar item to apply it. Apps with unsaved work may lose it. Thaw asks before each restart. Connecting or disconnecting a display only saves that display’s spacing; use Reapply Spacing to apply it."
            )
        case .relaunchNow:
            (
                "Changing spacing restarts menu bar apps",
                "macOS only reads the spacing when an app starts, so Thaw quits and reopens every app with a menu bar item to apply it. Apps with unsaved work may lose it. Thaw doesn’t ask first, and this happens again each time a profile with different spacing is applied, such as on a Space or Focus change. Connecting or disconnecting a display only saves that display’s spacing; use Reapply Spacing to apply it."
            )
        case .waitForRestart:
            (
                "New spacing appears as apps restart",
                "macOS only reads the spacing when an app starts. Thaw saves new spacing without restarting any app, so each app shows it the next time it starts, and gaps can differ until then."
            )
        }
    }
}
