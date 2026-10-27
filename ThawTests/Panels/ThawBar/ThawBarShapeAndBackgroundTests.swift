//
//  ThawBarShapeAndBackgroundTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// The Thaw Bar's layout and location names, its border shape and every background and tint fill.
@MainActor
@Suite("Thaw Bar shape and background")
struct ThawBarShapeAndBackgroundTests {
    // MARK: Layout and location

    @Test("Layouts parse from their names and raw values, and each has its own symbol")
    func layoutParsing() {
        for layout in ThawBarLayout.allCases {
            #expect(ThawBarLayout.fromString(String(describing: layout)) == layout)
            #expect(ThawBarLayout.fromString(String(layout.rawValue)) == layout)
            #expect(layout.id == layout.rawValue)
        }
        #expect(ThawBarLayout.fromString("diagonal") == nil)
        #expect(Set(ThawBarLayout.allCases.map(\.systemImage)).count == 3)
        #expect(Set(ThawBarLayout.allCases.map { "\($0.localized)" }).count == 3)
    }

    @Test("Locations parse from their names, raw values and the Ice-era spelling")
    func locationParsing() {
        for location in ThawBarLocation.allCases {
            #expect(ThawBarLocation.fromString(String(describing: location)) == location)
            #expect(ThawBarLocation.fromString(String(location.rawValue)) == location)
            #expect(location.id == location.rawValue)
        }
        #expect(ThawBarLocation.fromString("iceIcon") == .thawIcon)
        #expect(ThawBarLocation.fromString("center") == nil)
        #expect(Set(ThawBarLocation.allCases.map { "\($0.localized)" }).count == ThawBarLocation.allCases.count)
    }

    // MARK: Border shape

    private func points(_ path: Path) -> [CGPoint] {
        var points = [CGPoint]()
        // swiftformat:disable:next preferForLoop
        path.forEach { element in
            switch element {
            case let .move(to: point), let .line(to: point):
                points.append(point)
            case let .quadCurve(to: point, control: _), let .curve(to: point, control1: _, control2: _):
                points.append(point)
            case .closeSubpath:
                break
            }
        }
        return points
    }

    private func isClosed(_ path: Path) -> Bool {
        var closed = false
        // swiftformat:disable:next preferForLoop
        path.forEach { element in
            if case .closeSubpath = element {
                closed = true
            }
        }
        return closed
    }

    /// The runs of an outline that lie along its top edge between the corners.
    private func topEdgeRuns(_ path: Path, top: CGFloat) -> [(CGPoint, CGPoint)] {
        let drawn = points(path)
        return zip(drawn, drawn.dropFirst()).filter { abs($0.y - top) < 0.01 && abs($1.y - top) < 0.01 && abs($0.x - $1.x) > 20 }
    }

