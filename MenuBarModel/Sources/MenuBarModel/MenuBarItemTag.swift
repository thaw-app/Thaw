//
//  MenuBarItemTag.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import Synchronization

// MARK: - MenuBarItemTag

/// An identifier for a menu bar item.
public struct MenuBarItemTag: Hashable, CustomStringConvertible, Sendable, Codable {
    /// Shared classification for hiding, section assignment, and layout caching.
    /// Use its capabilities instead of duplicating system-item exceptions.
    public enum SectionManagementPolicy: Equatable, Sendable {
        /// The item can be assigned to and ordered within any section.
        case hideable

        /// The item must remain visible, but still belongs in the layout cache.
        case forcedVisible

        /// The item is not managed by the section layout.
        case excluded

        public var canBeHidden: Bool {
            self == .hideable
        }

        public var isVisibleInLayout: Bool {
            self != .excluded
        }

        public var isForcedVisible: Bool {
            self == .forcedVisible
        }
    }

    /// The namespace of the item identified by this tag.
    public let namespace: Namespace

    /// The title of the item identified by this tag.
    public let title: String

    /// The window identifier of the item identified by this tag.
    public let windowID: CGWindowID?

    /// The index of the item within its (namespace, title) group.
    public let instanceIndex: Int

    /// Includes Thaw-owned items as well as Apple system hosts.
    public var isSystemItem: Bool {
        switch namespace {
        case .controlCenter, .systemUIServer, .textInputMenuAgent, .weather, .passwords, .screenCaptureUI, .ssMenuAgent, .thaw, .gamePolicyAgent:
            return true
        case .menuBarAgent:
            return true
        case .string, .uuid, .null:
            return false
        }
    }

    /// Apple system items resist concealment and synthetic drags on macOS 27; exclude them from divergence checks to avoid reapply loops.
    /// Matches all com.apple.* owners except app-owned helpers, which can be concealed per bundle.
    public var isNonConcealableSystemItem: Bool {
        let owner = namespace.description
        if owner.hasPrefix("com.apple."), Self.isAppleAppOwnedBundle(owner) {
            return false
        }
        return isSystemItem || owner.hasPrefix("com.apple.")
    }

    /// Agents in /System/Library/CoreServices cannot conceal hosted items individually; other Apple bundles are app-owned.
    /// Cache the running process's classification because it is stable per bundle.
    public static func isAppleAppOwnedBundle(_ bundleIdentifier: String) -> Bool {
        if let known = appleAppOwnedBundles.withLock({ $0[bundleIdentifier] }) {
            return known
        }
        guard let url = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?.bundleURL
        else {
            // Not running: answer conservatively, and ask again next time.
            return false
        }
        let answer = !url.standardizedFileURL.path.hasPrefix("/System/Library/CoreServices/")
        appleAppOwnedBundles.withLock { $0[bundleIdentifier] = answer }
        return answer
    }

    private static let appleAppOwnedBundles = Mutex<[String: Bool]>([:])

    /// These Control Center modules remain hideable despite isNonConcealableSystemItem.
    /// Wi-Fi and Bluetooth use the restriction's system-item index; others use per-host visibility preferences.
    public var isControlCenterGovernable: Bool {
        SystemMenuBarModuleCatalog.controlCenterKeysByMenuExtraTitle[title] != nil
    }

    /// Preferred-position keys avoid restriction collateral-hiding; Sound's module:Sound key is its only hiding path, unlike Focus and Now Playing.
    /// Exclude Control Center to preserve access to settings, and Clock because weight 0 appears anchored.
    public static let positionManageableMenuBarAgentTitles: Set<String> = [
        "com.apple.menuextra.focusmode",
        "com.apple.menuextra.now-playing",
        "com.apple.menuextra.sound",
    ]

    /// Whether this MenuBarAgent child has a stable preferred-position hiding
    /// path.
    public var isPositionManageableMenuBarAgentItem: Bool {
        namespace == .menuBarAgent && Self.positionManageableMenuBarAgentTitles.contains(title)
    }

    /// Whether a persisted namespace:title[:instance] identifier names one
    /// of the MenuBarAgent extras that has a preferred-position hiding path.
    public static func isPositionManageableMenuBarAgentIdentifier(_ identifier: String) -> Bool {
        let prefix = "\(Namespace.menuBarAgent.description):"
        return positionManageableMenuBarAgentTitles.contains {
            identifier == "\(prefix)\($0)" || identifier.hasPrefix("\(prefix)\($0):")
        }
    }

    /// macOS 27 owns MenuBarAgent children as one family, so they stay Visible unless a real hiding path exists.
    /// Preferred-position extras and Control Center-governable modules are exceptions.
    public var isMenuBarAgentItemForcedVisible: Bool {
        namespace == .menuBarAgent
            && !isPositionManageableMenuBarAgentItem
            && !isControlCenterGovernable
    }

