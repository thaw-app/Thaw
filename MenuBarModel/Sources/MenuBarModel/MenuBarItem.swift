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
///
/// This is the pure-data subset of the app's `MenuBarItem` — it excludes
/// everything that requires live enumeration (AX/XPC) or persisted state
/// (`Defaults`-backed custom names), which stay behind in the app target.
public struct MenuBarItem: CustomStringConvertible, Sendable {
    /// The tag associated with this item.
    public let tag: MenuBarItemTag

    /// The item's window identifier.
    public let windowID: CGWindowID

    /// The identifier of the process that owns the item.
    public let ownerPID: pid_t

    /// The identifier of the process that created the item.
    public let sourcePID: pid_t?

    /// The item's bounds, specified in screen coordinates.
    public let bounds: CGRect

    /// The item's window title.
    public let title: String?

    /// A Boolean value that indicates whether the item is on screen.
    public let isOnScreen: Bool

    /// A Boolean value that indicates whether this item can be moved.
    public var isMovable: Bool {
        tag.isMovable
    }

    /// Layout-editor movability with experimental system-item hiding applied.
    /// When enabled on macOS 27, forced-visible system items may participate
    /// in assignment-backed section edits.
    public func isMovable(experimentalSystemItemHiding: Bool) -> Bool {
        isMovable ||
            (
                experimentalSystemItemHiding &&
                    sectionManagementPolicy.isForcedVisible
            )
    }

    /// Physical MenuBarAgent ordering with experimental system-item hiding
    /// applied. Some forced-visible items can be assigned/hidden by the
    /// experimental assertion but are not accepted as live reorder anchors.
    public func isPhysicallyOrderable(experimentalSystemItemHiding: Bool) -> Bool {
        if isControlItem, !tag.matchesVisibleControlItem {
            return false
        }
        if isMovable {
            return true
        }

        guard experimentalSystemItemHiding,
              sectionManagementPolicy.isForcedVisible,
              tag.namespace == .menuBarAgent
        else {
            return false
        }

        return true
    }

    /// A Boolean value that indicates whether this item can be hidden.
    public var canBeHidden: Bool {
        sectionManagementPolicy.canBeHidden
    }

    /// Hideability with experimental system-item hiding applied.
    public func canBeHidden(experimentalSystemItemHiding: Bool) -> Bool {
        sectionManagementPolicy(
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ).canBeHidden
    }

    /// Legacy divider-layout hideability, independent of the current host OS.
    public var canBeHiddenInLegacySectionLayout: Bool {
        tag.canBeHiddenInLegacySectionLayout && !isTransientControlCenterItem
    }

    /// The item's section-management policy, including live-item exclusions
    /// that cannot be determined from its tag alone.
    public var sectionManagementPolicy: MenuBarItemTag.SectionManagementPolicy {
        isTransientControlCenterItem ? .excluded : tag.sectionManagementPolicy
    }

    /// Section-management policy with experimental system-item hiding applied.
    public func sectionManagementPolicy(
        experimentalSystemItemHiding: Bool
    ) -> MenuBarItemTag.SectionManagementPolicy {
        let basePolicy = sectionManagementPolicy
        // Denylisted hiding-unsupported items stay forced-visible even under the
        // experimental toggle: the editor may reorder them, but they can never be
        // assigned to a hidden section. See ``MenuBarItemTag/isHidingUnsupported``.
        //
        // MenuBarAgent children are deliberately *not* excluded here. They are
        // forced visible by ``MenuBarItemTag/isMenuBarAgentItemForcedVisible``
        // in the base policy, which is what the toggle exists to override —
        // Clock, Control Center, Sound and Wi-Fi are precisely the items the
        // "hide native macOS items" setting is meant to reach. With the toggle
        // off the base policy still stands, so they stay pinned to Visible.
        guard experimentalSystemItemHiding,
              basePolicy.isForcedVisible,
              !tag.isHidingUnsupported
        else {
            return basePolicy
        }
        return .hideable
    }

