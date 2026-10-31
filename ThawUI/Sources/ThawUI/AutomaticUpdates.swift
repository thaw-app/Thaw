//
//  AutomaticUpdates.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The updater's two switches as the one choice the settings panes show:
/// downloading implies checking.
public nonisolated enum AutomaticUpdates: Hashable, CaseIterable, Identifiable, Sendable {
    case off, check, download

    public init(checks: Bool, downloads: Bool) {
        if !checks {
            self = .off
        } else {
            self = downloads ? .download : .check
        }
    }

    public var id: Self {
        self
    }

    public var checks: Bool {
        self != .off
    }

    public var downloads: Bool {
        self == .download
    }
}

/// The updater's two switches, so the choice can be tested without Sparkle.
@MainActor
public protocol AutomaticUpdateSwitches: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
}

public extension AutomaticUpdateSwitches {
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