    /// Rejects stale Hidden assignments before the live AX child appears, preserving extras with real hiding paths.
    public static func isMenuBarAgentForcedVisibleIdentifier(_ identifier: String) -> Bool {
        let prefix = "\(Namespace.menuBarAgent.description):"
        guard identifier.hasPrefix(prefix) else { return false }
        if isPositionManageableMenuBarAgentIdentifier(identifier) {
            return false
        }
        // Per-host preferences make these Hidden assignments user intent, not stale entries.
        let title = String(identifier.dropFirst(prefix.count).split(separator: ":").first ?? "")
        if SystemMenuBarModuleCatalog.controlCenterKeysByMenuExtraTitle[title] != nil {
            return false
        }
        return true
    }

    /// Direct-download iStat Menus ID; canonicalIStatMetricTitle prevents live values from churning layout keys.
    /// Prefer hasDynamicMetricTitles(_:) because the app ships under multiple bundle IDs.
    public static let iStatMenusStatusBundleID = "com.bjango.istatmenus.status"

    /// Live metric titles need stable identities; prefix/suffix matching covers multiple builds, including iStat Menus Setapp.
    /// - Important: Add only apps with live values; digit replacement would collapse ordinal titles such as "Fan 1" and "Fan 2".
    private static let dynamicMetricTitleBundleMatchers: [(prefix: String, suffix: String)] = [
        (prefix: "com.bjango.istatmenus", suffix: ".status"),
        (prefix: "eu.exelban.Stats", suffix: ""),
        // OpenUsage service names contain letters, so neutralizing quota digits keeps items distinct.
        (prefix: "com.robinebers.openusage", suffix: ""),
        // Macs Fan Control's temperature titles map to "#°C" so saved order matches and boundary repair can proceed.
        (prefix: "com.crystalidea.macsfancontrol", suffix: ""),
    ]

    /// Whether bundleID belongs to an app whose status-item titles carry live
    /// metric values and therefore need canonicalizing before use as identity.
    public static func hasDynamicMetricTitles(_ bundleID: String) -> Bool {
        dynamicMetricTitleBundleMatchers.contains { matcher in
            bundleID.hasPrefix(matcher.prefix) && bundleID.hasSuffix(matcher.suffix)
        }
    }

    /// Outlook's countdown prefix churns identity, triggering new-item moves and preventing image-cache backoff.
    /// Keep the meeting name after ": "; canonicalIStatMetricTitle would keep the volatile countdown instead.
    private static let countdownPrefixTitleBundleMatchers: [(prefix: String, suffix: String)] = [
        (prefix: "com.microsoft.Outlook", suffix: ""),
    ]

    /// Whether bundleID belongs to an app whose status-item titles lead with a
    /// live countdown and therefore need canonicalizing before use as identity.
    public static func hasCountdownPrefixTitles(_ bundleID: String) -> Bool {
        countdownPrefixTitleBundleMatchers.contains { matcher in
            bundleID.hasPrefix(matcher.prefix) && bundleID.hasSuffix(matcher.suffix)
        }
    }

    /// Wholly volatile titles, such as Dato's date and event countdown, have no stable fragment; use sibling position instead.
    /// - Important: Add only apps with volatile titles in every item; instanceIndex alone distinguishes siblings, so reordering swaps identities.
    private static let volatileTitleBundleMatchers: [(prefix: String, suffix: String)] = [
        (prefix: "com.sindresorhus.Dato", suffix: ""),
        // ThermalForge's single temperature item uses instanceIndex to avoid migration shuffles.
        // Its startup "Item-0" fallback maps to the same placeholder, preserving identity across launch.
        (prefix: "com.thermalforge.app", suffix: ""),
        // MacThrottle's single status item displays a live temperature.
        (prefix: "com.macthrottle.app", suffix: ""),
    ]

    /// Whether bundleID belongs to an app whose status-item titles are live
    /// text end to end and therefore cannot serve as identity at all.
    public static func hasVolatileTitles(_ bundleID: String) -> Bool {
        // Amphetamine's single item alternates between Item-0, ∞ and 𝗧.
        bundleID == "com.if.Amphetamine" || volatileTitleBundleMatchers.contains { matcher in
            bundleID.hasPrefix(matcher.prefix) && bundleID.hasSuffix(matcher.suffix)
        } || learnedVolatileTitleBundleIDs.withLock { $0.contains(bundleID) }
    }

