//
//  SystemExtraStandInIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import PlatformRuntimeKit
import Testing
@testable import Thaw

/// The layout identifier each stand-in's status item gets, and which stand-in
/// replaces each takeover item.
@MainActor
@Suite("System extra stand-in identity")
struct SystemExtraStandInIdentityTests {
    /// The autosave names ExtraRole in ThawExtraHelper gives each helper's item.
    @Test("Each stand-in's layout identifier is its bundle followed by the helper's autosave name", arguments: [
        (SystemExtraStandIn.focus, "Thaw.Extra.Focus"),
        (.timeMachine, "Thaw.Extra.TimeMachine"),
        (.timer, "Thaw.Extra.Timer"),
        (.airDrop, "Thaw.Extra.AirDrop"),
        (.nowPlaying, "Thaw.Extra.NowPlaying"),
        (.userSwitcher, "Thaw.Extra.UserSwitcher"),
        (.textInput, "Thaw.Extra.TextInput"),
    ])
    func itemIdentifier(standIn: SystemExtraStandIn, autosaveName: String) {
        #expect(standIn.itemIdentifier == "\(standIn.bundleIdentifier):\(autosaveName)")
    }

    @Test("Each takeover item is replaced by the stand-in of the same name", arguments: [
        (SystemExtraItem.timeMachine, SystemExtraStandIn.timeMachine),
        (.timer, .timer),
        (.textInput, .textInput),
    ])
    func standInForItem(item: SystemExtraItem, standIn: SystemExtraStandIn) {
        #expect(SystemExtraStandIn(item) == standIn)
    }
}
