//
//  KnownIdentitySeedingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Known identity seeding")
struct KnownIdentitySeedingTests {
    @Test("A known window's corrected identity is learned")
    func correctedIdentityIsLearned() {
        let learned = KnownIdentitySeeding.learned(
            current: [.init(windowID: 7, identifier: "com.example.app:Item-0", hasSourcePID: true)],
            previousIdentifiers: [7: "com.apple.controlcenter:Item-0"],
            known: ["com.apple.controlcenter:Item-0"]
        )
        #expect(learned == ["com.example.app:Item-0"])
    }

    @Test("A window only seen on the last pass stays new until something places it")
    func seenButUnknownStaysNew() {
        let learned = KnownIdentitySeeding.learned(
            current: [.init(windowID: 9, identifier: "dev.orca:Item-0", hasSourcePID: true)],
            previousIdentifiers: [9: "dev.orca:Item-0"],
            known: []
        )
        #expect(learned.isEmpty)
    }

    @Test("Unresolved owners and windows that weren't there are never learned")
    func unresolvedAndNewWindows() {
        let learned = KnownIdentitySeeding.learned(
            current: [
                .init(windowID: 7, identifier: "com.apple.controlcenter:Item-0", hasSourcePID: false),
                .init(windowID: 8, identifier: "com.example.other:Item-0", hasSourcePID: true),
            ],
            previousIdentifiers: [7: "com.example.app:Item-0"],
            known: ["com.example.app:Item-0"]
        )
        #expect(learned.isEmpty)
    }
}
