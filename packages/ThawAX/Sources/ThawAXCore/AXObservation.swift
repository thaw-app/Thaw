//
//  AXObservation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// One menu bar item as read from the Accessibility tree.
///
/// Model-free on purpose: the helper links no Thaw code, so it has no framework
/// rpath to resolve, and identity assembly stays in the app.
public struct AXItemObservation: Codable, Sendable, Equatable {
    /// The publishing application's bundle identifier (com.apple.MenuBarAgent
    /// for system items).
    public var bundleID: String?
    /// The publishing application's localized name, used as a namespace
    /// fallback when the bundle identifier is unavailable.
    public var processName: String?
    /// The process that owns the AX element.
    public var ownerPID: pid_t
    /// AXIdentifier.
    public var identifier: String?
    /// AXDescription.
    public var accessibilityDescription: String?
    /// AXTitle.
    public var title: String?
    /// AXHelp.
    public var help: String?
    /// The item's frame in screen coordinates.
    public var frame: CGRect
    /// Whether the element is MenuBarAgent's overflow chevron, not a real item.
    public var isOverflowControl: Bool
    /// The nested status-bar button's AXIdentifier, when the item's own
    /// container publishes none. Some apps put the stable identity on the
    /// button rather than the container, so the app falls back to this.
    public var childIdentifier: String?
    /// The nested status-bar button's AXDescription, the description
    /// counterpart of childIdentifier.
    public var childDescription: String?

    public init(
        bundleID: String?,
        processName: String?,
        ownerPID: pid_t,
        identifier: String?,
        accessibilityDescription: String?,
        title: String?,
        help: String?,
        frame: CGRect,
        isOverflowControl: Bool,
        childIdentifier: String? = nil,
        childDescription: String? = nil
    ) {
        self.bundleID = bundleID
        self.processName = processName
        self.ownerPID = ownerPID
        self.identifier = identifier
        self.accessibilityDescription = accessibilityDescription
        self.title = title
        self.help = help
        self.frame = frame
        self.isOverflowControl = isOverflowControl
        self.childIdentifier = childIdentifier
        self.childDescription = childDescription
    }
}

/// A request to the helper.
public struct AXEnumerateRequest: Codable, Sendable, Equatable {
    /// Restrict results to one display, or nil for every display.
    public var displayID: UInt32?
    /// Stop the walk once this many seconds have elapsed.
    public var deadlineSeconds: Double?
    /// The tallest an extras-bar child may be and still count as a status item.
    /// nil keeps the helper's default of 40 points, which is too short on a
    /// notched bar at high scaled resolutions; the app sends the same ceiling
    /// its in-process walk computes.
    public var maximumItemHeight: Double?

    public init(
        displayID: UInt32? = nil,
        deadlineSeconds: Double? = nil,
        maximumItemHeight: Double? = nil
    ) {
        self.displayID = displayID
        self.deadlineSeconds = deadlineSeconds
        self.maximumItemHeight = maximumItemHeight
    }
}

/// Whether an AXIdentifier is stable enough to key an item's identity on.
///
/// AppKit mints placeholders of the form _NS:<number> for status items whose
/// app sets no accessibility identifier. The number is an artifact of the
/// owning process's launch, so an identity keyed on it is orphaned on every
/// relaunch. The helper and the app share this rule so the nested-child
/// fallback the helper reads agrees with the in-process walk.
public func isStableAXIdentifier(_ identifier: String) -> Bool {
    !identifier.contains(/^_NS:\d+$/)
}

/// The helper's reply.
public struct AXEnumerateReply: Codable, Sendable, Equatable {
    public var items: [AXItemObservation]
    /// Whether the walk visited every application before the deadline.
    public var completed: Bool
    /// Whether the helper is trusted for Accessibility, so the app can tell
    /// "no items" from "never had permission".
    public var accessibilityTrusted: Bool
    /// Set when the walk could not run at all. items is empty in that case.
    public var errorDescription: String?

    public init(
        items: [AXItemObservation],
        completed: Bool,
        accessibilityTrusted: Bool,
        errorDescription: String? = nil
    ) {
        self.items = items
        self.completed = completed
        self.accessibilityTrusted = accessibilityTrusted
        self.errorDescription = errorDescription
    }
}
