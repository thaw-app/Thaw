//
//  ControlItemImageSetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Control item image set identity")
struct ControlItemImageSetTests {
    @Test("The identifier is the hash of the whole set, not just its name")
    func idIsTheHashValue() {
        let set = ControlItemImageSet.defaultIceIcon
        #expect(set.id == set.hashValue)
    }

    @Test("Two sets that differ only in their images get different identifiers")
    func differingImagesGetDifferentIdentifiers() {
        let first = ControlItemImageSet(name: .dot, image: .catalog("DotFill"))
        let second = ControlItemImageSet(name: .dot, image: .catalog("DotStroke"))
        #expect(first.id != second.id)
    }

    @Test("Two identical sets share an identifier")
    func identicalSetsShareAnIdentifier() {
        let first = ControlItemImageSet(name: .dot, image: .catalog("DotFill"))
        let second = ControlItemImageSet(name: .dot, hidden: .catalog("DotFill"), visible: .catalog("DotFill"))
        #expect(first == second)
        #expect(first.id == second.id)
    }
}
