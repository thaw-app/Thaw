//
//  ExtraRole.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The Apple menu extra this bundle stands in for, read from the last
/// component of its bundle identifier (<thaw bundle id>.extra.<role>).
enum ExtraRole: String, CaseIterable {
    case focus
    case timeMachine = "timemachine"
    case timer
    case airDrop = "airdrop"
    case nowPlaying = "nowplaying"
    case userSwitcher = "user"
    case textInput = "textinput"
    /// Stand-ins for third-party items macOS won't draw. Thaw hands each slot
    /// the item's icon and name, and does the click itself.
    case slot1, slot2, slot3, slot4, slot5, slot6

    static let bundleInfix = ".extra."

    init?(bundleIdentifier: String) {
        guard let range = bundleIdentifier.range(of: Self.bundleInfix, options: .backwards) else {
            return nil
        }
        self.init(rawValue: String(bundleIdentifier[range.upperBound...]))
    }

    /// The bundle identifier of the Thaw build that embeds this helper. The
    /// helper exits when that app does.
    static func parentBundleIdentifier(of bundleIdentifier: String) -> String? {
        bundleIdentifier.range(of: bundleInfix, options: .backwards).map {
            String(bundleIdentifier[..<$0.lowerBound])
        }
    }

    /// Permanent autosave name. The agent keys the item's position row on it,
    /// so it must never change once shipped.
    var autosaveName: String {
        switch self {
        case .focus: "Thaw.Extra.Focus"
        case .timeMachine: "Thaw.Extra.TimeMachine"
        case .timer: "Thaw.Extra.Timer"
        case .airDrop: "Thaw.Extra.AirDrop"
        case .nowPlaying: "Thaw.Extra.NowPlaying"
        case .userSwitcher: "Thaw.Extra.UserSwitcher"
        case .textInput: "Thaw.Extra.TextInput"
        case .slot1: "Thaw.Extra.Slot1"
        case .slot2: "Thaw.Extra.Slot2"
        case .slot3: "Thaw.Extra.Slot3"
        case .slot4: "Thaw.Extra.Slot4"
        case .slot5: "Thaw.Extra.Slot5"
        case .slot6: "Thaw.Extra.Slot6"
        }
    }

    var displayName: String {
        switch self {
        case .focus: String(localized: "Focus")
        case .timeMachine: String(localized: "Time Machine")
        case .timer: String(localized: "Timer")
        case .airDrop: String(localized: "AirDrop")
        case .nowPlaying: String(localized: "Now Playing")
        case .userSwitcher: String(localized: "Fast User Switching")
        case .textInput: String(localized: "Input Menu")
        case .slot1, .slot2, .slot3, .slot4, .slot5, .slot6: String(localized: "Stand-in")
        }
    }

    /// The slot number, for the third-party stand-ins.
    var slot: Int? {
        switch self {
        case .slot1: 1
        case .slot2: 2
        case .slot3: 3
        case .slot4: 4
        case .slot5: 5
        case .slot6: 6
        default: nil
        }
    }
}
