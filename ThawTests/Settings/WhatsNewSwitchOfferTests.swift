//
//  WhatsNewSwitchOfferTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("What's New switch offer")
struct WhatsNewSwitchOfferTests {
    private typealias Candidate = WhatsNewSwitchOffer.Candidate

    @Test("This release's switches come first, even when already on")
    func newSwitchesFirst() {
        let offered = WhatsNewSwitchOffer.offered([
            Candidate(id: "old", since: "1.0", isOn: false),
            Candidate(id: "new", since: "2.0", isOn: true),
        ], release: "2.0")
        #expect(offered == ["new", "old"])
    }

    @Test("Older switches that are on are left out")
    func olderOnIsSkipped() {
        let offered = WhatsNewSwitchOffer.offered([
            Candidate(id: "on", since: "1.0", isOn: true),
            Candidate(id: "off", since: "1.0", isOn: false),
        ], release: "2.0")
        #expect(offered == ["off"])
    }

    @Test("Nothing is offered when every older switch is on")
    func nothingToOffer() {
        #expect(WhatsNewSwitchOffer.offered([Candidate(id: "on", since: "1.0", isOn: true)], release: "2.0").isEmpty)
    }

    @MainActor
    @Test("Every catalog entry has a unique id")
    func catalogIdsAreUnique() {
        let ids = WhatsNewSwitch.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
