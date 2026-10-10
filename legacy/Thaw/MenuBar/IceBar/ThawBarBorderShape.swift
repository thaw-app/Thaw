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
/// Build both through the factories below, or the border drifts off the
/// clipped edge.
///
/// With square corners the top edge would be clipped by the screen's rounded
/// corners, so the border omits it.
nonisolated struct ThawBarBorderShape: InsettableShape {
    var cornerRadius: CGFloat
    /// Circular for fully rounded ends, continuous for square corners.
    var cornerStyle: RoundedCornerStyle = .continuous
    /// Leaves the top edge open, starting at the top-leading corner.
    var omitTopEdge: Bool
    /// Accumulated through ``inset(by:)``.
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

    /// The border that traces ``thawBarClip(height:hasRoundedShape:)``.
    ///
    /// Inset by half the stroke width so it sits centred on the clip edge.
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

        if !omitTopEdge {
            return RoundedRectangle(cornerRadius: radius, style: cornerStyle)
                .path(in: drawRect)
        }

        guard radius > 0 else {
            var path = Path()
            path.move(to: CGPoint(x: drawRect.minX, y: drawRect.minY))
            path.addLine(to: CGPoint(x: drawRect.minX, y: drawRect.maxY))
            path.addLine(to: CGPoint(x: drawRect.maxX, y: drawRect.maxY))
            path.addLine(to: CGPoint(x: drawRect.maxX, y: drawRect.minY))
            return path
        }

        // Bottom corners follow `cornerStyle` to match the clip.
        let closed = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: radius,
                bottomTrailing: radius,
                topTrailing: 0
            ),
            style: cornerStyle
        ).path(in: drawRect)

        return Self.openPathOmittingTopEdge(closed, in: drawRect)
    }

    /// Drops the top edge of a closed rounded-rect path.
    ///
    /// `UnevenRoundedRectangle` begins partway down the trailing edge, so the
    /// top edge sits mid-sequence. The loop is rebuilt in full and rotated to
    /// start just after the top edge, or the loose ends rejoin.
    private static func openPathOmittingTopEdge(_ closed: Path, in rect: CGRect) -> Path {
        let loop = segments(of: closed)
        guard let topEdge = loop.firstIndex(where: { isTopEdge($0, in: rect) }) else {
            // A closed outline beats a mangled one.
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
    /// that `closeSubpath` only implies.
    private static func segments(of path: Path) -> [Segment] {
        var segments: [Segment] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

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

    /// A zero-radius corner still emits zero-length curves on `minY`, so the
    /// width test is required.
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