    @Test("A square-cornered border leaves the top edge open and starts at the top-leading corner")
    func squareBorderOpensTop() throws {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 48)
        let border = ThawBarBorderShape.thawBarBorder(height: 48, hasRoundedShape: false, borderWidth: 2)
        #expect(border.omitTopEdge)
        #expect(border.insetAmount == 1)
        let path = border.path(in: rect)
        let drawn = points(path)
        let first = try #require(drawn.first)
        let last = try #require(drawn.last)
        #expect(abs(first.y - 1) < 0.01, "the stroke starts on the top edge")
        #expect(first.x < rect.midX)
        #expect(abs(last.y - 1) < 0.01, "and ends on it")
        #expect(last.x > rect.midX)
        #expect(topEdgeRuns(path, top: 1).isEmpty)
        #expect(drawn.contains { abs($0.y - 47) < 0.01 }, "the bottom edge is drawn")
        #expect(!isClosed(path), "the outline is left open")
    }

    @Test("A menu-bar-height square border still opens its top edge")
    func shortSquareBorderOpensTop() {
        // At 24 points the corner curve starts inside isTopEdge's 0.5 point tolerance,
        // so it is dropped with the top edge and the real top edge is drawn.
        let border = ThawBarBorderShape.thawBarBorder(height: 24, hasRoundedShape: false, borderWidth: 2)
        let path = border.path(in: CGRect(x: 0, y: 0, width: 120, height: 24))
        withKnownIssue("isTopEdge mistakes a small continuous corner for the top edge") {
            #expect(topEdgeRuns(path, top: 1).isEmpty)
        }
    }

    @Test("A rounded border keeps its outline closed and its corners circular")
    func roundedBorderStaysClosed() {
        let border = ThawBarBorderShape.thawBarBorder(height: 24, hasRoundedShape: true, borderWidth: 2)
        #expect(!border.omitTopEdge)
        #expect(border.cornerStyle == .circular)
        let path = border.path(in: CGRect(x: 0, y: 0, width: 120, height: 24))
        #expect(isClosed(path))
    }

    @Test("A zero-radius open border still drops only the top edge")
    func zeroRadiusOpenBorder() throws {
        let shape = ThawBarBorderShape(cornerRadius: 0, omitTopEdge: true)
        let rect = CGRect(x: 0, y: 0, width: 50, height: 20)
        let drawn = points(shape.path(in: rect))
        let first = try #require(drawn.first)
        #expect(first.y == rect.minY)
        #expect(drawn.contains { $0.y == rect.maxY }, "the bottom edge is still drawn")
        #expect(shape.path(in: .zero).isEmpty || points(shape.path(in: .zero)).allSatisfy { $0 == .zero })
    }

    // MARK: Background

    private func appearance(
        background: MenuBarBackgroundKind,
        tint: MenuBarTintKind,
        glass: MenuBarGlassStyle = .regular,
        border: Bool = false
    ) -> ResolvedThawBarAppearance {
        var fill = MenuBarAppearancePartialConfiguration.defaultConfiguration
        fill.backgroundKind = background
        fill.tintKind = tint
        fill.backgroundOpacity = 0.8
        fill.tintOpacity = 0.6
        fill.backgroundColor = CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)
        fill.tintColor = CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
        fill.backgroundGlassStyle = glass
        fill.tintGlassStyle = glass
        fill.backgroundHasBorder = border
        return ResolvedThawBarAppearance(hasRoundedShape: true, fillConfiguration: fill)
    }

    private func render(_ appearance: ResolvedThawBarAppearance, palette: WallpaperPalette? = nil) throws -> Data {
        let size = CGSize(width: 120, height: 30)
        let view = ThawBarAppearanceBackground(
            appearance: appearance,
            sampledColor: CGColor(gray: 0.3, alpha: 1),
            adaptiveColor: CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1),
            palette: palette,
            shape: .thawBarClip(height: size.height, hasRoundedShape: true)
        )
        .frame(width: size.width, height: size.height)
        return try OffscreenRender(view, size: size).pixels()
    }

    @Test("Each background kind fills differently")
    func backgroundKinds() throws {
        let kinds: [MenuBarBackgroundKind] = [.none, .solid, .gradient, .adaptive]
        let drawn = try kinds.map { try render(appearance(background: $0, tint: .noTint)) }
        #expect(Set(drawn).count == kinds.count)
    }

    @Test("Each tint kind draws over the background, and an adaptive gradient uses the wallpaper palette")
    func tintKinds() throws {
        let kinds: [MenuBarTintKind] = [.noTint, .solid, .gradient, .adaptive, .adaptiveGradient]
        let drawn = try kinds.map { try render(appearance(background: .none, tint: $0)) }
        #expect(Set(drawn).count >= 4)

        let palette = WallpaperPalette(swatches: [
            .init(red: 1, green: 0, blue: 0, weight: 0.6),
            .init(red: 0, green: 0, blue: 1, weight: 0.4),
        ])
        let withPalette = try render(appearance(background: .none, tint: .adaptiveGradient), palette: palette)
        #expect(withPalette != drawn[4], "the palette replaces the plain adaptive colour")
    }

    @Test("Glass backgrounds and tints lay out in both glass styles, and a border is stroked")
    func glassAndBorder() throws {
        for style in [MenuBarGlassStyle.regular, .liquid] {
            #expect(try !render(appearance(background: .glass, tint: .noTint, glass: style)).isEmpty)
            #expect(try !render(appearance(background: .none, tint: .glass, glass: style)).isEmpty)
        }
        let plain = try render(appearance(background: .solid, tint: .noTint))
        let bordered = try render(appearance(background: .solid, tint: .noTint, border: true))
        #expect(plain != bordered)
    }
}
