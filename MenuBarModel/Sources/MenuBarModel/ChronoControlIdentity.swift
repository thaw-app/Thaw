//
//  ChronoControlIdentity.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - ChronoControlIdentity

/// The identity of a Control Center control pinned directly to the menu bar.
///
/// macOS 27 lets a user drag any Control Center control (Dark Mode, Keyboard
/// Brightness, a Shortcut) out of a bento box and onto the menu bar. Those
/// controls are hosted by MenuBarAgent like the classic menu extras, but they
/// are published through Accessibility with a composite identifier instead of a
/// com.apple.menuextra.* name. The identifier is colon-separated: container
/// bundle ID, extension bundle ID, control identifier, then the displayable
/// instance UUID.
///
/// Only the first three components are durable; they match the archived
/// CHSControlIdentity values Control Center stores for the control. The trailing
/// UUID comes from the per-host com.apple.controlcenter.displayablemenuextras
/// domain and is minted fresh each time the control is placed in the menu bar. A
/// tag title that keeps that UUID therefore changes identity behind the user's
/// back, which drops whatever section assignment Thaw persisted for it.
public struct ChronoControlIdentity: Hashable, Sendable {
    /// The bundle identifier of the process hosting the control extension
    /// (com.apple.controlcenter for every Apple-provided control).
    public let containerBundleID: String

    /// The bundle identifier of the extension that vends the control
    /// (e.g. com.apple.controls.display).
    public let extensionBundleID: String

    /// The extension-scoped identifier of the individual control
    /// (e.g. com.apple.controls.display.dark-mode).
    public let controlIdentifier: String

    /// The displayable-instance UUID the control currently carries, when the
    /// parsed identifier included one. Volatile: never persist it.
    public let instanceID: String?

    /// The identifier with the volatile instance UUID removed, stable across
    /// removing the control from the menu bar and adding it back.
    public var stableIdentity: String {
        ":\(containerBundleID):\(extensionBundleID):\(controlIdentifier)"
    }

    /// A human-readable name derived from the control identifier's last
    /// component (for example display.dark-mode becomes Dark Mode).
    ///
    /// Only a fallback: the live Accessibility description ("Dark Mode") is the
    /// better label whenever it is available.
    public var derivedDisplayName: String {
        let leaf = controlIdentifier.split(separator: ".").last.map(String.init) ?? controlIdentifier
        return leaf
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Parses a MenuBarAgent Accessibility identifier, returning nil when it
    /// is not shaped like a Control Center control identity.
    ///
    /// Both the four-component form (no instance UUID) and the five-component
    /// form published in the menu bar are accepted.
    public init?(axIdentifier: String) {
        let components = axIdentifier.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        // The identifier is colon-prefixed, so the first component is empty.
        guard components.count == 4 || components.count == 5,
              components[0].isEmpty,
              components[1 ... 3].allSatisfy({ !$0.isEmpty })
        else {
            return nil
        }
        // A fifth component that is not a UUID is some other colon-delimited
        // identifier with five parts, not a control to strip the instance ID from.
        var instanceID: String?
        if components.count == 5 {
            guard UUID(uuidString: components[4]) != nil else {
                return nil
            }
            instanceID = components[4]
        }

        containerBundleID = components[1]
        extensionBundleID = components[2]
        controlIdentifier = components[3]
        self.instanceID = instanceID
    }

    /// The stable tag title for a MenuBarAgent Accessibility identifier, or
    /// nil when the identifier does not describe a Control Center control.
    public static func stableIdentity(forAXIdentifier identifier: String) -> String? {
        ChronoControlIdentity(axIdentifier: identifier)?.stableIdentity
    }
}