    /// Learn retitling only for single-item owners, such as WeChat's unread count, where collapsing titles cannot confuse siblings.
    /// The AX provider reads off the main actor, so access is locked.
    private static let learnedVolatileTitleBundleIDs = Mutex<Set<String>>([])

    /// The learned owners, for persisting.
    public static var learnedVolatileTitleOwners: Set<String> {
        learnedVolatileTitleBundleIDs.withLock { $0 }
    }

    /// Replaces the learned owners, from persisted state at launch.
    public static func restoreLearnedVolatileTitleOwners(_ bundleIDs: Set<String>) {
        learnedVolatileTitleBundleIDs.withLock { $0 = bundleIDs }
    }

    /// Records bundleID as retitling its item. Returns false when it was
    /// already learned or another rule already canonicalizes its titles.
    @discardableResult
    public static func learnVolatileTitleOwner(_ bundleID: String) -> Bool {
        guard titleCanonicalizer(for: bundleID) == nil else { return false }
        return learnedVolatileTitleBundleIDs.withLock { $0.insert(bundleID).inserted }
    }

    /// Avoid Item-<n> so volatile titles do not enter generic-title reveal matching for unnamed items.
    public static let volatileTitlePlaceholder = "Item"

    /// Discards a wholly volatile title, leaving instanceIndex to
    /// distinguish the app's items from one another.
    public static func canonicalVolatileTitle(_: String) -> String {
        volatileTitlePlaceholder
    }

    /// OneDrive's first line ("OneDrive — Personal") identifies the account and matches the host's position key; only the sync-status line churns.
    /// Keep the account line so multiple accounts retain distinct identities when reordered.
    private static let multilineStatusTitleBundleMatchers: [(prefix: String, suffix: String)] = [
        (prefix: "com.microsoft.OneDrive", suffix: ""),
    ]

    /// Whether bundleID belongs to an app whose status-item titles carry live
    /// status on a line below a stable first line.
    public static func hasMultilineStatusTitles(_ bundleID: String) -> Bool {
        multilineStatusTitleBundleMatchers.contains { matcher in
            bundleID.hasPrefix(matcher.prefix) && bundleID.hasSuffix(matcher.suffix)
        }
    }

    /// Keeps the stable first line, falling back to the raw title if it starts with a newline to avoid empty identities.
    public static func canonicalFirstLineTitle(_ raw: String) -> String {
        guard let firstLine = raw.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first else {
            return raw
        }
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? raw : trimmed
    }

    /// Shares the registry with identity-building callers; AX must canonicalize before assigning instance indices.
    public static func hasCanonicalizableTitles(_ bundleID: String) -> Bool {
        titleCanonicalizer(for: bundleID) != nil
    }

    /// Shared rule for live and persisted identities; nil means titles are already stable.
    private static func titleCanonicalizer(for bundleID: String) -> ((String) -> String)? {
        if hasDynamicMetricTitles(bundleID) {
            return canonicalIStatMetricTitle
        }
        if hasCountdownPrefixTitles(bundleID) {
            return canonicalCountdownPrefixTitle
        }
        if hasVolatileTitles(bundleID) {
            return canonicalVolatileTitle
        }
        if hasMultilineStatusTitles(bundleID) {
            return canonicalFirstLineTitle
        }
        return nil
    }

    /// Forces visible items that can be reordered but not reliably hidden on macOS 27.
    /// Do not add apps whose identities can be canonicalized for direct management.
    public static let hidingUnsupportedBundleIDs: Set<String> = [
        // iStat Menus identities are canonicalized, so users can move and hide them directly.
    ]

    /// These leading-edge items ignore weights and lack draggable elements; classify separately to avoid false concealment and trailing-anchor moves.
    /// Match process names because bundle-less accessories have no bundle identifier.
    public static let agentUngovernedOwners: Set<String> = [
        "sideloadly-daemon",
    ]

    private static let nativeOverflowChevronGlyphs: Set<Character> = [
        "<", ">", "‹", "›", "«", "»",
    ]

    /// Some macOS 27 builds publish overflow through AXOverflowButton rather than an ordinary status item.
    public static let nativeOverflowControlAXAttributeTitle = "AXOverflowButton"

    /// Localized title backstop for stale keys, fixtures, or failed AX reads; add observed locales, but never rely on titles alone.
    /// AX normally excludes overflow by its AXOverflowButton element or matching frame.
    static let nativeOverflowControlKnownTitles: Set<String> = [
        "Show Hidden Menu Bar Items",
    ]

    /// Whether this item's owner is in agentUngovernedOwners.
    public var isAgentUngoverned: Bool {
        if case let .string(owner) = namespace {
            return MenuBarItemTag.agentUngovernedOwners.contains(owner)
        }
        return false
    }

