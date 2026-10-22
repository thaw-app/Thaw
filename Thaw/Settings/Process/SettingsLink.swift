//
//  SettingsLink.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// What the app and its settings process tell each other, one JSON object per line.
nonisolated enum SettingsLinkMessage: Codable, Equatable, Sendable {
    /// Bring the window forward on this pane, or on the pane it has.
    case show(pane: String?)
    /// The sender wrote settings, so the receiver reads them again.
    case settingsChanged
    /// The settings process can't show this pane, so the app shows it instead.
    case openInApp(pane: String)
    /// The app's Settings window is up, so the settings process closes its own.
    case shownInApp
    /// The settings process moved to this pane, so the app opens on it next time.
    case pageChanged(pane: String)
    /// The updater's state, sent by the app, which runs the updater.
    case updatesState(canCheck: Bool, lastCheck: Date?)
    /// Check for updates now, in the app, which owns the updater's windows.
    case checkForUpdates
    /// Quit was chosen in the settings process, and quits the app too.
    case quit
}

nonisolated extension SettingsLinkMessage {
    /// Nil for a line that isn't a message, such as stray output on the pipe.
    init?(line: Data) {
        guard let message = try? JSONDecoder().decode(Self.self, from: line) else { return nil }
        self = message
    }

    /// The message as one line, newline included.
    var line: Data {
        // Encoding an enum of strings and dates can't fail.
        var data = (try? JSONEncoder().encode(self)) ?? Data()
        data.append(0x0A)
        return data
    }
}

/// Which panes the settings process shows itself. The rest need the running menu bar
/// engine or the updater, which only the app has.
nonisolated enum SettingsProcessRoute {
    static let launchArgument = "--settings"

    static let ownProcessPanes: Set<String> = ["General", "The Lab", "Scripts", "About", "Privacy"]

    static func runsInOwnProcess(pane: String, simpleMode: Bool, isEnabled: Bool) -> Bool {
        isEnabled && !simpleMode && ownProcessPanes.contains(pane)
    }

    /// The pane named after the launch argument, if there is one.
    static func launchPane(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: launchArgument), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
