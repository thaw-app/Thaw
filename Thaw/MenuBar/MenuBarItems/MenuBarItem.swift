//
//  MenuBarItem.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import os.lock

/// A structural representation of a menu bar item.
nonisolated struct MenuBarItem: CustomStringConvertible {
    let tag: MenuBarItemTag

    let windowID: CGWindowID

    /// The identifier of the process that owns the item.
    let ownerPID: pid_t

    /// The identifier of the process that created the item.
    let sourcePID: pid_t?

    /// The item's bounds, specified in screen coordinates.
    let bounds: CGRect

    let title: String?

    /// A Boolean value that indicates whether the item is on screen.
    let isOnScreen: Bool

    /// Read from the window server, falling back to the snapshot.
    var liveBounds: CGRect {
        Bridging.getWindowBounds(for: windowID) ?? bounds
    }

    /// The gate that refuses to move an item, named so refusals can be
    /// logged (#905).
    enum ImmovabilityReason {
        /// macOS doesn't allow it to move (Clock, Control Center).
        case prohibitedSystemItem
        /// A generic Control Center slot (`Item-N`) with no resolved source.
        /// Drag events to Control Center for it time out.
        case unresolvedControlCenterPlaceholder

        var logDescription: String {
            switch self {
            case .prohibitedSystemItem:
                "static immovable system item"
            case .unresolvedControlCenterPlaceholder:
                "Control Center generic slot with unresolved source PID; owning app unknown this cycle"
            }
        }
    }

    /// Whether synthetic move events are posted to the window's owner.
    ///
    /// Also decides whether an unresolved item is movable at all. See
    /// ``Defaults/Key/postMoveEventsToWindowOwner``.
    static var postsMoveEventsToWindowOwner: Bool {
        (Defaults.object(forKey: .postMoveEventsToWindowOwner) as? Bool)
            ?? Defaults.DefaultValue.postMoveEventsToWindowOwner
    }

    /// The reason this item cannot be moved, or `nil` when it can.
    ///
    /// Pure, never reads defaults. See also
    /// ``isMovableAddressingWindowOwner``.
    var immovabilityReason: ImmovabilityReason? {
        if !tag.isMovable {
            return .prohibitedSystemItem
        }
        if tag.isControlCenterGenericItem, sourcePID == nil {
            return .unresolvedControlCenterPlaceholder
        }
        return nil
    }

    /// Whether this item can be moved given where its events will be sent.
    ///
    /// Addressing the window's owner lifts
    /// ``ImmovabilityReason/unresolvedControlCenterPlaceholder``, since the
    /// owning app no longer matters. Separate so ``isMovable`` stays pure.
    var isMovableAddressingWindowOwner: Bool {
        switch immovabilityReason {
        case nil:
            true
        case .unresolvedControlCenterPlaceholder:
            Self.postsMoveEventsToWindowOwner
        case .prohibitedSystemItem:
            false
        }
    }

    /// Whether the layout editor may start a drag of this item.
    ///
    /// An unresolved Control Center slot parked off every display never takes
    /// a drag, even one addressed to Control Center (#1190). It waits for an
    /// AX alias instead.
    func isDraggableInLayoutEditor(displayBounds: [CGRect]) -> Bool {
        guard isMovableAddressingWindowOwner else {
            return false
        }
        guard immovabilityReason == .unresolvedControlCenterPlaceholder else {
            return true
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return displayBounds.contains { $0.contains(center) }
    }

    /// Whether a drop may be placed beside this item.
    ///
    /// An unresolved Control Center slot can sit parked far from where the
    /// editor shows it, so a drop beside it lands off-screen and reverts.
    var isLayoutDropAnchor: Bool {
        immovabilityReason != .unresolvedControlCenterPlaceholder
    }

    /// A Boolean value that indicates whether this item can be moved.
    ///
    /// Defined through ``immovabilityReason`` so they can't disagree.
    var isMovable: Bool {
        immovabilityReason == nil
    }

    /// A Boolean value that indicates whether this item can be hidden.
    var canBeHidden: Bool {
        tag.canBeHidden && !isTransientControlCenterItem
    }

    /// A transient Control Center module (e.g. Live Activities) with a
    /// generic `Item-\d+` title. Treated like screen recording indicators.
    var isTransientControlCenterItem: Bool {
        tag.isControlCenterGenericItem && sourcePID != nil
    }

    /// The source PID never resolved, so the namespace fell back to Control
    /// Center, which owns every hosted item on macOS 26. Nothing keyed by
    /// this identifier can be trusted.
    var hasProvisionalIdentity: Bool {
        sourcePID == nil && tag.namespace == .controlCenter
    }

    /// A Boolean value that indicates whether this item is one of Ice's
    /// control items.
    var isControlItem: Bool {
        tag.isControlItem
    }

    /// A Boolean value that indicates whether this item is a "BentoBox"
    /// item owned by the Control Center.
    var isBentoBox: Bool {
        tag.isBentoBox
    }

    /// A Boolean value that indicates whether this item is a
    /// system-created clone of an actual item, and therefore invalid
    /// for management.
    var isSystemClone: Bool {
        tag.isSystemClone
    }

    /// The application that owns the item.
    ///
    /// - Note: In macOS 26 and later, this property always returns the
    ///   Control Center. To get the actual application that created the
    ///   item, use ``sourceApplication``.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// The application that created the item.
    ///
    /// - Note: Prior to macOS 26, this property and ``owningApplication``
    ///   are functionally equivalent.
    var sourceApplication: NSRunningApplication? {
        guard let sourcePID else {
            return nil
        }
        return NSRunningApplication(processIdentifier: sourcePID)
    }

    /// Ignores the custom name.
    var autoDetectedName: String {
        /// Converts "UpperCamelCase" to "Title Case".
        ///
        /// Ignores cases where a single lowercase letter immediately
        /// precedes an uppercase letter (i.e. "WiFi").
        func toTitleCase(_ s: some StringProtocol) -> String {
            String(s).replacing(/([a-z]{2})([A-Z])/) { $0.output.1 + " " + $0.output.2 }
        }

        guard !isControlItem else {
            return Constants.displayName
        }

        lazy var fallbackName = "Menu Bar Item"

        guard let sourceApplication else {
            // Use the remembered name while the accessibility scan runs,
            // not "Menu Bar Item".
            return MenuBarItemNameMemory.rememberedName(for: self) ?? fallbackName
        }

        lazy var sourceName = sourceApplication.localizedName ?? sourceApplication.bundleIdentifier

        guard let title else {
            return sourceName ?? fallbackName
        }

        lazy var bestName = sourceName ?? title

        guard !isBentoBox else {
            if tag == .controlCenter {
                return bestName
            }
            return title
        }

        let displayName = switch tag.namespace {
        case .passwords, .weather, .textInputMenuAgent:
            toTitleCase(bestName.replacing(/Menu.*/, with: ""))
        case .controlCenter:
            if let match = title.prefixMatch(of: /Hearing/) {
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        case .systemUIServer:
            if let match = title.firstMatch(of: /TimeMachine/) {
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        default:
            bestName
        }

        if UUID(uuidString: displayName) != nil, let sourceName {
            return "\(sourceName) (\(displayName))"
        }

        return displayName
    }

    /// A name associated with the item, suited for display.
    var displayName: String {
        if let custom = customName, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }

        // Spacers carry their autosave name as the window title.
        if MenuBarSpacerManager.isSpacerTag(tag) {
            return String(localized: "Spacer")
        }

        return autoDetectedName
    }

    var description: String {
        "\(displayName) (\(tag))"
    }

    /// `namespace:title:index`; windowID changes between restarts.
    var uniqueIdentifier: String {
        if tag.instanceIndex > 0 {
            return "\(tag.namespace):\(tag.title):\(tag.instanceIndex)"
        }
        return "\(tag.namespace):\(tag.title)"
    }

    /// Custom name for this item (persisted).
    var customName: String? {
        get {
            let names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
            return names[uniqueIdentifier]
        }
        set {
            var names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
            if let newValue, !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                names[uniqueIdentifier] = newValue
            } else {
                names.removeValue(forKey: uniqueIdentifier)
            }
            Defaults.set(names, forKey: .menuBarItemCustomNames)
        }
    }

    var logString: String {
        "<\(tag) (windowID: \(windowID))>"
    }
}

// MARK: - UnresolvedPlaceholderAlias

/// Re-tags an `unresolvedControlCenterPlaceholder` with the app identity
/// the AX tree already names, for one Layout editor drag (#905).
///
/// The AppKit side lives in
/// `LayoutBarItemView.aliasForUnresolvedControlCenterPlaceholder()`.
nonisolated enum UnresolvedPlaceholderAlias {
    /// The bundle identifier carried by an AX identity, when one of its
    /// attributes names a non-host third-party app.
    ///
    /// Checks `AXIdentifier`, then `AXTitle`, then `AXHelp`. Rejects values
    /// without a dot, host processes, and Thaw.
    static nonisolated func appBundleID(
        from identity: AXIdentityCatalog.AXItemIdentity?,
        excluding hostBundleIDs: Set<String>,
        thawBundleID: String
    ) -> String? {
        guard let identity else { return nil }
        for candidate in [identity.identifier, identity.title, identity.help] {
            guard let candidate, candidate.contains(".") else { continue }
            if hostBundleIDs.contains(candidate) || candidate == thawBundleID {
                continue
            }
            return candidate
        }
        return nil
    }

    /// Returns `nil` unless `item` is an unresolved placeholder, so no other
    /// immovability case can be re-tagged.
    static nonisolated func aliasedItem(
        for item: MenuBarItem,
        appBundleID: String,
        hostPID: pid_t
    ) -> MenuBarItem? {
        guard item.immovabilityReason == .unresolvedControlCenterPlaceholder else { return nil }
        let aliasedTag = MenuBarItemTag(
            namespace: .string(appBundleID),
            title: item.tag.title,
            windowID: item.windowID,
            instanceIndex: item.tag.instanceIndex
        )
        return MenuBarItem(
            tag: aliasedTag,
            windowID: item.windowID,
            ownerPID: item.ownerPID,
            sourcePID: hostPID,
            bounds: item.bounds,
            title: item.title,
            isOnScreen: item.isOnScreen
        )
    }
}

// MARK: - MenuBarItem Init

// The memberwise initializer is synthesized; tests and fixtures use it.

// MARK: MenuBarItem: Equatable

nonisolated extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.tag == rhs.tag &&
            lhs.windowID == rhs.windowID &&
            lhs.ownerPID == rhs.ownerPID &&
            lhs.sourcePID == rhs.sourcePID &&
            lhs.bounds == rhs.bounds &&
            lhs.title == rhs.title &&
            lhs.isOnScreen == rhs.isOnScreen
    }
}

// MARK: MenuBarItem: Hashable

nonisolated extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(sourcePID)
        hasher.combine(bounds.origin.x)
        hasher.combine(bounds.origin.y)
        hasher.combine(bounds.size.width)
        hasher.combine(bounds.size.height)
        hasher.combine(title)
        hasher.combine(isOnScreen)
    }
}
