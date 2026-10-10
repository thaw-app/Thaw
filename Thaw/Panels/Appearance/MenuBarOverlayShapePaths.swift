//
//  MenuBarOverlayShapePaths.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Pure construction of the overlay's shape paths.
///
/// Kept apart from the content view so the drawing geometry can be reasoned
/// about without a live panel: every value a path depends on is a parameter,
/// and nothing here touches the view's state.
enum MenuBarShapePathBuilder {
    /// Pulls rect in so that an inset shape clears the edges of a notched
    /// menu bar.
    ///
    /// The top and bottom always come in by amount. Horizontally only the
    /// rounded ends move: a square end is already flush with the edge it sits
    /// against and has no curve needing room.
    ///
    /// Returns rect untouched on displays without a notch, or when the
    /// configuration does not ask for an inset shape.
    static func insetForNotch(
        _ rect: CGRect,
        outerCaps: MenuBarFullShapeInfo,
        isInset: Bool,
        screen: NSScreen,
        amount: CGFloat
    ) -> CGRect {
        guard isInset, screen.hasNotch else {
            return rect
        }
        var rect = rect.insetBy(dx: 0, dy: amount)
        if outerCaps.leadingEndCap == .round {
            rect.origin.x += amount
            rect.size.width -= amount
        }
        if outerCaps.trailingEndCap == .round {
            rect.size.width -= amount
        }
        return rect
    }

    /// The path of one end cap: a square filling its bounds, or a circle
    /// inscribed in them.
    static func endCapPath(_ endCap: MenuBarEndCap, in bounds: CGRect) -> NSBezierPath {
        switch endCap {
        case .square: NSBezierPath(rect: bounds)
        case .round: NSBezierPath(ovalIn: bounds)
        }
    }

    /// A capsule-ish path filling rect, finished at each end by the given cap.
    ///
    /// The path is a bar with a cap laid over each end, unioned together, so a
    /// square cap squares the end off and a round cap rounds it into a
    /// semicircle of the bar's own height.
    ///
    /// On displays without a notch the shape is pulled a hair inside rect:
    /// one point off the top and bottom, and one point off each rounded end so
    /// its curve is not clipped by the edge of the screen.
    static func shapePath(
        in rect: CGRect,
        caps: MenuBarFullShapeInfo,
        screen: NSScreen
    ) -> NSBezierPath {
        let insetRect: CGRect =
            if screen.hasNotch {
                rect
            } else {
                CGRect(
                    x: rect.origin.x + (caps.leadingEndCap == .round ? 1 : 0),
                    y: rect.origin.y + 1,
                    width: rect.width
                        - (caps.leadingEndCap == .round ? 1 : 0)
                        - (caps.trailingEndCap == .round ? 1 : 0),
                    height: rect.height - 2
                )
            }

        // Each cap is a square the height of the bar, sitting at one end; the
        // bar itself spans what is left between their centers.
        let capSide = insetRect.height
        let capSize = CGSize(width: capSide, height: capSide)
        let leadingCapBounds = CGRect(origin: insetRect.origin, size: capSize)
        let trailingCapBounds = CGRect(
            origin: CGPoint(x: insetRect.maxX - capSide, y: insetRect.minY),
            size: capSize
        )

        let barBounds = CGRect(
            x: insetRect.minX + capSide / 2,
            y: insetRect.minY,
            width: insetRect.width - capSide,
            height: insetRect.height
        )

        return NSBezierPath(rect: barBounds)
            .union(endCapPath(caps.leadingEndCap, in: leadingCapBounds))
            .union(endCapPath(caps.trailingEndCap, in: trailingCapBounds))
    }

    /// One path holding both pills of a two-part shape.
    static func pillPairPath(
        leading: CGRect,
        trailing: CGRect,
        leadingCaps: MenuBarFullShapeInfo,
        trailingCaps: MenuBarFullShapeInfo,
        screen: NSScreen
    ) -> NSBezierPath {
        let path = NSBezierPath()
        path.append(shapePath(in: leading, caps: leadingCaps, screen: screen))
        path.append(shapePath(in: trailing, caps: trailingCaps, screen: screen))
        return path
    }

