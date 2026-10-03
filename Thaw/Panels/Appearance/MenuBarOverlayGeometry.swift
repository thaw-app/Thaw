//
//  MenuBarOverlayGeometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

nonisolated enum MenuBarLiquidGlassGeometry {
    static func componentBounds(of path: CGPath) -> [CGRect] {
        var bounds = [CGRect]()
        var component = CGMutablePath()

        func finishComponent() {
            guard !component.isEmpty else { return }
            let componentBounds = component.boundingBoxOfPath
            if !componentBounds.isEmpty {
                bounds.append(componentBounds)
            }
            component = CGMutablePath()
        }

        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                finishComponent()
                component.move(to: element.points[0])
            case .addLineToPoint:
                component.addLine(to: element.points[0])
            case .addQuadCurveToPoint:
                component.addQuadCurve(
                    to: element.points[1],
                    control: element.points[0]
                )
            case .addCurveToPoint:
                component.addCurve(
                    to: element.points[2],
                    control1: element.points[0],
                    control2: element.points[1]
                )
            case .closeSubpath:
                component.closeSubpath()
                finishComponent()
            @unknown default:
                break
            }
        }
        finishComponent()
        return bounds
    }
}

nonisolated enum MenuBarSplitPillGeometry {
    static func followingVisibleEdge(
        _ sample: MenuBarLeadingEdgeSample,
        itemBounds: [CGRect],
        stableTrailingBounds: CGRect,
        screenFrame: CGRect,
        revealedSection: MenuBarSection.Name?,
        isTransitioning: Bool = false,
        sourceScreenFrame: CGRect? = nil
    ) -> (itemBounds: [CGRect], stableTrailingBounds: CGRect) {
        // Only the display that supplied these bounds may correct a mirrored pill's edge.
        guard sample.screenFrame == screenFrame || sample.screenFrame == sourceScreenFrame,
              revealedSection == nil, !isTransitioning
        else {
            return (itemBounds, stableTrailingBounds)
        }
        let edge = screenFrame.maxX - (sample.screenFrame.maxX - sample.x)
        guard let currentMinX = itemBounds.map(\.minX).min(),
              abs(currentMinX - edge) >= 1,
              let reference = itemBounds.first
        else { return (itemBounds, stableTrailingBounds) }
        var updated = itemBounds
        if edge > currentMinX {
            updated = itemBounds.compactMap { bounds in
                guard bounds.maxX > edge else { return nil }
                guard bounds.minX < edge else { return bounds }
                return CGRect(x: edge, y: bounds.minY, width: bounds.maxX - edge, height: bounds.height)
            }
        } else {
            updated.append(CGRect(x: edge, y: reference.minY, width: currentMinX - edge, height: reference.height))
        }
        var stable = stableTrailingBounds
        if !stable.isEmpty {
            let minX = stable.minX + (edge - currentMinX)
            if minX < stable.maxX {
                stable = CGRect(x: minX, y: stable.minY, width: stable.maxX - minX, height: stable.height)
            }
        }
        return (updated, stable)
    }

    static func leadingBounds(
        applicationMenuFrame: CGRect,
        trailingContentMinX: CGFloat?,
        in rect: CGRect,
        screenFrame: CGRect,
        trailingPadding: CGFloat,
        leadingMargin: CGFloat,
        notchFrame: CGRect?,
        notchMargin: CGFloat
    ) -> CGRect {
        let screenOriginX = screenFrame.minX
        let leftX = rect.minX + leadingMargin
        var rightX = if applicationMenuFrame.width > 0 {
            applicationMenuFrame.maxX - screenOriginX + trailingPadding
        } else {
            rect.maxX
        }

        if let notchFrame {
            rightX = min(rightX, notchFrame.minX - screenOriginX - notchMargin)
        }
        if let trailingContentMinX {
            rightX = min(rightX, trailingContentMinX - screenOriginX - 4)
        }

        rightX = min(max(rightX, rect.minX), rect.maxX)
        return CGRect(
            x: leftX,
            y: rect.minY,
            width: max(0, rightX - leftX),
            height: rect.height
        )
    }

    static func trailingBounds(
        itemBounds: [CGRect],
        in rect: CGRect,
        screenFrame: CGRect,
        leadingOutset: CGFloat,
        trailingOutset: CGFloat,
        notchFrame: CGRect?,
        notchMargin: CGFloat
    ) -> CGRect {
        let displayItemBounds = itemBounds.filter { bounds in
            bounds.midX >= screenFrame.minX && bounds.midX <= screenFrame.maxX
        }
        guard
            let contentMinX = displayItemBounds.map(\.minX).min(),
            let contentMaxX = displayItemBounds.map(\.maxX).max()
        else { return .zero }

        let screenOriginX = screenFrame.minX
        var leftX = contentMinX - leadingOutset - screenOriginX
        var rightX = contentMaxX + trailingOutset - screenOriginX

        if let notchFrame {
            leftX = max(leftX, notchFrame.maxX - screenOriginX + notchMargin)
        }

        leftX = min(max(leftX, rect.minX), rect.maxX)
        rightX = min(max(rightX, rect.minX), rect.maxX)
        return CGRect(
            x: leftX,
            y: rect.minY,
            width: max(0, rightX - leftX),
            height: rect.height
        )
    }

    /// Section/reveal state used when deciding which AX frames belong in the
    /// split trailing pill.
    nonisolated struct TrailingPillContext {
        var revealedSection: MenuBarSection.Name?
        var section: (MenuBarItem) -> MenuBarSection.Name
    }

    /// Picks drawable split-pill rectangles, preferring the last stable pair
    /// only while geometry is frozen or when a fresh AX read is completely empty.
    static func resolveSplitPathBounds(
        leading: CGRect,
        trailing: CGRect,
        geometryFrozen: Bool,
        lastStableLeading: CGRect,
        lastStableTrailing: CGRect
    ) -> (leading: CGRect, trailing: CGRect, nextStableLeading: CGRect, nextStableTrailing: CGRect) {
        if geometryFrozen,
           lastStableLeading != .zero || lastStableTrailing != .zero
        {
            return (
                lastStableLeading,
                lastStableTrailing,
                lastStableLeading,
                lastStableTrailing
            )
        }

        let freshValid = leading != .zero
            && trailing != .zero
            && !leading.intersects(trailing)
        if freshValid {
            return (leading, trailing, leading, trailing)
        }

        if leading != .zero, trailing == .zero {
            return (leading, .zero, leading, .zero)
        }

        if leading != .zero, trailing != .zero, leading.intersects(trailing) {
            // Overlap during reflow: draw the leading segment only instead of
            // resurrecting a stale trailing pill that still spans empty space.
            return (leading, .zero, leading, .zero)
        }

        if leading == .zero, trailing == .zero,
           lastStableLeading != .zero,
           lastStableTrailing != .zero,
           !lastStableLeading.intersects(lastStableTrailing)
        {
            return (
                lastStableLeading,
                lastStableTrailing,
                lastStableLeading,
                lastStableTrailing
            )
        }

        if leading == .zero, trailing == .zero,
           lastStableLeading != .zero,
           lastStableTrailing == .zero
        {
            return (lastStableLeading, .zero, lastStableLeading, .zero)
        }

        return (leading, trailing, lastStableLeading, lastStableTrailing)
    }

    /// Bounds that the split trailing pill should wrap on macOS 27.
    static func trailingPillBounds(
        from items: [MenuBarItem],
        context: TrailingPillContext
    ) -> [CGRect] {
        let isRevealingHidden = context.revealedSection == .hidden
            || context.revealedSection == .alwaysHidden
        let isRevealingAlwaysHidden = context.revealedSection == .alwaysHidden

        return items.compactMap { item -> CGRect? in
            guard shouldIncludeItemInTrailingPill(
                item,
                among: items,
                context: context,
                isRevealingHidden: isRevealingHidden,
                isRevealingAlwaysHidden: isRevealingAlwaysHidden
            ) else {
                return nil
            }
            return item.bounds
        }
    }

    /// macOS 27 can omit system-module frames at scaled notched resolutions; a one-point trailing stand-in keeps them filled.
    /// trailingBounds clamps the stand-in to the drawable rectangle.
    static func trailingPillBounds(
        from items: [MenuBarItem],
        screenFrame: CGRect,
        context: TrailingPillContext,
        mapBounds: (CGRect) -> CGRect = { $0 }
    ) -> [CGRect] {
        var bounds = trailingPillBounds(from: items, context: context).map(mapBounds)
        if !items.isEmpty, !bounds.isEmpty,
           !items.contains(where: { $0.tag.namespace == .menuBarAgent })
        {
            bounds.append(
                CGRect(
                    x: screenFrame.maxX - 1,
                    y: bounds.map(\.minY).min() ?? 0,
                    width: 1,
                    height: bounds.map(\.height).max() ?? 0
                )
            )
        }
        return bounds
    }

    /// Whether a live status item should contribute to the split trailing pill.
    static func shouldIncludeItemInTrailingPill(
        _ item: MenuBarItem,
        among peers: [MenuBarItem],
        context: TrailingPillContext,
        isRevealingHidden: Bool,
        isRevealingAlwaysHidden: Bool
    ) -> Bool {
        let isHiddenSectionDivider = item.isControlItem
            && !item.tag.matchesVisibleControlItem
        guard !item.isSystemClone,
              !isHiddenSectionDivider,
              item.isOnScreen,
              !item.bounds.isEmpty,
              !item.isParkedOffMenuBarBand(among: peers)
        else {
            return false
        }

        if isRevealingHidden {
            if item.tag.matchesVisibleControlItem {
                return true
            }
            if context.section(item) == .alwaysHidden, !isRevealingAlwaysHidden {
                return false
            }
            return true
        }

        // Exclude CC-hidden Sound/WiFi far-left AX slots so the pill does not span empty space.
        // Non-concealable Spotlight/Clock items are forcedVisible and resolve to visible.
        if context.section(item) != .visible {
            return false
        }
        return true
    }
}
