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
    /// The tag associated with this item.
    let tag: MenuBarItemTag

    /// The item's window identifier.
    let windowID: CGWindowID

    /// The identifier of the process that owns the item.
    let ownerPID: pid_t

    /// The identifier of the process that created the item.
    let sourcePID: pid_t?

    /// The item's bounds, specified in screen coordinates.
    let bounds: CGRect

    /// The item's window title.
    let title: String?

    /// A Boolean value that indicates whether the item is on screen.
    let isOnScreen: Bool

    /// The item's current bounds read from the Window Server, falling back
    /// to the snapshot taken when this struct was created if the window is
    /// gone or the query fails.
    var liveBounds: CGRect {
        Bridging.getWindowBounds(for: windowID) ?? bounds
    }

    /// The gate that refuses to move an item.
    ///
    /// A refusal used to be undiagnosable: the layout editor showed a
    /// generic alert, nothing was logged, and a report could not tell a
    /// static macOS prohibition from an identity-resolution failure (#905).
    /// Naming the gate is what lets the refusal sites log the condition the
    /// decision was made on.
    enum ImmovabilityReason {
        /// The tag is on the static list of system items macOS does not
        /// allow to be moved (Clock, Control Center, Screen Sharing).
        case prohibitedSystemItem
        /// A generic Control Center slot (`Item-N`) whose source process
        /// never resolved. The owning app is unknown this cycle, and
        /// posting drag events to Control Center for a placeholder times
        /// out, so the item is parked rather than offered and failed.
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
    /// Read here as well as in the manager because it decides whether an
    /// item with an unresolved owner is movable at all, not merely where
    /// its events go. See ``Defaults/Key/postMoveEventsToWindowOwner``.
    static var postsMoveEventsToWindowOwner: Bool {
        (Defaults.object(forKey: .postMoveEventsToWindowOwner) as? Bool)
            ?? Defaults.DefaultValue.postMoveEventsToWindowOwner
    }

    /// The reason this item cannot be moved, or `nil` when it can.
    ///
    /// Pure: derived from the item alone, never from user defaults, so it
    /// answers the same way in a test as on a bar. Callers that can lift a
    /// reason by changing *how* they move consult
    /// ``isMovableAddressingWindowOwner`` instead.
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
    /// ``ImmovabilityReason/unresolvedControlCenterPlaceholder`` exists
    /// because posting drag events to Control Center for a slot with no
    /// known owner was observed to time out — a statement about events aimed
    /// at an owning app that did not exist. When events address the window's
    /// owner instead, the move no longer needs to know who owns the item, so
    /// that reason stops applying. Every other reason still does: a
    /// prohibited system item is prohibited wherever the events go.
    ///
    /// Separate from ``isMovable`` so the pure answer stays pure and only
    /// the two gates that actually dispatch a move read the flag.
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

    /// A Boolean value that indicates whether this item can be moved.
    ///
    /// Defined through ``immovabilityReason`` so the answer and the gate a
    /// diagnostic names can never disagree.
    var isMovable: Bool {
        immovabilityReason == nil
    }

    /// A Boolean value that indicates whether this item can be hidden.
    var canBeHidden: Bool {
        tag.canBeHidden && !isTransientControlCenterItem
    }

    /// A Boolean value that indicates whether this item is a transient
    /// Control Center module (e.g. Live Activities) with a generic
    /// `Item-\d+` title. These are treated like screen recording indicators.
    var isTransientControlCenterItem: Bool {
        tag.isControlCenterGenericItem && sourcePID != nil
    }

    /// A Boolean value that indicates whether this item's identifier is only
    /// provisional: its source PID never resolved, so the namespace fell back
    /// to the owner of the window — Control Center, which on macOS 26 owns the
    /// window of every hosted status item. The same item is named after its
    /// real app on the next cycle that resolves it, so nothing keyed by the
    /// identifier (a saved position, a section assignment) can be trusted.
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

    /// The auto-detected name for the item (ignores custom name).
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
            // The source process has not resolved yet. Fall back to the name
            // this item resolved to on an earlier pass or launch rather than
            // labelling everything on the bar "Menu Bar Item" for the few
            // seconds the accessibility scan takes (#956).
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
        // Custom name takes precedence over auto-detected name
        if let custom = customName, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }

        return autoDetectedName
    }

    /// A textual representation of the item.
    var description: String {
        "\(displayName) (\(tag))"
    }

    /// A unique identifier for storing custom names.
    ///
    /// Uses `namespace:title:index` only — windowID is intentionally
    /// excluded because it is transient and changes between app restarts,
    /// which would cause persisted custom names to be lost.
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

    /// A string to use for logging purposes.
    var logString: String {
        "<\(tag) (windowID: \(windowID))>"
    }
}

// MARK: - UnresolvedPlaceholderAlias

/// Re-tagging an `unresolvedControlCenterPlaceholder` with an app-owned
/// identity, so a Layout editor drag can proceed against a slot the source-PID
/// cache has not resolved this cycle.
///
/// The catalog (#905) holds both the app-owned form
/// `at.obdev.littlesnitch.agent:Item-0` and the live Control-Center-hosted
/// slot form `com.apple.controlcenter:Item-0` for the same physical item.
/// While the cache has not caught up, the slot is parked by the
/// `unresolvedControlCenterPlaceholder` gate, the Layout editor's drag is
/// refused, and the user sees a generic alert even when the AX tree already
/// names the owning app. This alias promotes the slot to its app-owned
/// identity for the duration of one drag: `isMovable` becomes true, the
/// `move(...)` inner guard lets synthetic events through, and the post-move
/// `cacheItemsRegardless` writes the app-owned identifier into
/// `savedSectionOrder` once the cache resolves (or the drag lands AppKit-side
/// via the slot's own autosave position while the cache catches up).
///
/// The pure halves below are unit-testable; the AppKit coupling lives in
/// `LayoutBarItemView.aliasForUnresolvedControlCenterPlaceholder()`.
nonisolated enum UnresolvedPlaceholderAlias {
    /// The bundle identifier carried by an AX identity, when one of its
    /// attributes names a non-host third-party app.
    ///
    /// Order: `AXIdentifier` (e.g. `com.apple.menuextra.wifi` for a hosted
    /// module, `at.obdev.littlesnitch.agent` for a third-party agent), then
    /// `AXTitle`, then `AXHelp` — the latter two carry the bundle ID when a
    /// widget only publishes its title/help string. A candidate is rejected
    /// when it lacks the bundle-identifier shape (no dot, following the
    /// marker-pair convention in `MarkerPairResolver`), or names one of the
    /// host processes or Thaw itself.
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

    /// An aliased `MenuBarItem` whose tag carries the app-owned namespace and
    /// whose `sourcePID` is the resolved owner. Returns `nil` unless `item` is
    /// exactly the gate this alias is for, so callers cannot re-tag any other
    /// immovability case.
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

//
// The memberwise initializer is synthesized rather than written out. It used to
// be explicit because the two unchecked initializers lived in the struct body
// and suppressed synthesis; those moved to MenuBarItem+Enumeration.swift, so
// the compiler now produces an identical one -- same parameters, same order,
// same internal access. Tests and fixtures construct items through it.

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
