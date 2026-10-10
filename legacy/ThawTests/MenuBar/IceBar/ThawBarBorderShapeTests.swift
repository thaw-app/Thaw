//
//  ThawBarBorderShapeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

/// Covers the geometry the Thaw Bar's clip and border share, and the path
/// surgery that opens the top edge on square corners (#325).
///
/// `path(in:)` introspects a closed `UnevenRoundedRectangle` path, so it
/// depends on how SwiftUI emits it: the starting element, and whether the
/// top corners land exactly on `minY`. A change there shows up as a stray
/// line across the bar.
@Suite("Thaw Bar border shape")
struct ThawBarBorderShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 30)

    // MARK: - Closed outline

    /// Rounded ends stroke all four edges, so the path stays a plain closed
    /// rounded rectangle.
    @Test("Keeping the top edge leaves a closed outline")
    func keepingTopEdgeStaysClosed() {
        let outline = Outline(
            ThawBarBorderShape(cornerRadius: 15, cornerStyle: .circular, omitTopEdge: false)
                .path(in: rect)
        )
        #expect(outline.isClosed)
        #expect(outline.boundingRect.isNear(rect))
        #expect(outline.hasTopEdge(of: rect))
    }

    // MARK: - Open outline

    /// The remaining segments are walked as one chain, so a dropped edge in
    /// the middle of the traversal would be drawn straight back in.
    @Test("Omitting the top edge leaves no segment along the top", arguments: [
        RoundedCornerStyle.continuous, .circular,
    ])
    func omittingTopEdgeRemovesIt(style: RoundedCornerStyle) {
        let outline = Outline(
            ThawBarBorderShape(cornerRadius: 7.5, cornerStyle: style, omitTopEdge: true)
                .path(in: rect)
        )
        #expect(!outline.isClosed)
        #expect(!outline.hasTopEdge(of: rect))
    }

    /// The open ends sit on the two top corners, so the stroke runs down the
    /// leading side, across the bottom, and back up the trailing side.
    @Test("The open ends are the two top corners")
    func openEndsAreTopCorners() {
        let outline = Outline(
            ThawBarBorderShape(cornerRadius: 7.5, cornerStyle: .continuous, omitTopEdge: true)
                .path(in: rect)
        )
        let ends = [outline.start, outline.end].sorted { $0.x < $1.x }
        #expect(ends.count == 2)
        #expect(ends[0].isNear(CGPoint(x: rect.minX, y: rect.minY)))
        #expect(ends[1].isNear(CGPoint(x: rect.maxX, y: rect.minY)))
        #expect(outline.boundingRect.isNear(rect))
    }

    // MARK: - Degenerate radii

    /// A zero radius takes the hand-built three-edge fallback rather than the
    /// path-surgery branch.
    @Test("A zero radius draws three straight edges")
    func zeroRadiusDrawsThreeEdges() {
        let outline = Outline(
            ThawBarBorderShape(cornerRadius: 0, omitTopEdge: true).path(in: rect)
        )
        #expect(outline.segments.count == 3)
        #expect(outline.curveCount == 0)
        #expect(!outline.isClosed)
        #expect(outline.start.isNear(CGPoint(x: rect.minX, y: rect.minY)))
        #expect(outline.end.isNear(CGPoint(x: rect.maxX, y: rect.minY)))
    }

    /// An inset deeper than the radius must clamp to zero rather than produce
    /// a negative radius.
    @Test("An inset past the radius degenerates to straight edges")
    func insetPastRadiusDegenerates() {
        let shape = ThawBarBorderShape(cornerRadius: 4, omitTopEdge: true).inset(by: 6)
        let outline = Outline(shape.path(in: rect))
        #expect(outline.curveCount == 0)
        #expect(outline.boundingRect.isNear(rect.insetBy(dx: 6, dy: 6)))
    }

    /// A radius larger than the rect can hold is clamped, so the path never
    /// escapes its bounds.
    @Test("An oversized radius is clamped to the rect")
    func oversizedRadiusIsClamped() {
        let outline = Outline(
            ThawBarBorderShape(cornerRadius: 500, cornerStyle: .circular, omitTopEdge: true)
                .path(in: rect)
        )
        #expect(outline.boundingRect.isNear(rect))
        #expect(!outline.hasTopEdge(of: rect))
    }

    /// Zero-height bars occur transiently while the menu bar height is still
    /// being estimated; they must not trap on a negative dimension.
    @Test("A degenerate rect collapses to a point")
    func degenerateRectCollapses() {
        let outline = Outline(
            ThawBarBorderShape(cornerRadius: 8, omitTopEdge: true).path(in: .zero)
        )
        #expect(outline.boundingRect.isNear(.zero))
    }

    // MARK: - Inset accumulation

    /// `InsettableShape` insets compose, so `.strokeBorder` and an explicit
    /// inset do not overwrite one another.
    @Test("Insets accumulate")
    func insetsAccumulate() {
        let shape = ThawBarBorderShape(cornerRadius: 15, omitTopEdge: false)
            .inset(by: 2)
            .inset(by: 3)
        #expect(shape.insetAmount == 5)
        #expect(Outline(shape.path(in: rect)).boundingRect.isNear(rect.insetBy(dx: 5, dy: 5)))
    }

    // MARK: - Clip and border agreement

    /// Rounded ends: a circular half-height radius, top edge kept.
    @Test("A rounded clip is a circular half-height radius")
    func roundedClipGeometry() {
        let clip = ThawBarBorderShape.thawBarClip(height: 30, hasRoundedShape: true)
        #expect(clip.cornerRadius == 15)
        #expect(clip.cornerStyle == .circular)
        #expect(!clip.omitTopEdge)
        #expect(clip.insetAmount == 0)
    }

    /// Square ends: a continuous quarter-height radius. The clip stays closed
    /// even where the border opens up.
    @Test("A square clip is a continuous quarter-height radius and stays closed")
    func squareClipGeometry() {
        let clip = ThawBarBorderShape.thawBarClip(height: 30, hasRoundedShape: false)
        #expect(clip.cornerRadius == 7.5)
        #expect(clip.cornerStyle == .continuous)
        #expect(!clip.omitTopEdge)
    }

    /// Otherwise the stroke floats off the clipped edge.
    @Test("The border inherits the clip's radius and style", arguments: [true, false])
    func borderInheritsClipGeometry(hasRoundedShape: Bool) {
        let clip = ThawBarBorderShape.thawBarClip(height: 30, hasRoundedShape: hasRoundedShape)
        let border = ThawBarBorderShape.thawBarBorder(
            height: 30,
            hasRoundedShape: hasRoundedShape,
            borderWidth: 2
        )
        #expect(border.cornerRadius == clip.cornerRadius)
        #expect(border.cornerStyle == clip.cornerStyle)
        #expect(border.insetAmount == 1)
    }

    /// Only square corners open the top edge (#325); rounded ends have no
    /// screen corner to collide with.
    @Test("Only a square border opens the top edge")
    func onlySquareBorderOpensTopEdge() {
        #expect(
            ThawBarBorderShape
                .thawBarBorder(height: 30, hasRoundedShape: false, borderWidth: 1)
                .omitTopEdge
        )
        #expect(
            !ThawBarBorderShape
                .thawBarBorder(height: 30, hasRoundedShape: true, borderWidth: 1)
                .omitTopEdge
        )
    }

    /// Half a stroke width of inset keeps the stroke from straddling the clip edge.
    @Test("The border sits half a stroke width inside the clip")
    func borderSitsInsideClip() {
        let clipBounds = Outline(
            ThawBarBorderShape.thawBarClip(height: 30, hasRoundedShape: true).path(in: rect)
        ).boundingRect
        let borderBounds = Outline(
            ThawBarBorderShape
                .thawBarBorder(height: 30, hasRoundedShape: true, borderWidth: 4)
                .path(in: rect)
        ).boundingRect
        #expect(borderBounds.isNear(clipBounds.insetBy(dx: 2, dy: 2)))
    }
}