    /// A Boolean value that indicates whether this item is owned by an Apple
    /// system process that cannot be reliably concealed or reordered on macOS 27.
    /// See ``MenuBarItemTag/isNonConcealableSystemItem``.
    public var isNonConcealableSystemItem: Bool {
        tag.isNonConcealableSystemItem
    }

    /// Whether this item refers to the same status item as `other`, ignoring the
    /// volatile window ID (synthetic on macOS 27) — matched by namespace/title/
    /// instance plus owning process. Use this to re-locate an item in a freshly
    /// enumerated list rather than comparing window IDs.
    public func hasSameIdentity(as other: MenuBarItem) -> Bool {
        tag.matchesIgnoringWindowID(other.tag) &&
            (sourcePID ?? ownerPID) == (other.sourcePID ?? other.ownerPID)
    }

    /// A looser match than ``hasSameIdentity(as:)``: same owning app, ignoring a
    /// possibly-changed transient title (e.g. a Control-Center-style `Item-N`).
    public func hasSameOwner(as other: MenuBarItem) -> Bool {
        tag.namespace == other.tag.namespace &&
            (sourcePID ?? ownerPID) == (other.sourcePID ?? other.ownerPID)
    }

    /// Whether AX reports this item parked outside the live menu bar band.
    ///
    /// During assertion reflows macOS 27 temporarily parks items at y≈1400+
    /// while the bar reshuffles. Their X still reads as hidden-side, which
    /// false-triggers layout-divergence detection and doomed synthetic reorders
    /// ("moving Proton to hidden also hid iStat").
    ///
    /// Uses an absolute Y threshold first: when the visible control parks with
    /// collateral, a peer-relative check falsely reports everyone as on-band.
    public func isParkedOffMenuBarBand(among peers: [MenuBarItem]) -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return true }

        // Live bar items sit in the top ~60pt of the hosting-window space;
        // assertion reflow parks collateral at y≈1400+.
        if bounds.midY > 80 {
            return true
        }

        guard let barMidY = peers.first(where: {
            $0.tag.matchesVisibleControlItem && $0.bounds.midY <= 80
        })?.bounds.midY
            ?? peers.first(where: {
                $0.isControlItem && $0.bounds.width > 8 && $0.bounds.midY <= 80
            })?.bounds.midY
        else { return false }
        // The live bar band is ~30 pt; parked items are 1000+ pt away on Y.
        return abs(bounds.midY - barMidY) > 48
    }

    /// Whether this visible-assigned item is likely collateral from an
    /// assessment-mode reflow (parked off-band, or physically adjacent to a
    /// concealed item that still appears in AX).
    public func isRestrictionReflowCollateral(
        among peers: [MenuBarItem],
        concealedIdentifiers: Set<String>
    ) -> Bool {
        if isParkedOffMenuBarBand(among: peers) {
            return true
        }
        guard !concealedIdentifiers.isEmpty else { return false }

        let sorted = MenuBarItem.sortByVisualCenter(
            peers.filter { !$0.isControlItem && $0.bounds.width > 0 }
        )
        guard let index = sorted.firstIndex(where: { $0.windowID == windowID }) else {
            return false
        }

        for (neighborIndex, neighbor) in sorted.enumerated() where concealedIdentifiers.contains(neighbor.uniqueIdentifier) {
            if abs(neighborIndex - index) <= 1 {
                return true
            }
        }
        return false
    }

    /// A Boolean value that indicates whether this item is a transient
    /// Control Center module (e.g. Live Activities) with a generic
    /// `Item-\d+` title. These are treated like screen recording indicators.
    public var isTransientControlCenterItem: Bool {
        tag.isControlCenterGenericItem && sourcePID != nil
    }

    /// A Boolean value that indicates whether this item is one of Thaw's
    /// control items.
    public var isControlItem: Bool {
        tag.isControlItem
    }

    /// A Boolean value that indicates whether this item is a "BentoBox"
    /// item owned by the Control Center.
    public var isBentoBox: Bool {
        tag.isBentoBox
    }

    /// A Boolean value that indicates whether this item is a
    /// system-created clone of an actual item, and therefore invalid
    /// for management.
    public var isSystemClone: Bool {
        tag.isSystemClone
    }

    /// The application that owns the item.
    ///
    /// - Note: In macOS 26 and later, this property always returns the
    ///   Control Center. To get the actual application that created the
    ///   item, use ``sourceApplication``.
    public var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// The application that created the item.
    ///
    /// - Note: Prior to macOS 26, this property and ``owningApplication``
    ///   are functionally equivalent.
    public var sourceApplication: NSRunningApplication? {
        guard let sourcePID else {
            return nil
        }
        return NSRunningApplication(processIdentifier: sourcePID)
    }

    /// A unique identifier for this item.
    ///
    /// Uses `namespace:title:index` only — windowID is intentionally
    /// excluded because it is transient and changes between app restarts.
    public var uniqueIdentifier: String {
        tag.tagIdentifier
    }

    /// A string to use for logging purposes.
    public var logString: String {
        "<\(tag) (windowID: \(windowID))>"
    }

    /// The auto-detected name for the item (ignores any custom override,
    /// which is `Defaults`-backed and stays behind in the app target).
    public var autoDetectedName: String {
        /// Converts "UpperCamelCase" to "Title Case".
        ///
        /// Ignores cases where a single lowercase letter immediately
        /// precedes an uppercase letter (i.e. "WiFi").
        func toTitleCase(_ s: some StringProtocol) -> String {
            String(s).replacing(/([a-z]{2})([A-Z])/) { $0.output.1 + " " + $0.output.2 }
        }

        guard !isControlItem else {
            return ThawMenuBarIdentity.displayName
        }

        lazy var fallbackName = "Menu Bar Item"

        /// Prefers the AX child / catalog name (Wi‑Fi, Clock, …) over the
        /// MenuBarAgent process name that otherwise wins via `sourceApplication`.
        func menuBarAgentDisplayName(preferredTitle: String?) -> String {
            func significant(_ value: String?) -> String? {
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            let candidates = [preferredTitle, tag.title].compactMap(significant)
            for candidate in candidates {
                if let moduleName = SystemMenuBarModuleCatalog.moduleName(matching: candidate) {
                    // Keep human AX titles ("Wi-Fi"); map opaque IDs to catalog names.
                    let useCatalogName = candidate.hasPrefix("com.apple.") || candidate.hasPrefix("BentoBox")
                    return toTitleCase(useCatalogName ? moduleName : candidate)
                }
            }
            if let preferredTitle, let match = preferredTitle.prefixMatch(of: /Hearing/) {
                return toTitleCase(match.output)
            }
            if let preferredTitle = significant(preferredTitle) {
                if preferredTitle.hasPrefix("com.apple.menuextra.") {
                    let suffix = preferredTitle.dropFirst("com.apple.menuextra.".count)
                    return toTitleCase(suffix.replacing("-", with: " "))
                }
                return toTitleCase(preferredTitle)
            }
            if let identity = significant(tag.title) {
                return toTitleCase(identity)
            }
            return fallbackName
        }

        guard let sourceApplication else {
            if tag.namespace == .menuBarAgent {
                return menuBarAgentDisplayName(preferredTitle: title)
            }
            return fallbackName
        }

        lazy var sourceName = sourceApplication.localizedName ?? sourceApplication.bundleIdentifier

        guard let title else {
            if tag.namespace == .menuBarAgent {
                return menuBarAgentDisplayName(preferredTitle: nil)
            }
            return sourceName ?? fallbackName
        }

        lazy var bestName = sourceName ?? title

        guard !isBentoBox else {
            if tag == .controlCenter {
                // On macOS 27 the host process is MenuBarAgent; prefer the
                // catalog name ("Control Center") over that process label.
                if tag.namespace == .menuBarAgent {
                    return menuBarAgentDisplayName(preferredTitle: title)
                }
                return bestName
            }
            return title
        }

        let displayName = switch tag.namespace {
        case .passwords, .weather, .textInputMenuAgent:
            toTitleCase(bestName.replacing(/Menu.*/, with: ""))
        case .menuBarAgent:
            menuBarAgentDisplayName(preferredTitle: title)
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

    /// A textual representation of the item.
    public var description: String {
        "\(tag) (windowID: \(windowID))"
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    @MainActor
    public init(uncheckedItemWindow itemWindow: WindowInfo, instanceIndex: Int = 0) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow, instanceIndex: instanceIndex)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = itemWindow.ownerPID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.isOnScreen = itemWindow.isOnScreen
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @MainActor
    public init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?, instanceIndex: Int = 0) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow, sourcePID: sourcePID, instanceIndex: instanceIndex)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = sourcePID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.isOnScreen = itemWindow.isOnScreen
    }
}

