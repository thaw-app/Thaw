//
//  LayoutBarItemView+Pointer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Hover, press and click-or-drag for one gesture on a Layout tile.
nonisolated struct LayoutTilePointer: Equatable {
    /// A wobble under this many points stays a click, so the inspector still opens.
    static let dragThreshold: CGFloat = 3

    var isHovered = false
    private(set) var isPressed = false
    private(set) var isClickCandidate = false
    private var pressLocation: CGPoint?

    /// The accent wash's opacity: stronger while pressed than while hovered.
    var washAlpha: CGFloat? {
        isPressed ? 0.25 : isHovered ? 0.12 : nil
    }

    mutating func press(at location: CGPoint) {
        isPressed = true
        isClickCandidate = true
        pressLocation = location
    }

    /// Whether the pointer has moved far enough to drag. From then on the gesture is no longer a click.
    mutating func drag(to location: CGPoint) -> Bool {
        if let start = pressLocation, location.distance(to: start) < Self.dragThreshold {
            return false
        }
        isPressed = false
        isClickCandidate = false
        return true
    }

    mutating func release() -> Bool {
        defer {
            isPressed = false
            isClickCandidate = false
            pressLocation = nil
        }
        return isClickCandidate
    }

    mutating func exit() {
        isHovered = false
        isPressed = false
    }
}

extension LayoutBarItemView {
    func pointerEntered() {
        tooltipController.scheduleShow(delay: tooltipDelay)
        pointer.isHovered = true
        needsDisplay = true
    }

    func pointerExited() {
        tooltipController.cancel()
        pointer.exit()
        needsDisplay = true
    }

    func pointerPressed(_ event: NSEvent) {
        pointer.press(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    func pointerReleased() -> Bool {
        needsDisplay = true
        return pointer.release()
    }

    func pointerDragged(_ event: NSEvent) -> Bool {
        let began = pointer.drag(to: convert(event.locationInWindow, from: nil))
        if began {
            needsDisplay = true
        }
        return began
    }

    /// The accent wash under the glyph while the pointer is over the tile or pressing it.
    func drawPointerWash() {
        guard isEnabled, let alpha = pointer.washAlpha else { return }
        let radius = LayoutSelectionHighlight.Style.cornerRadius
        NSColor.controlAccentColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    /// An hourglass in the trailing corner while the app isn't responding, and the warning in the
    /// leading corner while macOS keeps the icon out of this section.
    func drawBadges() {
        if isOwnerUnresponsive, let hourglass = Self.unresponsiveBadge {
            drawBadge(hourglass, atLeadingEdge: false)
        }
        if visibilityLimit != nil {
            drawBadge(NSImage.warning, atLeadingEdge: true)
        }
    }

    private func drawBadge(_ badge: NSImage, atLeadingEdge: Bool) {
        let width = Metrics.unresponsiveBadgeWidth
        let size = CGSize(width: width, height: badge.size.height * (width / max(badge.size.width, 1)))
        let originX = atLeadingEdge ? bounds.minX : bounds.maxX - size.width
        badge.draw(in: CGRect(x: originX, y: bounds.minY, width: size.width, height: size.height))
    }

    private static var unresponsiveBadge: NSImage? {
        NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
    }

    /// The tooltip and VoiceOver help for whichever badge applies, the unresponsive one first.
    func refreshBadgeHelp() {
        let help = isOwnerUnresponsive
            ? Self.unresponsiveHelp(appName: item.owningApplication?.localizedName ?? item.displayName)
            : visibilityLimit?.explanation
        toolTip = help
        setAccessibilityHelp(help ?? appWideOverride?.tooltip(itemName: item.displayName))
        needsDisplay = true
    }

    nonisolated static func unresponsiveHelp(appName: String) -> String {
        String(
            localized: "\(appName) isn’t responding, so it can’t be moved right now.",
            comment: "Tooltip and VoiceOver help on a Layout item whose app is hung"
        )
    }
}
