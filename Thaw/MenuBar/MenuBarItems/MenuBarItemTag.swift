//
//  MenuBarItemTag.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import CoreGraphics
import Foundation

// MARK: - MenuBarItemTag

/// An identifier for a menu bar item.
nonisolated struct MenuBarItemTag: Hashable, CustomStringConvertible {
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
        case .string, .uuid, .null:
            return false
        }
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag can be moved.
    var isMovable: Bool {
        !MenuBarItemTag.immovableItems.contains(where: { $0.namespace == namespace && $0.title == title })
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag can be hidden.
    var canBeHidden: Bool {
        !MenuBarItemTag.nonHideableItems.contains(where: { $0.namespace == namespace && $0.title == title }) &&
            !(namespace.isUUID && title == "AudioVideoModule")
    }

    /// A Boolean value that indicates whether this tag represents a
    /// dynamically-named Control Center item (Live Activities, etc.)
    /// with the pattern `controlCenter:Item-\d+`.
    var isControlCenterGenericItem: Bool {
        namespace == .controlCenter && MarkerPairResolver.isGenericControlCenterTitle(title)
    }

    /// Whether this tag names a Control Center module under another namespace,
    /// which only a wrong source-PID resolution produces.
    ///
    /// Spatial AX matching can skew on multi-display setups and give a module
    /// a neighboring app's PID (`com.techsmith.snagit.capturehelper:Battery`,
    /// #1027). Only the title reveals it. A false positive (an app titling its
    /// item "Battery") only loses its saved position.
    var isMisattributedControlCenterModule: Bool {
        namespace != .controlCenter && Self.isControlCenterModuleTitle(title)
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a control item owned by Ice.
    ///
    /// User-created spacers are not control items and stay draggable; only
    /// section-divider spacers count.
    var isControlItem: Bool {
        if namespace == .thaw && title.hasPrefix(MenuBarSpacerManager.autosavePrefix) {
            return false
        }
        return MenuBarItemTag.controlItems.contains(where: { $0.namespace == namespace && $0.title == title }) ||
            title.contains(".Spacer.")
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a "BentoBox" item owned by Control Center.
    var isBentoBox: Bool {
        namespace == .controlCenter && title.hasPrefix("BentoBox")
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a system-created clone of an actual item,
    /// and therefore invalid for management.
    ///
    /// Matches on the title alone: WindowServer names clones consistently,
    /// but their namespace can be a UUID, "Window Server", or even a nearby
    /// app's bundle ID.
    var isSystemClone: Bool {
        title == "System Status Item Clone"
    }

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
        namespace == other.namespace && title == other.title && instanceIndex == other.instanceIndex
    }

    /// Stable across window ID changes. Includes a nonzero instance index to
    /// tell same-titled items from one app apart.
    var tagIdentifier: String {
        if instanceIndex > 0 {
            return "\(namespace):\(title):\(instanceIndex)"
        }
        return "\(namespace):\(title)"
    }

    /// A lossless string encoding of this tag, suitable for persistence.
    ///
    /// Unlike ``tagIdentifier``, round-trips the namespace kind and instance
    /// index. Excludes the window ID, which doesn't survive a relaunch.
    ///
    /// Format: `<kind>:<namespaceValue>:<instanceIndex>:<title>`, where `kind`
    /// is `n` (null), `s` (string) or `u` (uuid). The title is the remainder of
    /// the string, so it may contain `:`.
    var persistenceKey: String {
        let kind: String
        let namespaceValue: String
        switch namespace {
        case .null:
            kind = "n"
            namespaceValue = ""
        case let .string(string):
            kind = "s"
            namespaceValue = string
        case let .uuid(uuid):
            kind = "u"
            namespaceValue = uuid.uuidString
        }
        return "\(kind):\(namespaceValue):\(instanceIndex):\(title)"
    }

    /// Creates a tag from a string produced by ``persistenceKey``.
    ///
    /// Returns `nil` if the string is not a valid encoding. The resulting tag
    /// has a `nil` window identifier.
    init?(persistenceKey: String) {
        let components = persistenceKey.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard components.count == 4 else { return nil }

        let kind = components[0]
        let namespaceValue = String(components[1])
        guard let instanceIndex = Int(components[2]) else { return nil }
        let title = String(components[3])

        let namespace: Namespace
        switch kind {
        case "n":
            namespace = .null
        case "s":
            namespace = .string(namespaceValue)
        case "u":
            guard let uuid = UUID(uuidString: namespaceValue) else { return nil }
            namespace = .uuid(uuid)
        default:
            return nil
        }

        self.init(namespace: namespace, title: title, windowID: nil, instanceIndex: instanceIndex)
    }

    // MARK: Volatile-Title Canonicalization

    /// Bundle identifier of the iStat Menus status agent, whose items title
    /// themselves with the metric they are currently displaying.
    static let iStatMenusStatusBundleID = "com.bjango.istatmenus.status"

    /// Collapses a live metric title to the shape it will still have a second
    /// from now.
    ///
    /// iStat Menus titles items with the live value ("CPU 12%"), so anything
    /// keyed by the title stops matching on the next sample. Numbers become
    /// `#` and byte units are normalized; "CPU" and "Network" stay distinct.
    static func canonicalMetricTitle(_ raw: String) -> String {
        raw
            .replacing(/[-+]?\d+(?:[.,]\d+)?/, with: "#")
            .replacing(/#\s*[KMGTPE]?[Bb]\/s/, with: "# B/s")
            .replacing(/#\s*[KMGTPE]?[Bb]/, with: "# B")
    }

    /// Bundle identifier of LyricsX, whose menu bar item titles itself with
    /// the lyric line currently on screen.
    static let lyricsXBundleID = "ddddxxx.LyricsX"

    /// The titles Control Center gives its own menu bar modules.
    ///
    /// Under any other namespace, one of these means a misresolved PID.
    /// `BentoBox` carries an instance suffix, so it's a prefix test. A closed
    /// list in macOS's exact casing, not a heuristic.
    static let controlCenterModuleTitles: Set<String> = [
        "Accessibility",
        "AudioVideoModule",
        "Battery",
        "Bluetooth",
        "BentoBox",
        "Clock",
        "Display",
        "FaceTime",
        "FocusModes",
        "Hearing",
        "KeyboardBrightness",
        "MusicRecognition",
        "NowPlaying",
        "ScreenMirroring",
        "Sound",
        "WiFi",
    ]

    /// Whether `title` names one of Control Center's own modules, allowing
    /// for the `BentoBox-<n>` instance suffix.
    static func isControlCenterModuleTitle(_ title: String) -> Bool {
        controlCenterModuleTitles.contains(title) || title.hasPrefix("BentoBox")
    }

    /// The foreign-namespace spelling of a Control Center module identifier,
    /// if it is one.
    ///
    /// Returns the Control Center spelling (title and instance index kept),
    /// or the input unchanged. Comparing with the input is the
    /// misattribution test ``LayoutSolver`` prunes on.
    ///
    /// `Item-N` titles are left alone: a third-party generic slot looks the
    /// same, and guessing would orphan real items.
    static func canonicalControlCenterModuleIdentifier(_ identifier: String) -> String {
        guard let separator = identifier.firstIndex(of: ":") else {
            return identifier
        }
        let namespace = String(identifier[..<separator])
        guard namespace != Namespace.controlCenter.description else {
            return identifier
        }
        let remainder = identifier[identifier.index(after: separator)...]
        var title = Substring(remainder)
        var instanceIndex: Substring?
        if let lastSeparator = title.lastIndex(of: ":"),
            Int(title[title.index(after: lastSeparator)...]) != nil
        {
            instanceIndex = title[title.index(after: lastSeparator)...]
            title = title[..<lastSeparator]
        }
        guard isControlCenterModuleTitle(String(title)) else {
            return identifier
        }
        if let instanceIndex {
            return "\(Namespace.controlCenter.description):\(title):\(instanceIndex)"
        }
        return "\(Namespace.controlCenter.description):\(title)"
    }

    /// The canonical title for an owner whose title carries no identity.
    ///
    /// A lyric has no stable skeleton, so it collapses to a constant and
    /// items are told apart only by instance index. Fine for single-item
    /// owners, hence an allowlist.
    static let opaqueTitle = "#"

    /// The volatile-title owner an identifier belongs to, if any, paired with
    /// how that owner's titles collapse.
    private static func volatileTitleOwner(
        of identifier: String
    ) -> (prefix: String, canonicalize: (String) -> String)? {
        let iStatPrefix = "\(iStatMenusStatusBundleID):"
        if identifier.hasPrefix(iStatPrefix) {
            return (iStatPrefix, canonicalMetricTitle)
        }
        let lyricsXPrefix = "\(lyricsXBundleID):"
        if identifier.hasPrefix(lyricsXPrefix) {
            return (lyricsXPrefix, { _ in opaqueTitle })
        }
        return nil
    }

    /// The canonical form of a `namespace:title[:index]` identifier.
    ///
    /// A no-op except for volatile-title owners, so safe on any identifier.
    static func canonicalPersistentIdentifier(_ identifier: String) -> String {
        guard let (prefix, canonicalize) = volatileTitleOwner(of: identifier) else {
            return identifier
        }

        let suffix = String(identifier.dropFirst(prefix.count))
        // Split off a trailing `:<digits>` instance index first.
        if let separator = suffix.lastIndex(of: ":") {
            let title = String(suffix[..<separator])
            let instance = String(suffix[suffix.index(after: separator)...])
            if Int(instance) != nil {
                return "\(prefix)\(canonicalize(title)):\(instance)"
            }
        }
        return "\(prefix)\(canonicalize(suffix))"
    }

    /// Canonicalizes a list of identifiers, dropping duplicates that only
    /// differed by their volatile portion and preserving first-seen order.
    static func canonicalPersistentIdentifiers(_ identifiers: [String]) -> [String] {
        Array(identifiers.map(canonicalPersistentIdentifier).uniqued())
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

nonisolated extension MenuBarItemTag {
    // MARK: Special Item Lists

    /// An array of tags for items whose movement is prevented by macOS.
    ///
    /// These items have fixed positions at the trailing end of the menu bar,
    /// and cannot be hidden.
    ///
    /// This list contains the "Clock", "Control Center", and "Screen Sharing" (ssMenuAgent) items.
    static let immovableItems: [MenuBarItemTag] = [clock, controlCenter, ssMenuAgent]

    /// An array of tags for items that can be moved, but cannot be hidden.
    static let nonHideableItems: [MenuBarItemTag] = [visibleControlItem, audioVideoModule, faceTime, screenCaptureUI, gameMode]

    /// An array of tags for items representing Ice's control items.
    static let controlItems = ControlItem.Identifier.allCases.map(\.tag)

    // MARK: Control Items

    /// The tag for Ice's control item for the "Visible" section.
    static let visibleControlItem = MenuBarItemTag(controlItem: .visible)

    /// The tag for Ice's control item for the "Hidden" section.
    static let hiddenControlItem = MenuBarItemTag(controlItem: .hidden)

    /// The tag for Ice's control item for the "Always-Hidden" section.
    static let alwaysHiddenControlItem = MenuBarItemTag(controlItem: .alwaysHidden)

    // MARK: Other Special Items

    /// The tag for the system item that appears in the menu bar
    /// during screen or audio capture.
    static let audioVideoModule = MenuBarItemTag(namespace: .controlCenter, title: "AudioVideoModule")

    /// The tag for the system "Clock" item.
    static let clock = MenuBarItemTag(namespace: .controlCenter, title: "Clock")

    /// The tag for the system "Control Center" item.
    static let controlCenter = MenuBarItemTag(namespace: .controlCenter, title: "BentoBox-0")

    /// The tag for the system "FaceTime" item.
    static let faceTime = MenuBarItemTag(namespace: .controlCenter, title: "FaceTime")

    /// The tag for the system item that appears in the menu bar
    /// during recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = MenuBarItemTag(namespace: .screenCaptureUI, title: "Item-0")

    /// The tag for the system "SSMenuAgent" item (Screen Sharing menu extra).
    ///
    /// macOS prevents this item from being repositioned via Command+drag.
    /// The item visually follows the cursor during the drag, but springs
    /// back to its original position on mouse-up.
    static let ssMenuAgent = MenuBarItemTag(namespace: .ssMenuAgent, title: "Item-0")

    /// The tag for the system "Game Mode" item.
    static let gameMode = MenuBarItemTag(namespace: .gamePolicyAgent, title: "Item-0")
}

// MARK: - MenuBarItemTag.Namespace

nonisolated extension MenuBarItemTag {
    /// A type that represents a menu bar item namespace.
    enum Namespace: Hashable, CustomStringConvertible {
        /// The `null` namespace.
        case null
        /// A namespace represented by a string.
        case string(String)
        /// A namespace represented by a UUID.
        case uuid(UUID)

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

nonisolated extension MenuBarItemTag.Namespace {
    /// The namespace for the "Thaw" process.
    static let thaw = string(Constants.bundleIdentifier)

    /// The namespace for the "Control Center" process.
    static let controlCenter = string("com.apple.controlcenter")

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

    /// Bundle identifiers of helper processes that own a menu bar item on
    /// behalf of a user-facing app, mapped to that app's identifier.
    ///
    /// Otherwise the item is named after a helper the user never installed.
    /// An explicit list, not a heuristic: stripping dot-components would fold
    /// distinct items together. Adding an entry costs that item's saved
    /// position once.
    ///
    /// Verify every entry against a live bar. OneDrive doesn't belong: its
    /// own ID is `com.microsoft.OneDrive-mac` and the main app owns the item.
    static let helperBundleIDAliases: [String: String] = [
        // Verified: Little Snitch Agent.app, inside the app bundle, owns the item.
        "at.obdev.littlesnitch.agent": "at.obdev.littlesnitch",
    ]

    /// Returns the user-facing app's bundle identifier for a bundle
    /// identifier that may belong to one of its helpers.
    ///
    /// The identity function for everything not in ``helperBundleIDAliases``.
    static func canonicalBundleID(_ bundleID: String) -> String {
        helperBundleIDAliases[bundleID] ?? bundleID
    }
}
