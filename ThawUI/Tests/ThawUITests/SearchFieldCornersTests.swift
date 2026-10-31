//
//  SearchFieldCornersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import ThawUI

struct SearchFieldCornersTests {
    /// The settings preview's piece, which draws a field's corners, and the field in the launcher's panel.
    private static let outlineHeights: [CGFloat] = [34, 44]
    /// The field as its own piece.
    private static let pieceHeight: CGFloat = 67

    /// What SearchFieldShape drew before the slider, written out so these do not follow a later change.
    private static func outlineRadius(_ shape: SearchFieldShape, height: CGFloat) -> CGFloat {
        switch shape {
        case .rounded: 12
        case .capsule: height / 2
        case .square: 0
        }
    }

    private static func fieldPieceRadius(_ shape: SearchFieldShape, height: CGFloat) -> CGFloat {
        switch shape {
        case .rounded: 24
        case .capsule: height / 2
        case .square: 0
        }
    }

    private static func panelPieceRadius(_ shape: SearchFieldShape) -> CGFloat {
        shape == .square ? 0 : 24
    }

    @Test(arguments: SearchFieldShape.allCases)
    func eachOldShapeKeepsItsRadiiInBothLayouts(shape: SearchFieldShape) {
        let corners = SearchFieldCorners(shape)
        for height in Self.outlineHeights + [Self.pieceHeight] {
            #expect(corners.cornerRadius(height: height) == Self.outlineRadius(shape, height: height))
            #expect(shape.cornerRadius(height: height) == Self.outlineRadius(shape, height: height))
        }
        #expect(corners.fieldPieceRadius(height: Self.pieceHeight) == Self.fieldPieceRadius(shape, height: Self.pieceHeight))
        #expect(shape.fieldPieceRadius(height: Self.pieceHeight) == Self.fieldPieceRadius(shape, height: Self.pieceHeight))
        #expect(corners.panelPieceRadius == Self.panelPieceRadius(shape))
        #expect(shape.panelPieceRadius == Self.panelPieceRadius(shape))
        #expect(corners.pieceCornerStyle == (shape == .capsule ? .circular : .continuous))
        #expect(shape.pieceCornerStyle == corners.pieceCornerStyle)
    }

    @Test func theOldShapesSitAtTheEndsAndTheMiddleOfTheSlider() {
        #expect(SearchFieldCorners(.square).roundness == 0)
        #expect(SearchFieldCorners(.rounded).roundness == 0.5)
        #expect(SearchFieldCorners(.capsule).roundness == 1)
        #expect(SearchFieldCorners.rounded == SearchFieldCorners(.rounded))
    }

    @Test(arguments: [
        (0.0, SearchFieldShape.square), (0.24, .square),
        (0.25, .rounded), (0.5, .rounded), (0.74, .rounded),
        (0.75, .capsule), (1.0, .capsule),
    ] as [(Double, SearchFieldShape)])
    func eachRoundnessHasANearestOldShape(roundness: Double, shape: SearchFieldShape) {
        #expect(SearchFieldCorners(roundness: roundness).nearestShape == shape)
    }

    @Test(arguments: SearchFieldShape.allCases)
    func anOldShapeIsItsOwnNearest(shape: SearchFieldShape) {
        #expect(SearchFieldCorners(shape).nearestShape == shape)
    }

    @Test func roundnessStaysOnTheSlider() {
        #expect(SearchFieldCorners(roundness: -1).roundness == 0)
        #expect(SearchFieldCorners(roundness: 3).roundness == 1)
        var corners = SearchFieldCorners.rounded
        corners.roundness = 2
        #expect(corners.roundness == 1)
    }

