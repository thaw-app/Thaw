//
//  MenuBarItem.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// The pure-data part of a menu bar item. Live enumeration and
/// Defaults-backed custom names stay in the app target.
public struct MenuBarItem: CustomStringConvertible, Sendable, Codable {
    public let tag: MenuBarItemTag

    public let windowID: CGWindowID

    public let ownerPID: pid_t

    /// The process that created the item.
    public let sourcePID: pid_t?

    /// In screen coordinates.
    public let bounds: CGRect

    public let title: String?

    public let isOnScreen: Bool

    public var isMovable: Bool {
        tag.isMovable
    }

    /// With experimental hiding on, forced-visible system items may join
    /// assignment-backed section edits.
    public func isMovable(experimentalSystemItemHiding: Bool) -> Bool {
        isMovable ||
            (
                experimentalSystemItemHiding &&
                    sectionManagementPolicy.isForcedVisible &&
                    !tag.isAgentUngoverned
            )
    }

    /// Why a physical move was refused. Only requiresExperimentalHiding is
    /// actionable by the user; the rest are final.
    public enum OrderabilityRefusal: Sendable, Equatable {
        /// One of Thaw's own control items, but not the visible one.
        case hiddenControlItem
        /// macOS 27's overflow chevron, vended through AX like an extra but
        /// with nothing to grab and no weight to write.
        case nativeOverflowControl
        /// Clock, Control Center, Siri.
        case systemAnchored
        /// A forced-visible MenuBarAgent module, movable once experimental
        /// hiding is on.
        case requiresExperimentalHiding
        /// Forced-visible outside the .menuBarAgent namespace, so the
        /// experimental assertion cannot reach it.
        case notAgentManaged
    }

    /// Nil when orderable. isPhysicallyOrderable(experimentalSystemItemHiding:)
    /// is built on this.
    public func orderabilityRefusal(
        experimentalSystemItemHiding: Bool
    ) -> OrderabilityRefusal? {
        if isControlItem, !tag.matchesVisibleControlItem {
            return .hiddenControlItem
        }
        // Before isMovable: the tag reports the chevron movable, and boundary
        // repair would then pick it as a strand and fail on its bounds.
        if isNativeOverflowControl {
            return .nativeOverflowControl
        }
        if isMovable {
            return nil
        }

        if sectionManagementPolicy.isForcedVisible {
            // Forced-visible items move only under the experimental assertion
            // and only when the agent lays them out.
            if tag.namespace == .menuBarAgent {
                return experimentalSystemItemHiding ? nil : .requiresExperimentalHiding
            }
            return .notAgentManaged
        }

        return .systemAnchored
    }

    /// Some forced-visible items can be hidden by the experimental assertion
    /// but are not accepted as live reorder anchors.
    public func isPhysicallyOrderable(experimentalSystemItemHiding: Bool) -> Bool {
        orderabilityRefusal(experimentalSystemItemHiding: experimentalSystemItemHiding) == nil
    }

    public var canBeHidden: Bool {
        sectionManagementPolicy.canBeHidden
    }

    public func canBeHidden(experimentalSystemItemHiding: Bool) -> Bool {
        sectionManagementPolicy(
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ).canBeHidden
    }

    /// Legacy divider-layout hideability, independent of the current host OS.
    public var canBeHiddenInLegacySectionLayout: Bool {
        tag.canBeHiddenInLegacySectionLayout && !isTransientControlCenterItem
    }

    /// Includes live-item exclusions the tag alone cannot express.
    public var sectionManagementPolicy: MenuBarItemTag.SectionManagementPolicy {
        isTransientControlCenterItem ? .excluded : tag.sectionManagementPolicy
    }

    public func sectionManagementPolicy(
        experimentalSystemItemHiding: Bool
    ) -> MenuBarItemTag.SectionManagementPolicy {
        let basePolicy = sectionManagementPolicy
        // Only the host-pinned items (Clock, Control Center, Siri) become
        // hideable. Hiding-unsupported and agent-ungoverned items stay
        // forced-visible, since a hidden assignment could never be carried out.
        guard experimentalSystemItemHiding,
              tag.isLayoutAnchoredSystemItem,
              basePolicy.isForcedVisible,
              !tag.isHidingUnsupported,
              !tag.isAgentUngoverned
        else {
            return basePolicy
        }
        return .hideable
    }

    /// Owned by an Apple process that cannot be reliably concealed or reordered
    /// on macOS 27.
    public var isNonConcealableSystemItem: Bool {
        tag.isNonConcealableSystemItem
    }

    /// Same tag and process, ignoring the volatile window ID (synthetic on
    /// macOS 27). Use it to re-locate an item in a fresh list.
    public func hasSameIdentity(as other: MenuBarItem) -> Bool {
        tag.matchesIgnoringWindowID(other.tag) &&
            (sourcePID ?? ownerPID) == (other.sourcePID ?? other.ownerPID)
    }

