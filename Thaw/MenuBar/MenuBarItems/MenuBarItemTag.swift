//
//  MenuBarItemTag.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

// MARK: - MenuBarItemTag

/// An identifier for a menu bar item.
struct MenuBarItemTag: Hashable, CustomStringConvertible {
    /// How an item participates in Thaw's section model.
    ///
    /// This value is the classification authority shared by hiding, section
    /// assignment, and layout caching. Consumers must use the capabilities on
    /// this policy instead of rebuilding the system-item exceptions.
    enum SectionManagementPolicy: Equatable {
        /// The item can be assigned to and ordered within any section.
        case hideable

        /// The item must remain visible, but still belongs in the layout cache.
        case forcedVisible

        /// The item is not managed by the section layout.
        case excluded

        var canBeHidden: Bool {
            self == .hideable
        }

        var isVisibleInLayout: Bool {
            self != .excluded
        }

        var isForcedVisible: Bool {
            self == .forcedVisible
        }
    }

    /// The namespace of the item identified by this tag.
    let namespace: Namespace

    /// The title of the item identified by this tag.
    let title: String

    /// The window identifier of the item identified by this tag.
    let windowID: CGWindowID?

    /// The index of the item within its (namespace, title) group.
    let instanceIndex: Int

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a system item.
    var isSystemItem: Bool {
        switch namespace {
        case .controlCenter, .systemUIServer, .textInputMenuAgent, .weather, .passwords, .screenCaptureUI, .ssMenuAgent, .thaw, .gamePolicyAgent:
            return true
        case .menuBarAgent:
            if #available(macOS 27, *) {
                return true
            }
            return false
        case .string, .uuid, .null:
            return false
        }
    }

    /// A Boolean value that indicates whether this item is owned by an Apple
    /// system process that Thaw cannot reliably conceal or reorder on macOS 27.
    ///
    /// These items (Sound/Wi-Fi/Bluetooth/AirDrop under MenuBarAgent, Spotlight
    /// under `com.apple.campo`, Siri under SystemUIServer, …) report
    /// ``canBeHidden`` but their bundle keeps anchored siblings visible, so the
    /// assertion never conceals them, and the synthetic ⌘-drag does not reliably
    /// move them. They are managed best-effort and must be excluded from
    /// layout-divergence detection so a perpetually-stuck one cannot drive an
    /// infinite layout re-apply loop.
    ///
    /// Broader than ``isSystemItem``: that misses agents exposed under a
    /// `.string` namespace (e.g. Spotlight's `com.apple.campo`), so this also
    /// matches any `com.apple.*` owner.
    var isNonConcealableSystemItem: Bool {
        isSystemItem || namespace.description.hasPrefix("com.apple.")
    }

    /// A Boolean value that indicates whether this item is a Control Center
    /// module Thaw CAN hide individually via its per-host visibility pref
    /// (Wi-Fi/Bluetooth/AirDrop/NowPlaying/User/Focus — see
    /// ``ControlCenterModuleManager``). These are exceptions to
    /// ``isNonConcealableSystemItem``: the assertion can't conceal them, but the
    /// CC-pref path can, so they REMAIN hideable.
    var isControlCenterGovernable: Bool {
        ControlCenterModuleManager.moduleKeysByMenuExtraTitle[title] != nil
    }

    /// iStat Menus status-item bundle ID. Titles and identifiers are
    /// canonicalized via ``canonicalIStatMetricTitle`` so live metric values do
    /// not churn layout keys every second.
    static let iStatMenusStatusBundleID = "com.bjango.istatmenus.status"

    /// Bundle identifiers whose menu bar items Thaw can reorder but cannot yet
    /// reliably hide on macOS 27. Denylisted items are forced visible in the
    /// layout editor. Keep this empty for apps whose identities can be
    /// canonicalized well enough to let users manage them directly.
    static let hidingUnsupportedBundleIDs: Set<String> = [
        // iStat Menus identities are canonicalized above, so allow users to
        // move/hide them from the layout UI instead of forcing them visible.
        // iStatMenusStatusBundleID,
    ]

    private static let nativeOverflowChevronGlyphs: Set<Character> = [
        "<", ">", "‹", "›", "«", "»",
    ]

    /// Whether this item's owner is in ``hidingUnsupportedBundleIDs``.
    var isHidingUnsupported: Bool {
        if case let .string(bundleID) = namespace {
            return MenuBarItemTag.hidingUnsupportedBundleIDs.contains(bundleID)
        }
        return false
    }

    /// macOS 27's native menu-bar overflow control can appear in AX as a
    /// MenuBarAgent extra. It is a system placeholder, not a status item.
    var isNativeOverflowPlaceholder: Bool {
        guard namespace == .menuBarAgent else { return false }

        let glyphs = title.filter { !$0.isWhitespace }
        guard !glyphs.isEmpty, glyphs.count <= 4 else { return false }

        return glyphs.allSatisfy { MenuBarItemTag.nativeOverflowChevronGlyphs.contains($0) }
    }

    /// The item's authoritative section-management classification.
    var sectionManagementPolicy: SectionManagementPolicy {
        if #available(macOS 27, *), isNativeOverflowPlaceholder {
            return .excluded
        }

        if #available(macOS 27, *),
           isHidingUnsupported ||
           isLayoutAnchoredSystemItem ||
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

    /// A Boolean value that indicates whether this item should be rendered as a
    /// fixed system anchor in the layout UI.
    ///
    /// macOS 27 exposes Apple modules as children of `MenuBarAgent`. Most of
    /// those modules are movable live AX items; only the trailing fixed system
    /// controls should be rendered as disabled anchors in the layout UI.
    var isLayoutAnchoredSystemItem: Bool {
        if MenuBarItemTag.immovableItems.contains(where: { $0.namespace == namespace && $0.title == title }) {
            return true
        }

        if MenuBarItemTag.fixedSystemAgentNamespaces.contains(namespace) {
            return true
        }

        if #available(macOS 27, *) {
            if namespace == .menuBarAgent,
               MenuBarItemTag.menuBarAgentAnchoredModuleTitles.contains(title)
            {
                return true
            }
        }

        return false
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag can be moved.
    var isMovable: Bool {
        !isLayoutAnchoredSystemItem
    }

    /// Whether the item can participate in the legacy divider-based layout
    /// used on macOS 26 and earlier. This policy is intentionally independent
    /// of the host OS so legacy planners remain deterministic when their tests
    /// run on macOS 27, where additional agents are layout anchors.
    var isMovableInLegacySectionLayout: Bool {
        !MenuBarItemTag.legacyImmovableItems.contains {
            $0.namespace == namespace && $0.title == title
        }
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag can be hidden.
    var canBeHidden: Bool {
        sectionManagementPolicy.canBeHidden
    }

    /// Whether the item can participate as hideable in the legacy divider
    /// layout. This deliberately ignores macOS 27's assertion policy so pure
    /// legacy planners remain deterministic when tested on a newer host OS.
    var canBeHiddenInLegacySectionLayout: Bool {
        isMovableInLegacySectionLayout &&
            !MenuBarItemTag.nonHideableItems.contains(where: {
                $0.namespace == namespace && $0.title == title
            }) &&
            !(namespace.isUUID && title == "AudioVideoModule")
    }

    /// A Boolean value that indicates whether this tag represents a
    /// dynamically-named hosting-process item (Live Activities, etc.)
    /// with the pattern `<hostingProcess>:Item-\d+`.
    var isControlCenterGenericItem: Bool {
        // macOS 26: the hosting namespace is Control Center; macOS 27: MenuBarAgent
        // (see isMenuBarHostingNamespace). The generic-slot title test is shared
        // with the marker-pair resolver so both stay in sync.
        namespace.isMenuBarHostingNamespace && MarkerPairResolver.isGenericControlCenterTitle(title)
    }

    /// Whether this tag's namespace identifies Thaw itself (not a third-party app).
    var isThawOwnedNamespace: Bool {
        switch namespace {
        case .thaw:
            return true
        case let .string(bundleID):
            return Constants.isThawOwnedBundleIdentifier(bundleID)
        case .null, .uuid:
            return false
        }
    }

    /// Whether this tag is Thaw's visible-section chevron, including
    /// MenuBarHost-style AX namespaces on macOS 27.
    var matchesVisibleControlItem: Bool {
        title == ControlItem.Identifier.visible.rawValue && isThawOwnedNamespace
    }

    /// Whether this tag is a zero-width Hidden / Always-Hidden section divider.
    /// These may anchor section-boundary ⌘-drags but are never drag sources.
    var matchesSectionBoundaryControlItem: Bool {
        isControlItem && !matchesVisibleControlItem
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a control item owned by Ice.
    var isControlItem: Bool {
        if isThawOwnedNamespace, title.hasPrefix("Thaw.ControlItem.") {
            return true
        }
        return MenuBarItemTag.controlItems.contains(where: { $0.namespace == namespace && $0.title == title }) ||
            title.contains(".Spacer.")
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a "BentoBox" item owned by the menu bar hosting process.
    var isBentoBox: Bool {
        namespace.isMenuBarHostingNamespace && title.hasPrefix("BentoBox")
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a system-created clone of an actual item,
    /// and therefore invalid for management.
    ///
    /// The title is a stable name the WindowServer assigns to clone
    /// windows, but the namespace varies: it can be a UUID, the owning
    /// process name (Window Server) when the source PID never resolves,
    /// or even a real bundle ID when the clone spatially mis-matches a
    /// nearby app. Matching on the title alone catches every variant;
    /// gating on a UUID namespace missed the process-name and bundle-ID
    /// clones seen in the field.
    var isSystemClone: Bool {
        title == "System Status Item Clone"
    }

    /// A textual representation of the tag.
    var description: String {
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

    func hash(into hasher: inout Hasher) {
        hasher.combine(namespace)
        hasher.combine(title)
        hasher.combine(instanceIndex)
        if !isSystemItem {
            hasher.combine(windowID)
        }
    }

    static func == (lhs: MenuBarItemTag, rhs: MenuBarItemTag) -> Bool {
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
    func matchesIgnoringWindowID(_ other: MenuBarItemTag) -> Bool {
        namespace == other.namespace &&
            canonicalTitle == other.canonicalTitle &&
            instanceIndex == other.instanceIndex
    }

    /// Returns whether this tag identifies the same logical item as `other`,
    /// including Thaw's visible control across namespace aliases.
    func matchesIdentity(of other: MenuBarItemTag) -> Bool {
        if matchesVisibleControlItem, other.matchesVisibleControlItem {
            return true
        }
        return matchesIgnoringWindowID(other)
    }

    /// A stable string identifier that uniquely identifies this tag
    /// across window ID changes (e.g. app restarts). Includes the
    /// instance index when it is nonzero so that multiple items from
    /// the same app with the same title are distinguishable.
    var tagIdentifier: String {
        let title = canonicalTitle
        if instanceIndex > 0 {
            return "\(namespace):\(title):\(instanceIndex)"
        }
        return "\(namespace):\(title)"
    }

    var canonicalTitle: String {
        Self.canonicalTitle(namespace: namespace, title: title)
    }

    static func canonicalTitle(namespace: Namespace, title: String) -> String {
        guard namespace == .string(iStatMenusStatusBundleID) else {
            return title
        }
        return canonicalIStatMetricTitle(title)
    }

    static func canonicalPersistentIdentifier(_ identifier: String) -> String {
        let prefix = "\(iStatMenusStatusBundleID):"
        guard identifier.hasPrefix(prefix) else {
            return identifier
        }

        let suffix = String(identifier.dropFirst(prefix.count))
        if let separator = suffix.lastIndex(of: ":") {
            let title = String(suffix[..<separator])
            let instance = String(suffix[suffix.index(after: separator)...])
            if Int(instance) != nil {
                return "\(prefix)\(canonicalIStatMetricTitle(title)):\(instance)"
            }
        }
        return "\(prefix)\(canonicalIStatMetricTitle(suffix))"
    }

    static func canonicalPersistentIdentifiers(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            let canonical = canonicalPersistentIdentifier(identifier)
            guard seen.insert(canonical).inserted else {
                return nil
            }
            return canonical
        }
    }

    static func canonicalIStatMetricTitle(_ raw: String) -> String {
        raw
            .replacing(/[-+]?\d+(?:[.,]\d+)?/, with: "#")
            .replacing(/#\s*[KMGTPE]?[Bb]\/s/, with: "# B/s")
            .replacing(/#\s*[KMGTPE]?[Bb]/, with: "# B")
    }

    /// Creates a tag with the given namespace, title, window identifier,
    /// and instance index.
    init(namespace: Namespace, title: String, windowID: CGWindowID? = nil, instanceIndex: Int = 0) {
        self.namespace = namespace
        self.title = title
        self.windowID = windowID
        self.instanceIndex = instanceIndex
    }

    /// Creates a tag for the control item with the given identifier.
    private init(controlItem identifier: ControlItem.Identifier) {
        self.init(namespace: .thaw, title: identifier.rawValue, instanceIndex: 0)
    }
}

// MARK: MenuBarItemTag Constants

extension MenuBarItemTag {
    // MARK: Special Item Lists

    /// Fixed items in the legacy Control Center-hosted layout. Keep this list
    /// explicit rather than deriving it from the current OS namespace.
    private static let legacyImmovableItems: [MenuBarItemTag] = [
        MenuBarItemTag(namespace: .controlCenter, title: "Clock"),
        MenuBarItemTag(namespace: .controlCenter, title: "BentoBox-0"),
        siri,
        ssMenuAgent,
    ]

    /// An array of tags for items whose movement is prevented by macOS.
    ///
    /// These items have fixed positions at the trailing end of the menu bar,
    /// and cannot be hidden.
    ///
    /// This list contains the "Clock", "Control Center", "Siri", and
    /// "Screen Sharing" (ssMenuAgent) items.
    static var immovableItems: [MenuBarItemTag] {
        [clock, controlCenter, siri, ssMenuAgent]
    }

    /// An array of tags for items that can be moved, but cannot be hidden.
    static var nonHideableItems: [MenuBarItemTag] {
        [visibleControlItem, audioVideoModule, faceTime, screenCaptureUI, gameMode]
    }

    /// An array of tags for items representing Ice's control items.
    static let controlItems = ControlItem.Identifier.allCases.map(\.tag)

    /// Apple modules observed under `com.apple.MenuBarAgent` on macOS 27 that
    /// behave as fixed trailing system controls. Other MenuBarAgent modules
    /// (Wi-Fi, Bluetooth, Sound, Focus, Now Playing, etc.) remain movable.
    static let menuBarAgentAnchoredModuleTitles: Set<String> = [
        "Clock",
        "ControlCenter",
        "BentoBox-0",
        "com.apple.menuextra.clock",
        "com.apple.menuextra.controlcenter",
    ]

    /// Separate Apple/system agents that Thaw should display but not move.
    private static let fixedSystemAgentNamespaces: Set<Namespace> = [
        .gamePolicyAgent,
        .screenCaptureUI,
        .ssMenuAgent,
    ]

    // MARK: Control Items

    /// The tag for Ice's control item for the "Visible" section.
    static let visibleControlItem = MenuBarItemTag(controlItem: .visible)

    /// The tag for Ice's control item for the "Hidden" section.
    static let hiddenControlItem = MenuBarItemTag(controlItem: .hidden)

    /// The tag for Ice's control item for the "Always-Hidden" section.
    static let alwaysHiddenControlItem = MenuBarItemTag(controlItem: .alwaysHidden)

    // MARK: Other Special Items

    /// The namespace used by system-owned menu bar items (Clock, BentoBox, AudioVideoModule…).
    ///
    /// On macOS 26 the hosting process is Control Center; on macOS 27+ it is MenuBarAgent.
    private static var systemHostNamespace: Namespace {
        if #available(macOS 27, *) { .menuBarAgent } else { .controlCenter }
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

    /// The tag for the system "Music Recognition" item.
    static var musicRecognition: MenuBarItemTag {
        MenuBarItemTag(namespace: systemHostNamespace, title: "MusicRecognition")
    }

    /// The tag for the system item that appears in the menu bar
    /// during recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = MenuBarItemTag(namespace: .screenCaptureUI, title: "Item-0")

    /// The tag for the system "Siri" item.
    static let siri = MenuBarItemTag(namespace: .systemUIServer, title: "Siri")

    /// The tag for the system "SSMenuAgent" item (Screen Sharing menu extra).
    ///
    /// macOS prevents this item from being repositioned via Command+drag.
    /// The item visually follows the cursor during the drag, but springs
    /// back to its original position on mouse-up.
    static let ssMenuAgent = MenuBarItemTag(namespace: .ssMenuAgent, title: "Item-0")

    /// The tag for the system "Time Machine" item.
    static let timeMachine = MenuBarItemTag(namespace: .systemUIServer, title: "com.apple.menuextra.TimeMachine")

    /// The tag for the system "Game Mode" item.
    static let gameMode = MenuBarItemTag(namespace: .gamePolicyAgent, title: "Item-0")
}

// MARK: - MenuBarItemTag.Namespace

extension MenuBarItemTag {
    /// A type that represents a menu bar item namespace.
    enum Namespace: Hashable, CustomStringConvertible {
        /// The `null` namespace.
        case null
        /// A namespace represented by a string.
        case string(String)
        /// A namespace represented by a UUID.
        case uuid(UUID)

        /// A textual representation of the namespace.
        var description: String {
            switch self {
            case .null: "null"
            case let .string(string): string
            case let .uuid(uuid): uuid.uuidString
            }
        }

        /// A Boolean value that indicates whether this namespace is
        /// the `null` namespace.
        var isNull: Bool {
            switch self {
            case .null: true
            case .string, .uuid: false
            }
        }

        /// A Boolean value that indicates whether this namespace is
        /// represented by a string.
        var isString: Bool {
            switch self {
            case .string: true
            case .uuid, .null: false
            }
        }

        /// A Boolean value that indicates whether this namespace is
        /// represented by a UUID.
        var isUUID: Bool {
            switch self {
            case .uuid: true
            case .null, .string: false
            }
        }

        /// A Boolean value that indicates whether this namespace is the system
        /// process that owns menu bar item windows at the CG layer.
        ///
        /// On macOS 26 the hosting process is Control Center
        /// (`com.apple.controlcenter`); on macOS 27 and later it is
        /// MenuBarAgent (`com.apple.MenuBarAgent`).
        var isMenuBarHostingNamespace: Bool {
            if #available(macOS 27, *) {
                return self == .menuBarAgent
            } else {
                return self == .controlCenter
            }
        }

        /// Creates a namespace with the given optional value.
        ///
        /// - Parameter value: An optional value for the namespace.
        ///
        /// - Returns: A namespace represented by a string when `value`
        ///   is not `nil`. Otherwise, the `null` namespace.
        static func optional(_ value: String?) -> Namespace {
            value.map { .string($0) } ?? .null
        }
    }
}

// MARK: MenuBarItemTag.Namespace Constants

extension MenuBarItemTag.Namespace {
    /// The namespace for the "Thaw" process.
    static let thaw = string(Constants.bundleIdentifier)

    /// The namespace for the "Control Center" process.
    static let controlCenter = string("com.apple.controlcenter")

    /// The namespace for the "MenuBarAgent" process (macOS 27+).
    static let menuBarAgent = string("com.apple.MenuBarAgent")

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
