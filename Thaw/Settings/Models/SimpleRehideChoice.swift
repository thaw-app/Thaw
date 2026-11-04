//
//  SimpleRehideChoice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The "Hide items again" choice over three stored settings: whether items rehide, the strategy and the delay.
/// Never keeps the strategy and delay, so turning rehiding back on returns to the last other choice.
nonisolated enum SimpleRehideChoice: Hashable, Identifiable {
    case never
    case whenClickingElsewhere
    case whenSwitchingApps
    case after(TimeInterval)

    /// The delays on offer. One saved through a settings link that isn't listed is added to the menu.
    static let delays: [TimeInterval] = [5, 10, 15, 30, 60]

    var id: Self {
        self
    }

    init(autoRehide: Bool, strategy: RehideStrategy, interval: TimeInterval) {
        guard autoRehide else {
            self = .never
            return
        }
        switch strategy {
        case .smart: self = .whenClickingElsewhere
        case .focusedApp: self = .whenSwitchingApps
        case .timed: self = .after(interval)
        }
    }

    /// The menu's entries, with the current choice included even when its delay isn't one of the listed ones.
    static func options(including current: Self) -> [Self] {
        var options: [Self] = [.never, .whenClickingElsewhere, .whenSwitchingApps] + delays.map { .after($0) }
        if !options.contains(current) {
            options.append(current)
        }
        return options
    }

    /// What to save. The delay is left alone unless a delay was chosen.
    func settings(keepingInterval interval: TimeInterval) -> (autoRehide: Bool, strategy: RehideStrategy?, interval: TimeInterval) {
        switch self {
        case .never: (false, nil, interval)
        case .whenClickingElsewhere: (true, .smart, interval)
        case .whenSwitchingApps: (true, .focusedApp, interval)
        case let .after(seconds): (true, .timed, seconds)
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .never: "Never"
        case .whenClickingElsewhere: "When I click elsewhere"
        case .whenSwitchingApps: "When I switch apps"
        case let .after(seconds) where seconds == 60: "After 1 minute"
        case let .after(seconds): "After \(Int(seconds)) seconds"
        }
    }

    /// What happens under this choice, for the line under the menu.
    var explanation: LocalizedStringResource {
        switch self {
        case .never:
            "Hidden items stay in the menu bar until you hide them yourself."
        case .whenClickingElsewhere:
            "Hidden items go away when you click elsewhere or switch apps, but not while one of their menus is open."
        case .whenSwitchingApps:
            "Hidden items go away after you switch to another app."
        case .after:
            "Hidden items go away once the pointer has been off the menu bar for that long."
        }
    }

    /// The choice as one line, such as "Hide items again: Never", for the rehide shortcut's
    /// notification and a profile's summary.
    var summaryLine: String {
        switch self {
        case .never: String(localized: "Hide items again: Never")
        case .whenClickingElsewhere: String(localized: "Hide items again: When I click elsewhere")
        case .whenSwitchingApps: String(localized: "Hide items again: When I switch apps")
        case let .after(seconds) where seconds == 60: String(localized: "Hide items again: After 1 minute")
        case let .after(seconds): String(localized: "Hide items again: After \(Int(seconds)) seconds")
        }
    }
}
