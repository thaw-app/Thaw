//
//  SimpleRehideChoice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Simple Mode's one "Hide items again" menu, over the three settings the
/// full window shows separately:
/// whether items rehide, the strategy, and the delay.
nonisolated enum SimpleRehideChoice: Hashable, Identifiable {
    case never
    case whenClickingElsewhere
    case whenSwitchingApps
    case after(TimeInterval)

    /// The delays on offer. One saved in the full window that isn't listed is added to the menu.
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
}
