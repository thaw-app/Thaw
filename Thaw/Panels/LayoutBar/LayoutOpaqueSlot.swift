//
//  LayoutOpaqueSlot.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

@MainActor
protocol LayoutOpaqueSlotApplication {
    var bundleIdentifier: String? { get }
    var icon: NSImage? { get }
}

extension NSRunningApplication: LayoutOpaqueSlotApplication {}

/// A presentation-only slot for a running status item that cannot provide a
/// reliable AX glyph. It never enters MenuBarItemCache or persisted ordering.
nonisolated struct LayoutOpaqueSlotDescriptor: Equatable {
    let runtimePositionKey: String
    let bundleIdentifier: String
    let title: String
    let badgeSystemImage: String
    let badgeReason: String
    let tooltip: String
    let accessibilityLabel: String
    let captureTag: MenuBarItemTag?

    /// A placeholder for a Control Center menu extra its preference removes
    /// from the bar, so its assignment stays visible instead of looking deleted.
    static func governableExtra(menuExtraTitle: String, displayName: String) -> Self {
        Self(
            runtimePositionKey: "governable:\(menuExtraTitle)",
            bundleIdentifier: "com.apple.controlcenter",
            title: displayName,
            badgeSystemImage: "eye.slash",
            badgeReason: String(localized: "Removed while hidden"),
            tooltip: String(
                localized: "\(displayName) is removed from the menu bar while its section is hidden. Reveal the section to show it; it is removed again on conceal."
            ),
            accessibilityLabel: String(localized: "\(displayName), removed while hidden"),
            captureTag: MenuBarItemTag(namespace: .menuBarAgent, title: menuExtraTitle)
        )
    }

    /// Human name for a governable menu-extra title.
    static func governableExtraDisplayName(forMenuExtraTitle title: String) -> String {
        switch title {
        case "com.apple.menuextra.airdrop": String(localized: "AirDrop")
        case "com.apple.menuextra.bluetooth": String(localized: "Bluetooth")
        case "com.apple.menuextra.wifi": String(localized: "Wi‑Fi")
        case "com.apple.menuextra.now-playing": String(localized: "Now Playing")
        case "com.apple.menuextra.user": String(localized: "Fast User Switching")
        case "com.apple.menuextra.focusmode": String(localized: "Focus")
        default: title
        }
    }

    @MainActor
    static func appIcon(
        bundleIdentifier: String,
        applications: [some LayoutOpaqueSlotApplication]
    ) -> NSImage? {
        applications.first { $0.bundleIdentifier == bundleIdentifier }?.icon
    }

    @MainActor
    static func preferredIcon(
        capturedImage: NSImage?,
        bundleIdentifier: String,
        applications: [some LayoutOpaqueSlotApplication]
    ) -> NSImage? {
        capturedImage ?? appIcon(bundleIdentifier: bundleIdentifier, applications: applications)
    }
}

final class LayoutOpaqueSlotView: LayoutBarArrangedView {
    private enum Metrics {
        static let size = CGSize(width: 32, height: 32)
        static let iconInset: CGFloat = 2
        static let badgeSize: CGFloat = 12
    }

    let descriptor: LayoutOpaqueSlotDescriptor
    private let displayIcon: NSImage?
    private lazy var tooltipController = CustomTooltipController(text: descriptor.tooltip, view: self)
    private var tooltipTrackingArea: NSTrackingArea?

    override var kind: Kind {
        .opaqueSlot(descriptor)
    }

    init(
        descriptor: LayoutOpaqueSlotDescriptor,
        runningApplications: [NSRunningApplication],
        capturedImage: NSImage? = nil
    ) {
        self.descriptor = descriptor
        self.displayIcon = LayoutOpaqueSlotDescriptor.preferredIcon(
            capturedImage: capturedImage,
            bundleIdentifier: descriptor.bundleIdentifier,
            applications: runningApplications
        )
        super.init(frame: CGRect(origin: .zero, size: Metrics.size))
        isEnabled = false
        unregisterDraggedTypes()
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(descriptor.accessibilityLabel)
        setAccessibilityHelp(descriptor.tooltip)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tooltipTrackingArea {
            removeTrackingArea(tooltipTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tooltipTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        tooltipController.scheduleShow(delay: 0.5)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        tooltipController.cancel()
    }

    override func draw(_: NSRect) {
        let iconRect = bounds.insetBy(dx: Metrics.iconInset, dy: Metrics.iconInset)
        if let displayIcon {
            displayIcon.draw(in: iconRect)
        } else if let fallback = NSImage(
            systemSymbolName: "app.dashed",
            accessibilityDescription: descriptor.title
        ) {
            fallback.draw(in: iconRect)
        }

        let badgeRect = CGRect(
            x: bounds.maxX - Metrics.badgeSize,
            y: bounds.minY,
            width: Metrics.badgeSize,
            height: Metrics.badgeSize
        )
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1, dy: -1)).fill()
        if let badge = NSImage(
            systemSymbolName: descriptor.badgeSystemImage,
            accessibilityDescription: descriptor.badgeReason
        ) {
            badge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 0.7)
        }
    }
}
