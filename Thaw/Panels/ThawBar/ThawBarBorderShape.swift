//
//  ThawBarBorderShape.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The Thaw Bar's rounded-rectangle geometry, serving as both its clip and
/// its border stroke.
///
/// The clip and the stroke have to agree on corner radius and style or the
/// border drifts off the clipped edge, so both are built by the factories
/// below instead of by separately maintained expressions at each call site.
///
/// When square corners meet the display's rounded screen corners,
/// the top edge of the stroke would be clipped and look broken, so the
/// border omits it and draws only the leading, trailing, and bottom edges.
nonisolated struct ThawBarBorderShape: InsettableShape {
    /// Corner radius of the un-inset path.
    var cornerRadius: CGFloat
    /// Circular for fully rounded ends, continuous for square corners.
    var cornerStyle: RoundedCornerStyle = .continuous
    /// When true, the path starts at the top-leading corner, runs down the
    /// leading side, across the bottom, and up the trailing side, leaving the
    /// top edge open.
    var omitTopEdge: Bool
    /// Inset applied before constructing the path. Accumulated through
    /// inset(by:) rather than set directly.
    var insetAmount: CGFloat = 0

    /// The Thaw Bar's clip for a given content height: fully rounded ends get
    /// a circular half-height radius, square corners a continuous
    /// quarter-height one.
    static func thawBarClip(height: CGFloat, hasRoundedShape: Bool) -> ThawBarBorderShape {
        ThawBarBorderShape(
            cornerRadius: hasRoundedShape ? height / 2 : height / 4,
            cornerStyle: hasRoundedShape ? .circular : .continuous,
            omitTopEdge: false
        )
    }

    /// The border that traces thawBarClip(height:hasRoundedShape:).
    ///
    /// Derived from the clip so the two cannot drift apart, inset by half the
    /// stroke width so the stroke sits centred on the clip edge, and opened at
    /// the top on square corners.
    static func thawBarBorder(
        height: CGFloat,
        hasRoundedShape: Bool,
        borderWidth: CGFloat
    ) -> ThawBarBorderShape {
        var shape = thawBarClip(height: height, hasRoundedShape: hasRoundedShape)
        shape.omitTopEdge = !hasRoundedShape
        return shape.inset(by: borderWidth / 2)
    }

    func inset(by amount: CGFloat) -> ThawBarBorderShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let drawRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(max(cornerRadius - insetAmount, 0), min(drawRect.width, drawRect.height) / 2)

        // The fill and the border both trace this rounded rectangle, so they
        // share the same corner radii and rounding style; the border differs
        // only in opening its top edge so a rounded screen corner cannot
        // clip it.
        let closed = RoundedRectangle(cornerRadius: radius, style: cornerStyle)
            .path(in: drawRect)
        guard omitTopEdge else {
            return closed
        }

        return Self.openPathOmittingTopEdge(closed, in: drawRect)
    }

    /// Drops the top edge of a closed rounded-rect path and reopens the
    /// remaining outline so the stroke runs top-leading → bottom → top-trailing.
    ///
    /// The source is a closed loop, but SwiftUI is free to begin that loop
    /// anywhere on it, so the removed edge can sit in the middle of the
    /// emitted order. Walking that order directly would join the two loose
    /// ends and draw the top edge straight back in, while losing the stretch of
    /// trailing edge above the start point. The outline is therefore rebuilt as
    /// a full loop, including the segment closeSubpath implies, and rotated
    /// to begin just after the top edge before being reversed.
    private static func openPathOmittingTopEdge(_ closed: Path, in rect: CGRect) -> Path {
        let loop = segments(of: closed)
        guard let topEdge = loop.firstIndex(where: { isTopEdge($0, in: rect) }) else {
            // Nothing recognizable to remove; a closed outline beats a mangled
            // one, so draw the shape as it came.
            return closed
        }

        let chain = Array(loop[(topEdge + 1)...] + loop[..<topEdge])

        var path = Path()
        guard let last = chain.last else {
            return path
        }

        // Reverse so drawing starts at the top-leading corner.
        path.move(to: last.to)
        for segment in chain.reversed() {
            switch segment.kind {
            case .line:
                path.addLine(to: segment.from)
            case let .quad(control):
                path.addQuadCurve(to: segment.from, control: control)
            case let .cubic(control1, control2):
                path.addCurve(to: segment.from, control1: control2, control2: control1)
            }
        }
        return path
    }

    /// Flattens a path into its segments, materializing the closing segment
    /// that closeSubpath only implies.
    private static func segments(of path: Path) -> [Segment] {
        var segments: [Segment] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        // swiftformat:disable:next preferForLoop
        path.forEach { element in
            switch element {
            case let .move(to: point):
                current = point
                subpathStart = point
            case let .line(to: point):
                segments.append(Segment(from: current, to: point, kind: .line))
                current = point
            case let .quadCurve(to: point, control: control):
                segments.append(Segment(from: current, to: point, kind: .quad(control: control)))
                current = point
            case let .curve(to: point, control1: control1, control2: control2):
                let kind = SegmentKind.cubic(control1: control1, control2: control2)
                segments.append(Segment(from: current, to: point, kind: kind))
                current = point
            case .closeSubpath:
                if current != subpathStart {
                    segments.append(Segment(from: current, to: subpathStart, kind: .line))
                }
                current = subpathStart
            }
        }
        return segments
    }

    /// Whether a segment is the run along the top of rect.
    ///
    /// The width test matters: a zero-radius corner still emits curve elements,
    /// they are just zero-length, and both of the top ones sit exactly on
    /// minY. Without it the first of those would be mistaken for the edge.
    private static func isTopEdge(_ segment: Segment, in rect: CGRect) -> Bool {
        abs(segment.from.y - rect.minY) < 0.5
            && abs(segment.to.y - rect.minY) < 0.5
            && abs(segment.to.x - segment.from.x) > 0.5
    }

    private struct Segment {
        var from: CGPoint
        var to: CGPoint
        var kind: SegmentKind
    }

    private enum SegmentKind {
        case line
        case quad(control: CGPoint)
        case cubic(control1: CGPoint, control2: CGPoint)
    }
}