    /// Returns a path for the MenuBarShapeKind.full shape kind.
    ///
    /// insetAmount is nil when the appearance manager is unavailable, and
    /// the caller then has nothing to draw, so it gets an empty path.
    static func fullShapePath(
        in rect: CGRect,
        info: MenuBarFullShapeInfo,
        isInset: Bool,
        screen: NSScreen,
        leftMargin: Double,
        rightMargin: Double,
        insetAmount: CGFloat?
    ) -> NSBezierPath {
        guard let insetAmount else {
            return NSBezierPath()
        }
        var rect = rect
        rect.origin.x += leftMargin
        rect.size.width -= (leftMargin + rightMargin)
        rect = insetForNotch(
            rect,
            outerCaps: info,
            isInset: isInset,
            screen: screen,
            amount: insetAmount
        )
        return shapePath(in: rect, caps: info, screen: screen)
    }

    /// Returns a path for the MenuBarShapeKind.notch shape kind.
    /// Behaves like full on non-notched displays, splits at the notch
    /// on notched displays.
    ///
    /// insetAmount is nil when the appearance manager is unavailable, and
    /// the caller then has nothing to draw, so it gets an empty path.
    static func notchShapePath(
        in rect: CGRect,
        info: MenuBarNotchShapeInfo,
        isInset: Bool,
        screen: NSScreen,
        leftMargin: Double,
        rightMargin: Double,
        notchMargin: Double,
        insetAmount: CGFloat?
    ) -> NSBezierPath {
        guard let insetAmount else {
            return NSBezierPath()
        }

        // Non-notched: behaves like full shape using the outer end caps
        guard screen.hasNotch,
              let topLeft = screen.auxiliaryTopLeftArea,
              let topRight = screen.auxiliaryTopRightArea
        else {
            return fullShapePath(
                in: rect,
                info: info.outerEndCaps,
                isInset: isInset,
                screen: screen,
                leftMargin: leftMargin,
                rightMargin: rightMargin,
                insetAmount: insetAmount
            )
        }

        let rect = insetForNotch(
            rect,
            outerCaps: info.outerEndCaps,
            isInset: isInset,
            screen: screen,
            amount: insetAmount
        )

        let screenOrigin = screen.frame.minX

        let leadingBounds: CGRect = {
            let notchLeftX = topLeft.maxX - screenOrigin - notchMargin
            let adjustedMinX = rect.minX + leftMargin
            let width = max(0, notchLeftX - adjustedMinX)
            return CGRect(x: adjustedMinX, y: rect.minY, width: width, height: rect.height)
        }()

        let trailingBounds: CGRect = {
            let notchRightX = topRight.minX - screenOrigin + notchMargin
            let maxX = rect.maxX - rightMargin
            let width = max(0, maxX - notchRightX)
            return CGRect(x: notchRightX, y: rect.minY, width: width, height: rect.height)
        }()

        if leadingBounds.width <= 0 || trailingBounds.width <= 0
            || leadingBounds.intersects(trailingBounds)
        {
            return fullShapePath(
                in: rect,
                info: info.outerEndCaps,
                isInset: isInset,
                screen: screen,
                leftMargin: leftMargin,
                rightMargin: rightMargin,
                insetAmount: insetAmount
            )
        }

        return pillPairPath(
            leading: leadingBounds,
            trailing: trailingBounds,
            leadingCaps: info.leading,
            trailingCaps: info.trailing,
            screen: screen
        )
    }

    /// Builds the split shape from resolved leading/trailing rectangles.
    static func splitShapePath(
        leadingPathBounds: CGRect,
        trailingPathBounds: CGRect,
        info: MenuBarSplitShapeInfo,
        in rect: CGRect,
        leftMargin: Double,
        rightMargin: Double,
        screen: NSScreen
    ) -> NSBezierPath {
        switch (leadingPathBounds == .zero, trailingPathBounds == .zero) {
        case (true, true):
            // Geometry not yet loaded; draw nothing.
            return NSBezierPath()
        case (false, true):
            return shapePath(in: leadingPathBounds, caps: info.leading, screen: screen)
        case (true, false):
            // Trailing items known but app-menu frame not yet loaded: draw
            // only the trailing pill rather than a full-width fallback that
            // would cover the empty center of the bar.
            return shapePath(in: trailingPathBounds, caps: info.trailing, screen: screen)
        case (false, false):
            break
        }

        if leadingPathBounds.intersects(trailingPathBounds) {
            // Pills intersect (transient reflow): fall back to full-width.
            var fallbackRect = rect
            fallbackRect.origin.x += leftMargin
            fallbackRect.size.width -= (leftMargin + rightMargin)
            return shapePath(in: fallbackRect, caps: info.outerEndCaps, screen: screen)
        }

        return pillPairPath(
            leading: leadingPathBounds,
            trailing: trailingPathBounds,
            leadingCaps: info.leading,
            trailingCaps: info.trailing,
            screen: screen
        )
    }
}