// MARK: - Path introspection

/// A flattened view of a `Path`: its segment endpoints, in draw order.
private struct Outline {
    struct Segment {
        var from: CGPoint
        var to: CGPoint
        var isCurve: Bool
    }

    var segments: [Segment] = []
    var isClosed = false

    var start: CGPoint { segments.first?.from ?? .zero }
    var end: CGPoint { segments.last?.to ?? .zero }
    var curveCount: Int { segments.count { $0.isCurve } }

    var boundingRect: CGRect {
        let points = segments.flatMap { [$0.from, $0.to] }
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }

    init(_ path: Path) {
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        path.forEach { element in
            switch element {
            case let .move(to: point):
                current = point
                subpathStart = point
            case let .line(to: point):
                segments.append(Segment(from: current, to: point, isCurve: false))
                current = point
            case let .quadCurve(to: point, control: _):
                segments.append(Segment(from: current, to: point, isCurve: true))
                current = point
            case let .curve(to: point, control1: _, control2: _):
                segments.append(Segment(from: current, to: point, isCurve: true))
                current = point
            case .closeSubpath:
                isClosed = true
                segments.append(Segment(from: current, to: subpathStart, isCurve: false))
                current = subpathStart
            }
        }
    }

    /// Whether any segment runs horizontally along the top of `rect`.
    ///
    /// Uses a wider tolerance than the shape's own 0.5 so a top edge that
    /// merely drifted, rather than vanished, still counts as present.
    func hasTopEdge(of rect: CGRect) -> Bool {
        segments.contains { segment in
            abs(segment.from.y - rect.minY) < 1
                && abs(segment.to.y - rect.minY) < 1
                && abs(segment.to.x - segment.from.x) > 1
        }
    }
}

private extension CGPoint {
    func isNear(_ other: CGPoint, tolerance: CGFloat = 0.5) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

private extension CGRect {
    func isNear(_ other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(maxX - other.maxX) <= tolerance
            && abs(maxY - other.maxY) <= tolerance
    }
}
