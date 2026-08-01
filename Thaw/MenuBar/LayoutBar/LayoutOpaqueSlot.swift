//
//  LayoutOpaqueSlot.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import PlatformRuntimeKit

@MainActor
protocol LayoutOpaqueSlotApplication {
    var bundleIdentifier: String? { get }
    var icon: NSImage? { get }
}

extension NSRunningApplication: LayoutOpaqueSlotApplication {}

/// A presentation-only slot for a running status item that cannot provide a
/// reliable AX glyph. It never enters MenuBarItemCache or persisted ordering.
nonisolated struct LayoutOpaqueSlotDescriptor: Equatable {
    static let littleSnitchBundleIdentifier = "at.obdev.littlesnitch.agent"
    static let littleSnitchRuntimePositionKey = "status:at.obdev.littlesnitch.agent::Item-0"

    let runtimePositionKey: String
    let bundleIdentifier: String
    let title: String
    let badgeSystemImage: String
    let badgeReason: String
    let tooltip: String
    let accessibilityLabel: String

    static func littleSnitch(
        runningBundleIdentifiers: Set<String>,
        positions: [String: Int]
    ) -> Self? {
        guard runningBundleIdentifiers.contains(littleSnitchBundleIdentifier),
              positions[littleSnitchRuntimePositionKey] != nil
        else { return nil }

        return Self(
            runtimePositionKey: littleSnitchRuntimePositionKey,
            bundleIdentifier: littleSnitchBundleIdentifier,
            title: String(localized: "Little Snitch"),
            badgeSystemImage: "eye.slash",
            badgeReason: String(localized: "Reliable menu bar preview unavailable"),
            tooltip: String(localized: "Little Snitch can’t provide a reliable menu bar preview. Thaw is showing its app icon; this slot can’t be moved here."),
            accessibilityLabel: String(localized: "Little Snitch app icon. A reliable menu bar preview is unavailable, and this slot can’t be moved in Thaw.")
        )
    }

    func matchesOpaqueItem(_ item: MenuBarItem) -> Bool {
        if item.tag.namespace == .string(bundleIdentifier) {
            return true
        }
        return item.tag.isControlCenterGenericItem && item.tag.title == "Item-0"
    }

    static func itemsForLayout(
        _ items: [MenuBarItem],
        suppressUnresolvedSlot: Bool
    ) -> [MenuBarItem] {
        items.filter { item in
            if item.tag.namespace == .string(littleSnitchBundleIdentifier) {
                return false
            }
            let isUnresolvedSlot = item.tag.isControlCenterGenericItem && item.tag.title == "Item-0"
            return !isUnresolvedSlot || !suppressUnresolvedSlot
        }
    }

    static func shouldSuppressUnresolvedSlot(
        in items: [MenuBarItem],
        littleSnitchRunning: Bool,
        wasSuppressed: Bool
    ) -> Bool {
        littleSnitchRunning || (
            wasSuppressed && items.contains {
                $0.tag.isControlCenterGenericItem && $0.tag.title == "Item-0"
            }
        )
    }

    @MainActor
    @available(macOS 27, *)
    func insertionIndex(in items: [MenuBarItem], positions: [String: Int]) -> Int {
        guard let opaqueWeight = positions[runtimePositionKey] else { return items.endIndex }
        let existingKeys = Array(positions.keys)
        let references: [(index: Int, x: CGFloat, weight: Int)] = items.enumerated().compactMap { index, item in
            guard !matchesOpaqueItem(item),
                  let key = RuntimePositionStore.resolveKey(
                      for: item,
                      existingKeys: existingKeys,
                      positions: positions,
                      liveItems: items
                  ),
                  let weight = positions[key]
            else { return nil }
            return (index, item.bounds.midX, weight)
        }
        return Self.insertionIndex(opaqueWeight: opaqueWeight, references: references, fallback: items.endIndex)
    }

    /// Inserts the opaque slot by its live AX frame's on-screen `midX`,
    /// instead of the saved preferred-position weights the ``insertionIndex``
    /// heuristic compares against.
    ///
    /// The weight path can drift 2-3 items away from where the LS icon
    /// actually renders: every reference item must resolve a fresh runtime
    /// key with an up-to-date weight, and any reference whose saved weight
    /// lags behind its current X (after a recent reorder, an app-quit title
    /// churn, or a `resolveKey` ambiguity miss) biases the slot's predicted
    /// position past several real neighbours. The opaque item itself carries
    /// a live AX frame in the same pass, so anchoring on its `midX` reads
    /// the truth: the cache enumerates items left-to-right, the displayed
    /// items keep that order, and the slot inserts before the first
    /// neighbour whose `midX` is at or past the anchor.
    ///
    /// `nil` is returned when the anchor is unusable (non-finite or
    /// non-positive); the caller then falls back to the weight heuristic
    /// rather than dropping the slot entirely. Pure value-level work over
    /// `MenuBarItem` bounds, so no OS-availability gate is needed.
    static func insertionIndex(
        byAnchorX anchorX: CGFloat,
        in displayedItems: [MenuBarItem]
    ) -> Int? {
        guard anchorX.isFinite, anchorX > 0 else { return nil }
        return displayedItems.firstIndex { item in
            item.bounds.midX.isFinite && item.bounds.midX >= anchorX
        } ?? displayedItems.endIndex
    }

    static func insertionIndex(
        opaqueWeight: Int,
        references: [(index: Int, x: CGFloat, weight: Int)],
        fallback: Int
    ) -> Int {
        guard references.count > 1 else { return fallback }
        let byX = references.sorted { $0.x < $1.x }
        let weightsIncreaseWithX = byX[0].weight < byX[byX.count - 1].weight
        let visualOrder = references.sorted {
            weightsIncreaseWithX ? $0.weight < $1.weight : $0.weight > $1.weight
        }
        guard let next = visualOrder.first(where: {
            weightsIncreaseWithX ? opaqueWeight < $0.weight : opaqueWeight > $0.weight
        }) else {
            return (visualOrder.last?.index ?? (fallback - 1)) + 1
        }
        return next.index
    }

    @MainActor
    static func appIcon(
        bundleIdentifier: String,
        applications: [some LayoutOpaqueSlotApplication]
    ) -> NSImage? {
        applications.first { $0.bundleIdentifier == bundleIdentifier }?.icon
    }
}

final class LayoutOpaqueSlotView: LayoutBarArrangedView {
    private enum Metrics {
        static let size = CGSize(width: 32, height: 32)
        static let iconInset: CGFloat = 2
        static let badgeSize: CGFloat = 12
    }

    let descriptor: LayoutOpaqueSlotDescriptor
    private let applicationIcon: NSImage?
    private lazy var tooltipController = CustomTooltipController(text: descriptor.tooltip, view: self)
    private var tooltipTrackingArea: NSTrackingArea?

    override var kind: Kind {
        .opaqueSlot(descriptor)
    }

    init(descriptor: LayoutOpaqueSlotDescriptor, runningApplications: [NSRunningApplication]) {
        self.descriptor = descriptor
        self.applicationIcon = LayoutOpaqueSlotDescriptor.appIcon(
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
        if let applicationIcon {
            applicationIcon.draw(in: iconRect)
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
