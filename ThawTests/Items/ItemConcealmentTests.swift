//
//  ItemConcealmentTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The concealment sets hold canonical keys, so a raw identifier must be canonicalized before the lookup.
@Suite("Item concealment")
struct ItemConcealmentTests {
    private let bundle = "com.bjango.istatmenus-setapp.status"

    @Test("An item whose title ticks is found under its canonical key")
    func dynamicTitleMatchesCanonicalKey() {
        let concealed: Set = ["\(bundle):CPU #%"]
        #expect(ItemConcealment.isConcealed("\(bundle):CPU 42%", in: concealed))
        #expect(ItemConcealment.isConcealed("\(bundle):CPU 43%", in: concealed))
    }

    @Test("An item outside the set is not concealed")
    func otherItemIsNotConcealed() {
        let concealed: Set = ["\(bundle):CPU #%"]
        #expect(!ItemConcealment.isConcealed("com.example.App:Item-0", in: concealed))
        #expect(!ItemConcealment.isConcealed("\(bundle):CPU 42%", in: []))
    }

    @Test("A plain identifier matches itself")
    func plainIdentifierMatches() {
        #expect(ItemConcealment.isConcealed("com.example.App:Item-0", in: ["com.example.App:Item-0"]))
    }
}
