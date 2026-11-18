//
//  MenuBarContainerTintTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers how a MenuBarContainerTint mixes into the background when it is
/// drawn behind the content, as the Thaw Bar's own tint is. An opaque tint
/// must recolor the background and flip the light/dark decision, and must
/// never leave the sampled color in charge of it.
@Suite("Menu bar container tint")
@MainActor
struct MenuBarContainerTintTests {
    private let beige = CGColor(srgbRed: 0.86, green: 0.83, blue: 0.78, alpha: 1)
    private let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    private func makeTint(
        _ kind: MenuBarTintKind,
        gradient: IceGradient = IceGradient(stops: []),
        opacity: Double,
        isBehindContent: Bool = true
    ) -> MenuBarContainerTint {
        MenuBarContainerTint(
            kind: kind,
            color: .black,
            gradient: gradient,
            opacity: opacity,
            isBehindContent: isBehindContent
        )
    }

    private func rgbComponents(_ color: CGColor) -> [CGFloat] {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return []
        }
        let converted = color.converted(to: space, intent: .defaultIntent, options: nil)
        return Array((converted?.components ?? []).prefix(3))
    }

    @Test("An opaque black tint turns a bright background black")
    func opaqueTintReplacesBackground() {
        let components = rgbComponents(makeTint(.solid, opacity: 1).composited(over: beige))

        #expect(components.count == 3)
        #expect(components.allSatisfy { abs($0) < 0.001 })
    }

    @Test("A half-opaque tint mixes halfway into the background")
    func halfOpaqueTintMixesHalfway() {
        let components = rgbComponents(makeTint(.solid, opacity: 0.5).composited(over: white))

        #expect(components.count == 3)
        #expect(components.allSatisfy { abs($0 - 0.5) < 0.001 })
    }

    @Test("A gradient tint mixes in its average color")
    func gradientTintUsesItsAverage() {
        let gradient = IceGradient(stops: [.black(location: 0), .black(location: 1)])
        let components = rgbComponents(makeTint(.gradient, gradient: gradient, opacity: 1).composited(over: white))

        #expect(components.count == 3)
        #expect(components.allSatisfy { abs($0) < 0.001 })
    }

    @Test(
        "Tints that draw no color leave the background as it is",
        arguments: [MenuBarTintKind.noTint, .glass, .adaptive, .adaptiveGradient]
    )
    func colorlessTintKeepsBackground(kind: MenuBarTintKind) {
        #expect(makeTint(kind, opacity: 1).composited(over: beige) == beige)
    }

    @Test("A tint behind the content makes a bright sample read as dark")
    func behindTintDecidesBrightness() {
        let sampled = MenuBarAverageColorInfo(color: beige, source: .menuBarWindow)
        let background = makeTint(.solid, opacity: 1).backgroundColorInfo(over: sampled)

        #expect(sampled.isBright)
        #expect(background?.isBright == false)
    }

    @Test("A tint over the content leaves the sampled color in charge")
    func overTintKeepsSampledColor() {
        let sampled = MenuBarAverageColorInfo(color: beige, source: .menuBarWindow)

        #expect(makeTint(.solid, opacity: 1, isBehindContent: false).backgroundColorInfo(over: sampled) == sampled)
    }

    @Test("Without a sampled color there is nothing to mix into")
    func missingSampleStaysMissing() {
        #expect(makeTint(.solid, opacity: 1).backgroundColorInfo(over: nil) == nil)
    }
}
