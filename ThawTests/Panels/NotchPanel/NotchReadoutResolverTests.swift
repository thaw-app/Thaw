//
//  NotchReadoutResolverTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Notch readout resolver")
struct NotchReadoutResolverTests {
    @Test("A readout that only repeats the item's name is thrown away")
    func nameOnly() {
        let readout = NotchReadoutResolver.resolve(
            candidates: ["Philips Hue", "Open Philips Hue", "Hue menu bar item"],
            names: ["Philips Hue", "com.philips.hue"]
        )
        #expect(readout == nil)
    }

    @Test("A name label at the start is stripped and the state kept")
    func labelStripped() {
        let readout = NotchReadoutResolver.resolve(candidates: ["Garage: Open"], names: ["Garage"])
        #expect(readout == nil, "Open alone is boilerplate")

        let state = NotchReadoutResolver.resolve(candidates: ["Weather: 78° Cloudy"], names: ["Weather"])
        #expect(state == NotchItemReadout(primary: "78° Cloudy", secondary: nil))
    }

    @Test("A sentence that starts with the name keeps its subject")
    func sentenceSubjectKept() {
        let readout = NotchReadoutResolver.resolve(
            candidates: ["Amphetamine is active for 2 hours"],
            names: ["Amphetamine"]
        )
        #expect(readout?.primary == "Amphetamine is active for 2 hours")
    }

    @Test("Trailing names are trimmed")
    func trailingNameTrimmed() {
        let readout = NotchReadoutResolver.resolve(candidates: ["Battery 80% - Coconut"], names: ["Coconut"])
        #expect(readout?.primary == "Battery 80%")
    }

    @Test("A second line is kept only when it adds new meaning")
    func secondaryLine() {
        let overlapping = NotchReadoutResolver.resolve(
            candidates: ["78 Cloudy", "Cloudy in San Diego", "Wind 5 mph"],
            names: ["Weather"]
        )
        #expect(overlapping == NotchItemReadout(primary: "78 Cloudy", secondary: "Wind 5 mph"))
    }

    @Test("Short, empty and missing candidates are skipped")
    func shortCandidates() {
        let readout = NotchReadoutResolver.resolve(candidates: [nil, "", "ok", "  ", "Connected to Home"], names: [nil])
        #expect(readout?.primary == "Connected to Home")
        #expect(readout?.secondary == nil)
    }

    @Test("Case and diacritics do not hide a repeated name")
    func foldedNames() {
        let readout = NotchReadoutResolver.resolve(candidates: ["CAFÉ", "café status icon"], names: ["Cafe"])
        #expect(readout == nil)
    }

    @Test("Separator-only leading words are dropped with the name")
    func separatorsDropped() {
        let readout = NotchReadoutResolver.resolve(candidates: ["Timer — 12 minutes left"], names: ["Timer"])
        #expect(readout?.primary == "12 minutes left")
    }
}
