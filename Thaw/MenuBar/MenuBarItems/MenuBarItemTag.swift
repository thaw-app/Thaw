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
        case .controlCenter, .systemUIServer, .textInputMenuAgent, .weather, .passwords, .screenCaptureUI, .ssMenuAgent, .thaw:
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

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a control item owned by Ice.
    var isControlItem: Bool {
        MenuBarItemTag.controlItems.contains(where: { $0.namespace == namespace && $0.title == title }) ||
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
    var isSystemClone: Bool {
        namespace.isUUID && title == "System Status Item Clone"
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
        namespace == other.namespace && title == other.title && instanceIndex == other.instanceIndex
    }

    /// A stable string identifier that uniquely identifies this tag
    /// across window ID changes (e.g. app restarts). Includes the
    /// instance index when it is nonzero so that multiple items from
    /// the same app with the same title are distinguishable.
    var tagIdentifier: String {
        if instanceIndex > 0 {
            return "\(namespace):\(title):\(instanceIndex)"
        }
        return "\(namespace):\(title)"
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

    /// An array of tags for items whose movement is prevented by macOS.
    ///
    /// These items have fixed positions at the trailing end of the menu bar,
    /// and cannot be hidden.
    ///
    /// In macOS 26, this list contains the "Clock" and "Control Center" items.
    /// In earlier releases, it also contained the "Siri" item.
    static let immovableItems: [MenuBarItemTag] = {
        var items = [clock, controlCenter, ssMenuAgent]
        if #unavailable(macOS 26.0) {
            items.append(siri)
        }
        return items
    }()

    /// NOTE: MusicRecognition became hideable at some point. If the minimum
    /// deployment target is raised, this item may need conditional exclusion.
    ///
    /// We're using macOS 15.3.2 for now, but it could be earlier.
    ///
    /// An array of tags for items that can be moved, but cannot be hidden.
    static let nonHideableItems: [MenuBarItemTag] = {
        var items = [visibleControlItem, audioVideoModule, faceTime, screenCaptureUI]
        if #unavailable(macOS 15.3.2) {
            items.append(musicRecognition)
        }
        return items
    }()

    /// An array of tags for items representing Ice's control items.
    static let controlItems = ControlItem.Identifier.allCases.map { $0.tag }

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
    static let controlCenter = if #available(macOS 26.0, *) {
        MenuBarItemTag(namespace: .controlCenter, title: "BentoBox-0")
    } else {
        MenuBarItemTag(namespace: .controlCenter, title: "BentoBox")
    }

    /// The tag for the system "FaceTime" item.
    static let faceTime = MenuBarItemTag(namespace: .controlCenter, title: "FaceTime")

    /// The tag for the system "Music Recognition" item.
    static let musicRecognition = MenuBarItemTag(namespace: .controlCenter, title: "MusicRecognition")

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
    static let timeMachine = if #available(macOS 26.0, *) {
        MenuBarItemTag(namespace: .systemUIServer, title: "com.apple.menuextra.TimeMachine")
    } else if #available(macOS 15.0, *) {
        MenuBarItemTag(namespace: .systemUIServer, title: "TimeMachineMenuExtra.TMMenuExtraHost")
    } else {
        MenuBarItemTag(namespace: .systemUIServer, title: "TimeMachine.TMMenuExtraHost")
    }
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

    /// The namespace for the "WeatherMenu" process.
    static let weather = string("com.apple.weather.menu")
}
