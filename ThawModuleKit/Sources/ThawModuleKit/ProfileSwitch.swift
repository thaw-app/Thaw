//
//  ProfileSwitch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A profile switch Thaw announces to its modules, before and after the layout changes. It carries no
/// script path, so a stray sender can only make a module run scripts the user already chose.
public struct ProfileSwitch: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case willApply
        case didApply
    }

    public let profileID: UUID
    public let profileName: String
    public let previousProfileID: UUID?
    public let previousProfileName: String?

    public init(profileID: UUID, profileName: String, previousProfileID: UUID?, previousProfileName: String?) {
        self.profileID = profileID
        self.profileName = profileName
        self.previousProfileID = previousProfileID
        self.previousProfileName = previousProfileName
    }

    /// The notification name for a phase. It starts with the bundle ID of the
    /// Thaw that posts it, so a debug build and a release build don't hear
    /// each other's switches.
    public static func notificationName(_ phase: Phase, hostBundleIdentifier: String) -> Notification.Name {
        Notification.Name("\(hostBundleIdentifier).module.profile.\(phase.rawValue)")
    }

    private enum Key {
        static let profileID = "profileID"
        static let profileName = "profileName"
        static let previousProfileID = "previousProfileID"
        static let previousProfileName = "previousProfileName"
    }

    /// The notification's user info. Only strings, so it survives the trip
    /// between processes.
    public var userInfo: [String: String] {
        var info = [Key.profileID: profileID.uuidString, Key.profileName: profileName]
        info[Key.previousProfileID] = previousProfileID?.uuidString
        info[Key.previousProfileName] = previousProfileName
        return info
    }

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let id = (userInfo[Key.profileID] as? String).flatMap(UUID.init(uuidString:)),
              let name = userInfo[Key.profileName] as? String
        else {
            return nil
        }
        self.init(
            profileID: id,
            profileName: name,
            previousProfileID: (userInfo[Key.previousProfileID] as? String).flatMap(UUID.init(uuidString:)),
            previousProfileName: userInfo[Key.previousProfileName] as? String
        )
    }
}

/// Values Thaw hands a module when it launches one.
public enum ModuleLaunchEnvironment {
    /// The environment variable that holds the launching Thaw's bundle ID.
    public static let hostBundleIdentifierKey = "THAW_HOST_BUNDLE_ID"

    /// The launch argument Thaw passes when the user asks to see a module's window.
    public static let showWindowArgument = "--show-window"

    /// What sits between Thaw's bundle ID and a module's identifier in the
    /// module's bundle ID, as in com.example.Thaw.module.triggers.
    public static let moduleBundleSeparator = ".module."

    /// The Thaw a module belongs to. Thaw passes its bundle ID at launch; a
    /// module opened by hand works it out from its own bundle ID.
    public static func hostBundleIdentifier(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> String? {
        if let host = environment[hostBundleIdentifierKey] {
            return host
        }
        guard let bundleIdentifier, let range = bundleIdentifier.range(of: moduleBundleSeparator) else {
            return nil
        }
        return String(bundleIdentifier[..<range.lowerBound])
    }
}

/// The modules that come with Thaw, by the identifier each declares in its
/// Info.plist. Scripts keeps the identifier automation from before it was
/// renamed, so saved choices still apply.
public enum ModuleIdentifier: String, CaseIterable, Sendable {
    case scripts = "automation"
    case triggers
    case widgets
}