    /// Whether this item's owner is in hidingUnsupportedBundleIDs.
    public var isHidingUnsupported: Bool {
        if case let .string(bundleID) = namespace {
            return MenuBarItemTag.hidingUnsupportedBundleIDs.contains(bundleID)
        }
        return false
    }

    /// macOS 27 overflow chrome has no assignable owner, usable weight, or drag window; exclude it from sections, persistence, spacing, orders, and moves wherever clones are excluded.
    /// This title-only backstop recognizes AXOverflowButton, chevron descriptions/glyphs, and known localized titles; AX normally drops it structurally.
    public var isNativeOverflowControl: Bool {
        guard namespace == .menuBarAgent else { return false }
        return MenuBarItemTag.isNativeOverflowControlTitle(title)
    }

    /// The title half of isNativeOverflowControl, for callers that hold a
    /// MenuBarAgent element's title (identity or display) before a tag exists.
    public static func isNativeOverflowControlTitle(_ title: String) -> Bool {
        let normalized = title.filter { !$0.isWhitespace }
        guard !normalized.isEmpty else { return false }
        if normalized.caseInsensitiveCompare(nativeOverflowControlAXAttributeTitle) == .orderedSame {
            return true
        }
        // macOS 27's notchless indicator uses "Double backward chevron", not glyphs.
        // Only the indicator mentions "chevron" in MenuBarAgent titles or descriptions.
        if title.range(of: "chevron", options: .caseInsensitive) != nil {
            return true
        }
        if nativeOverflowControlKnownTitles.contains(
            title.trimmingCharacters(in: .whitespacesAndNewlines)
        ) {
            return true
        }
        guard normalized.count <= 4 else { return false }
        return normalized.allSatisfy { nativeOverflowChevronGlyphs.contains($0) }
    }

    /// The item's authoritative section-management classification.
    public var sectionManagementPolicy: SectionManagementPolicy {
        if isNativeOverflowControl || isCaptureActivityIndicator {
            return .excluded
        }

        if isHidingUnsupported ||
            isAgentUngoverned ||
            isLayoutAnchoredSystemItem ||
            isMenuBarAgentItemForcedVisible ||
            (namespace != .menuBarAgent && isNonConcealableSystemItem && !isControlCenterGovernable)
        {
            return .forcedVisible
        }

        if isLayoutAnchoredSystemItem {
            return .excluded
        }

        if MenuBarItemTag.nonHideableItems.contains(where: {
            $0.namespace == namespace && $0.title == title
        }) || (namespace.isUUID && title == "AudioVideoModule") {
            return .excluded
        }

        return .hideable
    }

    /// Only fixed trailing controls are disabled layout anchors; most macOS 27 MenuBarAgent modules remain movable.
    public var isLayoutAnchoredSystemItem: Bool {
        if MenuBarItemTag.immovableItems.contains(where: { $0.namespace == namespace && $0.title == title }) {
            return true
        }

        if MenuBarItemTag.fixedSystemAgentNamespaces.contains(namespace) {
            return true
        }

        if namespace == .menuBarAgent,
           MenuBarItemTag.menuBarAgentAnchoredModuleTitles.contains(title)
        {
            return true
        }

        return false
    }

    public var isMovable: Bool {
        !isLayoutAnchoredSystemItem && !isAgentUngoverned && !isCaptureActivityIndicator
    }

    /// System capture activity changes with ScreenCaptureKit sessions; it is
    /// not a user-arranged item and must not enter capture or order repair.
    public var isCaptureActivityIndicator: Bool {
        (title == "AudioVideoModule" || title == "com.apple.menuextra.audiovideo") &&
            (namespace == .menuBarAgent || namespace == .controlCenter || namespace.isUUID)
    }

    /// Legacy divider movement ignores the host OS so tests stay deterministic on macOS 27, which adds anchors.
    public var isMovableInLegacySectionLayout: Bool {
        !MenuBarItemTag.legacyImmovableItems.contains {
            $0.namespace == namespace && $0.title == title
        }
    }

    public var canBeHidden: Bool {
        sectionManagementPolicy.canBeHidden
    }

    /// Legacy hiding ignores macOS 27 assertion policy so planner tests remain deterministic across host OS versions.
    public var canBeHiddenInLegacySectionLayout: Bool {
        isMovableInLegacySectionLayout &&
            !MenuBarItemTag.nonHideableItems.contains(where: {
                $0.namespace == namespace && $0.title == title
            }) &&
            !(namespace.isUUID && title == "AudioVideoModule")
    }

