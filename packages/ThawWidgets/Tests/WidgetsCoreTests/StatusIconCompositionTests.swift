//
//  StatusIconCompositionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import WidgetsCore

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

/// The icon's proportions, measured from the combined status indicator.
@Suite("Status icon geometry")
struct StatusIconGeometryTests {
    private let side: CGFloat = 22

    @Test("The arc fills the icon, and the dots sit on its circle inside the opening")
    func arcProportions() {
        let layout = StatusIconGeometry(side: side, outer: .arc, style: StatusIconStyle(size: .large, thickness: .regular))
        let diameter = 2 * layout.radius + layout.lineWidth
        #expect(diameter > side * 0.9, "the ring is nearly as tall as the icon")
        #expect(abs(layout.lineWidth / diameter - 0.057) < 0.0001)
        #expect(abs(layout.glyphSize.width / diameter - 0.44) < 0.0001)
        #expect(layout.dots.count == 4)
        for dot in layout.dots {
            let distance = hypot(dot.x - layout.center.x, dot.y - layout.center.y)
            #expect(abs(distance - layout.radius) < 0.001, "on the ring's circle")
            let angle = atan2(dot.y - layout.center.y, dot.x - layout.center.x) * 180 / .pi
            #expect(abs(angle - 90) < StatusIconGeometry.arcGapDegrees / 2, "inside the opening")
        }
        #expect(layout.dots.map(\.x) == layout.dots.map(\.x).sorted(), "left to right")
    }

    @Test("Every size, thickness and layout stays inside the icon")
    func staysInside() {
        for outer in StatusIconComposition.Outer.allCases {
            for size in StatusIconStyle.Size.allCases {
                for thickness in StatusIconStyle.Thickness.allCases {
                    let layout = StatusIconGeometry(side: side, outer: outer, style: StatusIconStyle(size: size, thickness: thickness))
                    let ringReach = layout.radius + layout.lineWidth / 2
                    #expect(layout.center.y - ringReach >= -0.001, "top")
                    #expect(layout.center.x - ringReach >= -0.001 && layout.center.x + ringReach <= side + 0.001, "sides")
                    for dot in layout.dots {
                        #expect(dot.y + layout.dotDiameter / 2 <= side + 0.001, "bottom row")
                    }
                }
            }
        }
    }

    @Test("A closed ring leaves room for the row under it, and no ring gives the symbol more room")
    func ringAndNone() {
        let style = StatusIconStyle()
        let ring = StatusIconGeometry(side: side, outer: .ring, style: style)
        #expect(ring.dots.allSatisfy { $0.y > ring.center.y + ring.radius })
        let none = StatusIconGeometry(side: side, outer: .none, style: style)
        #expect(none.glyphSize.width > ring.glyphSize.width)
    }
}