// MARK: - MenuBarItem Init

public extension MenuBarItem {
    init(tag: MenuBarItemTag, windowID: CGWindowID, ownerPID: pid_t, sourcePID: pid_t?, bounds: CGRect, title: String?, isOnScreen: Bool) {
        self.tag = tag
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.sourcePID = sourcePID
        self.bounds = bounds
        self.title = title
        self.isOnScreen = isOnScreen
    }
}

// MARK: MenuBarItem: Equatable

extension MenuBarItem: Equatable {
    public static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
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

extension MenuBarItem: Hashable {
    public func hash(into hasher: inout Hasher) {
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

// MARK: - MenuBarItemTag Helper

extension MenuBarItemTag {
    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    @MainActor
    init(uncheckedItemWindow itemWindow: WindowInfo, instanceIndex: Int = 0) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow)
        self.title = itemWindow.title ?? ""
        self.windowID = itemWindow.windowID
        self.instanceIndex = instanceIndex
    }

    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @MainActor
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?, instanceIndex: Int = 0) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        self.title = itemWindow.title ?? ""
        self.windowID = itemWindow.windowID
        self.instanceIndex = instanceIndex
    }
}

// MARK: - MenuBarItemTag.Namespace Helper

extension MenuBarItemTag.Namespace {
    private static let uuidCache = OSAllocatedUnfairLock<[CGWindowID: UUID]>(initialState: [:])