    /// Whether title has the generic Item-N shape macOS gives a hosted
    /// item that publishes no name of its own (Item-0, Item-38, ...). The one
    /// place that shape is spelled out.
    public static func isGenericItemTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        return title.wholeMatch(of: /Item-\d+/) != nil
    }

    /// Generic hosting-process identity (such as a Live Activity) with the pattern <hostingProcess>:Item-\d+.
    public var isControlCenterGenericItem: Bool {
        namespace.isMenuBarHostingNamespace && Self.isGenericItemTitle(title)
    }

    /// Unnamed extras read before naming attributes return have no reliable position key; move and order paths must skip them.
    /// Backstops walks missed by the identity reconciler.
    public var isUnnamedMenuBarAgentExtra: Bool {
        namespace == .menuBarAgent && isControlCenterGenericItem
    }

    /// Whether a persisted namespace:title[:instance] identifier names an
    /// unnamed MenuBarAgent extra. See isUnnamedMenuBarAgentExtra.
    public static func isUnnamedMenuBarAgentIdentifier(_ identifier: String) -> Bool {
        let prefix = "\(Namespace.menuBarAgent.description):"
        guard identifier.hasPrefix(prefix) else { return false }
        let title = String(identifier.dropFirst(prefix.count).split(separator: ":").first ?? "")
        return Self.isGenericItemTitle(title)
    }

    /// Whether this tag's namespace identifies Thaw itself (not a third-party app).
    public var isThawOwnedNamespace: Bool {
        switch namespace {
        case .thaw:
            return true
        case let .string(bundleID):
            return ThawMenuBarIdentity.owns(bundleIdentifier: bundleID)
        case .null, .uuid:
            return false
        }
    }

    /// Whether this tag is Thaw's visible-section chevron.
    public var matchesVisibleControlItem: Bool {
        title == ControlItemIdentifier.visible.rawValue && isThawOwnedNamespace
    }

    /// Whether this tag is Thaw's Hidden-section divider.
    public var matchesHiddenControlItem: Bool {
        title == ControlItemIdentifier.hidden.rawValue && isThawOwnedNamespace
    }

    /// Whether this tag is a zero-width Hidden / Always-Hidden section divider.
    /// These may anchor section-boundary ⌘-drags but are never drag sources.
    public var matchesSectionBoundaryControlItem: Bool {
        isControlItem && !matchesVisibleControlItem
    }

    public var isControlItem: Bool {
        if isThawOwnedNamespace, title.hasPrefix("Thaw.ControlItem.") {
            return true
        }
        // User-created Thaw.Spacer.* items must remain draggable, reorderable, and concealable.
        return MenuBarItemTag.controlItems.contains(where: { $0.namespace == namespace && $0.title == title })
    }

    public var isBentoBox: Bool {
        namespace.isMenuBarHostingNamespace && title.hasPrefix("BentoBox")
    }

    /// Clones are invalid for management; match WindowServer's stable title, not namespace.
    /// Unresolved PIDs or spatial mismatches can give clones process-name or real bundle-ID namespaces instead of UUIDs.
    public var isSystemClone: Bool {
        title == "System Status Item Clone"
    }

    /// A textual representation of the tag.
    public var description: String {
        var result = String(describing: namespace)
        if !title.isEmpty {
            result.append(":\(title)")
        }
        if instanceIndex > 0 {
            result.append(":\(instanceIndex)")
        }
        if let windowID, !isSystemItem {
            result.append(" (windowID: \(windowID))")
        }
        return result
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(namespace)
        hasher.combine(title)
        hasher.combine(instanceIndex)
        if !isSystemItem {
            hasher.combine(windowID)
        }
    }

    public static func == (lhs: MenuBarItemTag, rhs: MenuBarItemTag) -> Bool {
        if lhs.namespace != rhs.namespace || lhs.title != rhs.title || lhs.instanceIndex != rhs.instanceIndex {
            return false
        }
        if lhs.isSystemItem {
            return true
        }
        return lhs.windowID == rhs.windowID
    }

    /// Returns a Boolean value that indicates whether the given tag
    /// matches this tag, ignoring their window identifiers.
    public func matchesIgnoringWindowID(_ other: MenuBarItemTag) -> Bool {
        namespace == other.namespace &&
            canonicalTitle == other.canonicalTitle &&
            instanceIndex == other.instanceIndex
    }

    /// Returns whether this tag identifies the same logical item as other,
    /// including Thaw's visible control across namespace aliases.
    public func matchesIdentity(of other: MenuBarItemTag) -> Bool {
        if matchesVisibleControlItem, other.matchesVisibleControlItem {
            return true
        }
        return matchesIgnoringWindowID(other)
    }

    /// Stable across window ID changes; nonzero instance indices distinguish same-app items with identical titles.
    public var tagIdentifier: String {
        let title = canonicalTitle
        if instanceIndex > 0 {
            return "\(namespace):\(title):\(instanceIndex)"
        }
        return "\(namespace):\(title)"
    }

    public var canonicalTitle: String {
        Self.canonicalTitle(namespace: namespace, title: title)
    }

    public static func canonicalTitle(namespace: Namespace, title: String) -> String {
        guard case let .string(bundleID) = namespace else {
            return title
        }
        return migratedAppKitPlaceholderTitle(bundleID: bundleID, title: title)
            ?? titleCanonicalizer(for: bundleID)?(title)
            ?? title
    }

    /// Rectangle owns one status item; its old AppKit placeholder became Item-0
    /// when AX enumeration stopped accepting _NS identifiers. Do not generalize
    /// to multi-item apps such as Keyboard Maestro. Keep this migration outside
    /// the live-title registry so AX attribute precedence remains unchanged.
    private static func migratedAppKitPlaceholderTitle(bundleID: String, title: String) -> String? {
        guard bundleID == "com.knollsoft.Rectangle",
              title.wholeMatch(of: /_NS:\d+/) != nil
        else { return nil }
        return "Item-0"
    }

    public static func canonicalPersistentIdentifier(_ identifier: String) -> String {
        // An identifier is namespace:title[:instance], and a bundle ID never
        // contains a colon, so the first one separates the namespace.
        guard let separator = identifier.firstIndex(of: ":") else {
            return identifier
        }
        let bundleID = String(identifier[..<separator])
        let prefix = "\(bundleID):"
        let suffix = String(identifier[identifier.index(after: separator)...])
        // The first number belongs to AppKit's title, not to our instance index.
        if let match = suffix.wholeMatch(of: /(_NS:\d+)(?::(\d+))?/),
           let title = migratedAppKitPlaceholderTitle(bundleID: bundleID, title: String(match.1))
        {
            let instance = match.2.map { ":\($0)" } ?? ""
            return "\(prefix)\(title)\(instance)"
        }
        guard let canonicalize = titleCanonicalizer(for: bundleID) else {
            return identifier
        }

        // A clock's trailing minutes are not an instance index; splitting them would churn identity every minute.
        // Distinguish times by digits before the colon and two digits after it.
        if !suffix.contains(/\d{1,2}:\d{2}(?::\d{2})?$/),
           let separator = suffix.lastIndex(of: ":")
        {
            let title = String(suffix[..<separator])
            let instance = String(suffix[suffix.index(after: separator)...])
            if Int(instance) != nil {
                return "\(prefix)\(canonicalize(title)):\(instance)"
            }
        }
        return "\(prefix)\(canonicalize(suffix))"
    }

    /// Drops remembered identifiers of one bundle that can no longer name an item: AppKit placeholders
    /// (_NS:<n>), which enumeration no longer accepts, and OneDrive's bare title once an account title is known.
    public static func identifiersWithoutStaleAliases(_ identifiers: Set<String>, bundleID: String) -> Set<String> {
        let prefix = "\(bundleID):"
        func title(of identifier: String) -> Substring? {
            identifier.hasPrefix(prefix) ? identifier.dropFirst(prefix.count) : nil
        }
        let hasOneDriveAccountTitle = hasMultilineStatusTitles(bundleID)
            && identifiers.contains { title(of: $0)?.hasPrefix("OneDrive \u{2014} ") == true }
        return identifiers.filter { identifier in
            guard let title = title(of: identifier) else { return true }
            if title.wholeMatch(of: /_NS:\d+(?::\d+)?/) != nil {
                return false
            }
            return !(hasOneDriveAccountTitle && title == "OneDrive")
        }
    }

    public static func canonicalPersistentIdentifiers(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            let canonical = canonicalPersistentIdentifier(identifier)
            guard seen.insert(canonical).inserted else {
                return nil
            }
            return canonical
        }
    }

    /// Keys "Module: data" on the module because localized status words and peripherals churn too; otherwise neutralizes numbers.
    /// - Note: A bare clock ("15:41") has no ": " and canonicalizes to "#:#".
    public static func canonicalIStatMetricTitle(_ raw: String) -> String {
        // An untitled extra's Item-N is a stable identity that keys the position store, not a reading.
        if raw.wholeMatch(of: /Item-\d+/) != nil {
            return raw
        }
        if let separator = raw.range(of: ": ") {
            let module = raw[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            if !module.isEmpty {
                return module
            }
        }
        return raw
            .replacing(/[-+]?\d+(?:[.,]\d+)?/, with: "#")
            .replacing(/#\s*[KMGTPE]?[Bb]\/s/, with: "# B/s")
            .replacing(/#\s*[KMGTPE]?[Bb]/, with: "# B")
    }

    /// Keeps the name after ": " without matching localized countdown words; identity changes only when the meeting changes.
    /// Returns titles unchanged when the separator or remaining name is absent, as between meetings.
    public static func canonicalCountdownPrefixTitle(_ raw: String) -> String {
        guard let separator = raw.range(of: ": ") else {
            return raw
        }
        let name = raw[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? raw : name
    }

    /// Creates a tag with the given namespace, title, window identifier,
    /// and instance index.
    public init(namespace: Namespace, title: String, windowID: CGWindowID? = nil, instanceIndex: Int = 0) {
        self.namespace = namespace
        self.title = title
        self.windowID = windowID
        self.instanceIndex = instanceIndex
    }

    /// Creates a tag for the control item with the given identifier.
    private init(controlItem identifier: ControlItemIdentifier) {
        self.init(namespace: .thaw, title: identifier.rawValue, instanceIndex: 0)
    }
}

// MARK: MenuBarItemTag Constants

public extension MenuBarItemTag {
    // MARK: Special Item Lists

    /// Fixed items in the legacy Control Center-hosted layout. Keep this list
    /// explicit rather than deriving it from the current OS namespace.
    private static let legacyImmovableItems: [MenuBarItemTag] = [
        MenuBarItemTag(namespace: .controlCenter, title: "Clock"),
        MenuBarItemTag(namespace: .controlCenter, title: "BentoBox-0"),
        siri,
        ssMenuAgent,
    ]

    /// macOS fixes these items at the trailing end and prevents hiding.
    static var immovableItems: [MenuBarItemTag] {
        [clock, controlCenter, siri, ssMenuAgent]
    }

    /// An array of tags for items that can be moved, but cannot be hidden.
    static var nonHideableItems: [MenuBarItemTag] {
        [visibleControlItem, audioVideoModule, faceTime, screenCaptureUI, gameMode]
    }

    /// An array of tags for items representing Thaw's control items.
    static let controlItems = ControlItemIdentifier.allCases.map(\.tag)

    /// Apple modules observed under com.apple.MenuBarAgent on macOS 27 that
    /// behave as fixed trailing system controls. Other MenuBarAgent modules
    /// (Wi-Fi, Bluetooth, Sound, Focus, Now Playing, etc.) remain movable.
    static let menuBarAgentAnchoredModuleTitles: Set<String> = [
        "Clock",
        "ControlCenter",
        "BentoBox-0",
        "Siri",
        "com.apple.menuextra.clock",
        "com.apple.menuextra.controlcenter",
        "com.apple.menuextra.siri",
    ]

    /// Separate Apple/system agents that Thaw should display but not move.
    private static let fixedSystemAgentNamespaces: Set<Namespace> = [
        .gamePolicyAgent,
        .screenCaptureUI,
        .ssMenuAgent,
    ]

    /// Lower ranks sort leftmost within a hidden section's trailing anchor group.
    /// Non-anchors return a rank above all anchors so they precede the group.
    static func anchoredSystemItemRank(_ tag: MenuBarItemTag) -> Int {
        if tag.title == controlCenter.title
            || tag.title == "ControlCenter"
            || tag.title == "com.apple.menuextra.controlcenter"
        {
            return 1
        }
        // macOS 27 Siri, including its MenuBarAgent spelling, precedes pinned Control Center and Clock.
        if tag == .siri
            || tag.title == "Siri"
            || tag.title == "com.apple.menuextra.siri"
        {
            return 0
        }
        if tag.title == clock.title
            || tag.title == "com.apple.menuextra.clock"
        {
            return 2
        }
        return 3
    }

    // MARK: Control Items

    /// The tag for Thaw's control item for the "Visible" section.
    static let visibleControlItem = MenuBarItemTag(controlItem: .visible)

    /// The tag for Thaw's control item for the "Hidden" section.
    static let hiddenControlItem = MenuBarItemTag(controlItem: .hidden)

    /// The tag for Thaw's control item for the "Always-Hidden" section.
    static let alwaysHiddenControlItem = MenuBarItemTag(controlItem: .alwaysHidden)

    // MARK: Other Special Items

    /// The namespace used by system-owned menu bar items (Clock, BentoBox, AudioVideoModule, ...).
    ///
    /// On macOS 26 the hosting process is Control Center; on macOS 27+ it is MenuBarAgent.
    private static var systemHostNamespace: Namespace {
        .menuBarAgent
    }

    /// The tag for the system item that appears in the menu bar
    /// during screen or audio capture.
    static var audioVideoModule: MenuBarItemTag {
        MenuBarItemTag(namespace: systemHostNamespace, title: "AudioVideoModule")
    }

    /// The tag for the system "Clock" item.
    static var clock: MenuBarItemTag {
        MenuBarItemTag(namespace: systemHostNamespace, title: "Clock")
    }

    /// The tag for the system "Control Center" item.
    static var controlCenter: MenuBarItemTag {
        MenuBarItemTag(namespace: systemHostNamespace, title: "BentoBox-0")
    }

    /// The tag for the system "FaceTime" item.
    static var faceTime: MenuBarItemTag {
        MenuBarItemTag(namespace: systemHostNamespace, title: "FaceTime")
    }

    /// The tag for the system item that appears in the menu bar
    /// during recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = MenuBarItemTag(namespace: .screenCaptureUI, title: "Item-0")

    /// The tag for the system "Siri" item.
    static let siri = MenuBarItemTag(namespace: .systemUIServer, title: "Siri")

    /// Screen Sharing follows Command-drag visually but returns to its original position on mouse-up.
    static let ssMenuAgent = MenuBarItemTag(namespace: .ssMenuAgent, title: "Item-0")

    /// The tag for the system "Time Machine" item.
    static let timeMachine = MenuBarItemTag(namespace: .systemUIServer, title: "com.apple.menuextra.TimeMachine")

    /// macOS 27's unnamed Time Machine needs a stable key because MenuBarAgent does not sort by positional Item-N.
    /// Siri keeps its own title.
    static func legacySystemUIServerIdentity(
        namespace: Namespace,
        identifier: String?,
        accessibilityDescription: String?,
        axTitle: String?
    ) -> String? {
        guard namespace == .systemUIServer else { return nil }
        let absent: (String?) -> Bool = { $0?.isEmpty ?? true }
        guard absent(identifier), absent(accessibilityDescription), absent(axTitle) else { return nil }
        return timeMachine.title
    }

    /// The tag for the system "Game Mode" item.
    static let gameMode = MenuBarItemTag(namespace: .gamePolicyAgent, title: "Item-0")
}

// MARK: - MenuBarItemTag.Namespace

public extension MenuBarItemTag {
    /// A type that represents a menu bar item namespace.
    enum Namespace: Hashable, CustomStringConvertible, Sendable, Codable {
        /// The null namespace.
        case null
        /// A namespace represented by a string.
        case string(String)
        /// A namespace represented by a UUID.
        case uuid(UUID)

        /// A textual representation of the namespace.
        public var description: String {
            switch self {
            case .null: "null"
            case let .string(string): string
            case let .uuid(uuid): uuid.uuidString
            }
        }

        public var isNull: Bool {
            switch self {
            case .null: true
            case .string, .uuid: false
            }
        }

        public var isString: Bool {
            switch self {
            case .string: true
            case .uuid, .null: false
            }
        }

        public var isUUID: Bool {
            switch self {
            case .uuid: true
            case .null, .string: false
            }
        }

        /// CG window host: Control Center on macOS 26, MenuBarAgent on macOS 27 and later.
        public var isMenuBarHostingNamespace: Bool {
            return self == .menuBarAgent
        }

        /// Creates a namespace with the given optional value.
        ///
        /// - Parameter value: An optional value for the namespace.
        ///
        /// - Returns: A namespace represented by a string when value
        ///   is not nil. Otherwise, the null namespace.
        public static func optional(_ value: String?) -> Namespace {
            value.map { .string($0) } ?? .null
        }
    }
}

// MARK: MenuBarItemTag.Namespace Constants

public extension MenuBarItemTag.Namespace {
    /// The namespace for the "Thaw" process.
    static let thaw = string(ThawMenuBarIdentity.bundleIdentifier)

    /// The namespace for the "Control Center" process.
    static let controlCenter = string("com.apple.controlcenter")

    /// The namespace for the "MenuBarAgent" process (macOS 27+).
    static let menuBarAgent = string(SharedConstants.menuBarHostingBundleID)

    /// The namespace for the "PasswordsMenuBarExtra" process.
    static let passwords = string("com.apple.Passwords.MenuBarExtra")

    /// The namespace for the "screencaptureui" process.
    static let screenCaptureUI = string("com.apple.screencaptureui")

    /// The namespace for the "SystemUIServer" process.
    static let systemUIServer = string("com.apple.systemuiserver")

    /// The namespace for the "TextInputMenuAgent" process.
    static let textInputMenuAgent = string("com.apple.TextInputMenuAgent")

    /// The namespace for the "SSMenuAgent" process (Screen Sharing menu extra).
    static let ssMenuAgent = string("com.apple.SSMenuAgent")

    /// The namespace for the "GamePolicyAgent" process (Game Mode).
    static let gamePolicyAgent = string("GamePolicyAgent")

    /// The namespace for the "WeatherMenu" process.
    static let weather = string("com.apple.weather.menu")
}
