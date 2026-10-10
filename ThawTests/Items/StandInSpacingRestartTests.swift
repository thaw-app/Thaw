//
//  StandInSpacingRestartTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Stand-ins and the spacing relaunch wave")
struct StandInSpacingRestartTests {
    @Test("Every stand-in bundle is recognised as this app's own", arguments: SystemExtraStandIn.allCases)
    func standInIsOwned(standIn: SystemExtraStandIn) {
        #expect(SystemExtraStandIn.owns(bundleIdentifier: standIn.bundleIdentifier))
    }

    @Test("Other apps, the app itself and a missing identifier are not stand-ins")
    func othersAreNotOwned() {
        let parent = "com.example.Thaw"
        #expect(!SystemExtraStandIn.owns(bundleIdentifier: nil, parent: parent))
        #expect(!SystemExtraStandIn.owns(bundleIdentifier: parent, parent: parent))
        #expect(!SystemExtraStandIn.owns(bundleIdentifier: "org.herf.Flux", parent: parent))
        #expect(!SystemExtraStandIn.owns(bundleIdentifier: "\(parent).extra.unknown", parent: parent))
        #expect(SystemExtraStandIn.owns(bundleIdentifier: "\(parent).extra.timemachine", parent: parent))
    }
}