    @Test func radiiGrowAlongTheSlider() {
        let positions = stride(from: 0.0, through: 1.0, by: 0.05).map { SearchFieldCorners(roundness: $0) }
        var series = Self.outlineHeights.map { height in positions.map { $0.cornerRadius(height: height) } }
        series.append(positions.map { $0.fieldPieceRadius(height: Self.pieceHeight) })
        series.append(positions.map(\.panelPieceRadius))
        for radii in series {
            #expect(zip(radii, radii.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }

    @Test func aRoundnessIsStoredAsAPlainNumberAndClampedWhenRead() throws {
        let data = try JSONEncoder().encode(SearchFieldCorners(roundness: 0.35))
        #expect(String(bytes: data, encoding: .utf8) == "0.35")
        #expect(try JSONDecoder().decode(SearchFieldCorners.self, from: data).roundness == 0.35)
        #expect(try JSONDecoder().decode(SearchFieldCorners.self, from: Data("7".utf8)).roundness == 1)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SearchFieldCorners.self, from: Data("\"capsule\"".utf8))
        }
    }

    @Test func theOutlineFillsItsRectAndInsets() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 44)
        for roundness in [0, 0.3, 0.5, 0.8, 1] {
            let outline = SearchFieldCorners(roundness: roundness).outline
            #expect(outline.path(in: rect).boundingRect == rect)
            #expect(outline.inset(by: 2).path(in: rect).boundingRect == rect.insetBy(dx: 2, dy: 2))
        }
    }

    @Test(arguments: SearchFieldShape.allCases)
    func theOldShapesOutlineIsTheCornersOutline(shape: SearchFieldShape) {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 44)
        #expect(shape.outline.shape == shape)
        #expect(shape.outline.path(in: rect) == SearchFieldCorners(shape).outline.path(in: rect))
    }

    @Test func theEnvironmentsTwoNamesAreOneValue() {
        var environment = EnvironmentValues()
        #expect(environment.searchFieldCorners == .rounded)
        environment.searchFieldShape = .capsule
        #expect(environment.searchFieldCorners == .capsule)
        environment.searchFieldCorners = SearchFieldCorners(roundness: 0.1)
        #expect(environment.searchFieldShape == .square)
    }

    /// Points along an outline, curves walked in small steps.
    private static func points(along path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        func add(_ point: CGPoint) {
            if let last = points.last, hypot(last.x - point.x, last.y - point.y) < 0.01 {
                return
            }
            points.append(point)
        }
        func addCurve(to end: CGPoint, _ first: CGPoint, _ second: CGPoint) {
            for step in 1 ... 100 {
                let t = CGFloat(step) / 100
                let weights = [pow(1 - t, 3), 3 * pow(1 - t, 2) * t, 3 * (1 - t) * t * t, t * t * t]
                let knots = [current, first, second, end]
                let x = zip(weights, knots).reduce(CGFloat(0)) { $0 + $1.0 * $1.1.x }
                let y = zip(weights, knots).reduce(CGFloat(0)) { $0 + $1.0 * $1.1.y }
                add(CGPoint(x: x, y: y))
            }
        }
        // swiftformat:disable:next preferForLoop
        path.forEach { element in
            switch element {
            case let .move(to), let .line(to):
                add(to)
                current = to
            case let .curve(to, first, second):
                addCurve(to: to, first, second)
                current = to
            case let .quadCurve(to, control):
                let first = CGPoint(x: current.x + (control.x - current.x) * 2 / 3, y: current.y + (control.y - current.y) * 2 / 3)
                let second = CGPoint(x: to.x + (control.x - to.x) * 2 / 3, y: to.y + (control.y - to.y) * 2 / 3)
                addCurve(to: to, first, second)
                current = to
            case .closeSubpath:
                break
            }
        }
        return points
    }

    /// The largest step backwards along an outline, in degrees. A smooth convex outline only ever turns one way, so
    /// anything above zero is the nick a continuous corner leaves once it is close to half the height.
    private static func nick(in path: Path) -> Double {
        let points = points(along: path)
        let directions = zip(points, points.dropFirst()).map { atan2($1.y - $0.y, $1.x - $0.x) }
        let turns = zip(directions, directions.dropFirst()).map { previous, next -> CGFloat in
            var turn = next - previous
            while turn > .pi {
                turn -= 2 * .pi
            }
            while turn < -.pi {
                turn += 2 * .pi
            }
            return turn
        }
        let way: CGFloat = turns.reduce(0, +) >= 0 ? 1 : -1
        return Double(turns.map { -$0 * way }.max() ?? 0) * 180 / .pi
    }

    @Test func aContinuousCornerAtHalfTheHeightDoesLeaveANick() {
        let rect = CGRect(x: 0, y: 0, width: 600, height: 67)
        #expect(Self.nick(in: Path(roundedRect: rect, cornerRadius: 33.5, style: .continuous)) > 0.5)
        #expect(Self.nick(in: Path(roundedRect: rect, cornerRadius: 33.5, style: .circular)) < 0.1)
    }

    @Test func noPositionOfTheSliderLeavesANick() {
        for roundness in stride(from: 0.0, through: 1.0, by: 0.01) {
            let corners = SearchFieldCorners(roundness: roundness)
            for height in Self.outlineHeights {
                let rect = CGRect(x: 0, y: 0, width: 600, height: height)
                #expect(Self.nick(in: corners.outline.path(in: rect)) < 0.1, "outline, height \(height), roundness \(roundness)")
            }
            let rect = CGRect(x: 0, y: 0, width: 600, height: Self.pieceHeight)
            let piece = Path(roundedRect: rect, cornerRadius: corners.fieldPieceRadius(height: Self.pieceHeight), style: corners.pieceCornerStyle)
            #expect(Self.nick(in: piece) < 0.1, "piece, roundness \(roundness)")
        }
    }
}
