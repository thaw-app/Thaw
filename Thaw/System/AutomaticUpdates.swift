//
//  AutomaticUpdates.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The updater's two switches as the one choice the settings panes show:
/// downloading implies checking.
enum AutomaticUpdates: Hashable, CaseIterable, Identifiable {
    case off, check, download

    init(checks: Bool, downloads: Bool) {
        if !checks {
            self = .off
        } else {
            self = downloads ? .download : .check
        }
    }

    var id: Self {
        self
    }

    var checks: Bool {
        self != .off
    }

    var downloads: Bool {
        self == .download
    }

    var localized: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .check: "Check only"
        case .download: "Check and download"
        }
    }
}

/// The updater's two switches, so the choice can be tested without Sparkle.
@MainActor
protocol AutomaticUpdateSwitches: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
}

extension UpdatesManager: AutomaticUpdateSwitches {}

extension AutomaticUpdateSwitches {
    var automaticUpdates: AutomaticUpdates {
        get {
            AutomaticUpdates(checks: automaticallyChecksForUpdates, downloads: automaticallyDownloadsUpdates)
        }
        set {
            automaticallyChecksForUpdates = newValue.checks
            automaticallyDownloadsUpdates = newValue.downloads
        }
    }
}
