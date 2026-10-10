//
//  StatusIconCompositionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Status icon composition")
struct StatusIconCompositionTests {
    @Test("The initial combination matches the reference's three slots")
    func initialComposition() {
        let composition = StatusIconComposition()
        #expect(composition.outer == .arc)
        #expect(composition.outerSource == .battery)
        #expect(composition.center == .wifi)
        #expect(composition.bottom == .dots)
        #expect(composition.bottomSource == .wifi)
        #expect(!composition.isEmpty)
    }

    @Test("Each slot can stand alone, or all three can be hidden")
    func optionalSlots() {
        var composition = StatusIconComposition(outer: .none, center: .none, bottom: .none)
        #expect(composition.isEmpty)
        composition.outer = .ring
        #expect(!composition.isEmpty)
        composition.outer = .none
        composition.center = .moon
        #expect(!composition.isEmpty)
        composition.center = .none
        composition.bottom = .bars
        #expect(!composition.isEmpty)
    }

    @Test("A reading can drive either indicator without coupling their sources")
    func independentSources() {
        var composition = StatusIconComposition()
        composition.outerSource = .volume
        composition.bottomSource = .cpu
        var samples = StatusIconSamples()
        samples[.volume] = 0.9
        samples[.cpu] = 0.1
        #expect(samples[composition.outerSource] == 0.9)
        #expect(samples.litSegments(for: composition.bottomSource) == 1)
        #expect(samples[.battery] == 0.75)
        composition.bottomSource = .volume
        #expect(samples.litSegments(for: composition.bottomSource) == 4)
    }

    @Test("Only visible indicators request sample controls, without duplicates")
    func activeSources() {
        var composition = StatusIconComposition()
        #expect(composition.activeSources == [.battery, .wifi])
        composition.bottomSource = .battery
        #expect(composition.activeSources == [.battery])
        composition.outer = .none
        #expect(composition.activeSources == [.battery])
        composition.bottom = .none
        #expect(composition.activeSources.isEmpty)
        #expect(!composition.isEmpty, "The fixed center symbol needs no reading")
    }

    @Test("Readings are bounded before drawing", arguments: StatusIconComposition.Source.allCases)
    func boundedReadings(source: StatusIconComposition.Source) {
        var samples = StatusIconSamples()
        for (input, expected) in [(-1.0, 0.0), (2.0, 1.0), (.nan, 0.0), (.infinity, 0.0)] {
            samples[source] = input
            #expect(samples[source] == expected)
        }
    }

    @Test("Segments include empty, partial, and full readings")
    func segmentThresholds() {
        var samples = StatusIconSamples()
        for (input, expected) in [(0.0, 0), (0.01, 1), (0.25, 1), (0.26, 2), (0.5, 2), (0.75, 3), (1.0, 4)] {
            samples[.battery] = input
            #expect(samples.litSegments(for: .battery) == expected)
        }
    }
}