    @MainActor
    public static func pruneUUIDCache(keeping validWindowIDs: Set<CGWindowID>) {
        uuidCache.withLock { $0 = $0.filter { validWindowIDs.contains($0.key) } }
    }

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    @MainActor
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        //
        // Use the name of the owning process as a fallback. The non-localized
        // name seems less likely to change, so let's prefer it as a (somewhat)
        // stable identifier.
        if let app = itemWindow.owningApplication {
            self = .optional(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
        } else {
            self = .optional(itemWindow.ownerName)
        }
    }

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @MainActor
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        // Check for our own control items by title and owner.
        // On macOS 26 these are owned by Control Center; on macOS 27+ by MenuBarAgent.
        if let title = itemWindow.title, title.hasPrefix("Thaw.ControlItem.") {
            let ccBundleID = SharedConstants.menuBarHostingBundleID
            if itemWindow.owningApplication?.bundleIdentifier == ccBundleID ||
                itemWindow.ownerPID == ProcessInfo.processInfo.processIdentifier
            {
                self = .thaw
                return
            }
        }

        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        if let sourcePID, let app = NSRunningApplication(processIdentifier: sourcePID) {
            self = .optional(app.bundleIdentifier ?? app.localizedName)
        } else if let app = itemWindow.owningApplication {
            // Fallback: use the owning application's bundle ID or name.
            // This covers cases where the source PID doesn't resolve
            // (e.g. helper processes) but the owner is known.
            self = .optional(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
        } else if let ownerName = itemWindow.ownerName {
            // Last resort: use the process name as a stable identifier.
            self = .string(ownerName)
        } else if let uuid = Self.uuidCache.withLock({ $0[itemWindow.windowID] }) {
            self = .uuid(uuid)
        } else {
            let uuid = UUID()
            Self.uuidCache.withLock { $0[itemWindow.windowID] = uuid }
            self = .uuid(uuid)
        }
    }
}