    /// A looser match than hasSameIdentity(as:): same owning app, ignoring a
    /// possibly-changed transient title (e.g. a Control-Center-style Item-N).
    public func hasSameOwner(as other: MenuBarItem) -> Bool {
        tag.namespace == other.tag.namespace &&
            (sourcePID ?? ownerPID) == (other.sourcePID ?? other.ownerPID)
    }

    /// Whether AX reports this item parked outside the live bar. During
    /// assertion reflows macOS 27 parks items around y 1400 with a hidden-side
    /// X, which would falsely trigger divergence detection and reorders.
    ///
    /// The absolute Y check comes first: when the visible control parks too,
    /// a peer-relative check would call everyone on-band.
    public func isParkedOffMenuBarBand(among peers: [MenuBarItem]) -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return true }

        // A parked item reports the leading-edge sentinel (origin.x == -1) in
        // the bar's own Y band, so the Y checks below miss it.
        if bounds.origin.x == -1 {
            return true
        }

        // Live bar items sit in the top 60 pt or so of the hosting-window space.
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
        // The live band is about 30 pt; parked items are 1000+ pt away on Y.
        return abs(bounds.midY - barMidY) > 48
    }

    /// A transient Control Center module (such as Live Activities) with a
    /// generic Item-N title, treated like a screen recording indicator.
    public var isTransientControlCenterItem: Bool {
        tag.isControlCenterGenericItem && sourcePID != nil
    }

    public var isControlItem: Bool {
        tag.isControlItem
    }

    /// A Control Center BentoBox item.
    public var isBentoBox: Bool {
        tag.isBentoBox
    }

    /// A system-created clone of a real item, never managed.
    public var isSystemClone: Bool {
        tag.isSystemClone
    }

    /// macOS 27's overflow chevron, never in any section. Check it wherever
    /// isSystemClone is checked.
    public var isNativeOverflowControl: Bool {
        tag.isNativeOverflowControl
    }

    /// - Note: In macOS 26 and later this is always Control Center; use
    ///   sourceApplication for the app that created the item.
    public var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// The application that created the item.
    public var sourceApplication: NSRunningApplication? {
        guard let sourcePID else {
            return nil
        }
        return NSRunningApplication(processIdentifier: sourcePID)
    }

    /// namespace:title:index only; windowID changes across app restarts.
    public var uniqueIdentifier: String {
        tag.tagIdentifier
    }

    public var logString: String {
        "<\(tag) (windowID: \(windowID))>"
    }

    /// Ignores any custom name, which lives in the app target.
    public var autoDetectedName: String {
        /// Converts "UpperCamelCase" to "Title Case", but leaves a single
        /// lowercase letter before an uppercase one alone ("WiFi").
        func toTitleCase(_ s: some StringProtocol) -> String {
            String(s).replacing(/([a-z]{2})([A-Z])/) { $0.output.1 + " " + $0.output.2 }
        }

        guard !isControlItem else {
            return ThawMenuBarIdentity.displayName
        }

        lazy var fallbackName = "Menu Bar Item"

        /// Prefers the AX or catalog name (Wi-Fi, Clock) over the MenuBarAgent
        /// process name that sourceApplication would give.
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
                // A Control Center control that published no description falls
                // back to its own identifier, which is a raw dotted path.
                if let chrono = ChronoControlIdentity(axIdentifier: identity) {
                    return chrono.derivedDisplayName
                }
                return toTitleCase(identity)
            }
            return fallbackName
        }

        // For items with no resolvable creator, such as restored conceal
        // snapshots, which carry no PID. The namespace is the creator's bundle
        // identifier, which beats "Menu Bar Item".
        var namespaceDerivedName: String? {
            guard case let .string(bundleIdentifier) = tag.namespace else {
                return nil
            }
            if
                let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first,
                let localizedName = running.localizedName
            {
                return localizedName
            }
            // Installed but not running: use the Finder name.
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return FileManager.default.displayName(atPath: url.path)
                    .replacing(/\.app$/, with: "")
            }
            guard let component = bundleIdentifier.split(separator: ".").last else {
                return nil
            }
            return toTitleCase(component.prefix(1).uppercased() + component.dropFirst())
        }

        guard let sourceApplication else {
            if tag.namespace == .menuBarAgent {
                return menuBarAgentDisplayName(preferredTitle: title)
            }
            return namespaceDerivedName ?? fallbackName
        }

        lazy var sourceName = sourceApplication.localizedName ?? sourceApplication.bundleIdentifier

        guard let title else {
            if tag.namespace == .menuBarAgent {
                return menuBarAgentDisplayName(preferredTitle: nil)
            }
            return sourceName ?? namespaceDerivedName ?? fallbackName
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

    /// Declared in the main body so it suppresses the synthesized memberwise
    /// initializer, which would collide with it.
    public init(tag: MenuBarItemTag, windowID: CGWindowID, ownerPID: pid_t, sourcePID: pid_t?, bounds: CGRect, title: String?, isOnScreen: Bool) {
        self.tag = tag
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.sourcePID = sourcePID
        self.bounds = bounds
        self.title = title
        self.isOnScreen = isOnScreen
    }

    public var description: String {
        "\(tag) (windowID: \(windowID))"
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
