//
//  SpaceLabels.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// One Space as Settings lists it.
nonisolated struct SpaceChoice: Hashable, Identifiable, Sendable {
    /// The persistent key a profile stores.
    let id: String
    let label: String
    let kind: ManagedSpaceKind
    /// The app a full screen Space belongs to, for its icon.
    let ownerPID: pid_t?
    /// Whether a profile names this Space but the window server no longer lists it.
    let isMissing: Bool
}

/// The Spaces of one display, in Mission Control's order.
nonisolated struct SpaceDisplayGroup: Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let hasMenuBar: Bool
    let spaces: [SpaceChoice]
}

/// Names Spaces the way Mission Control does: desktops are numbered per
/// display, and a full screen Space takes the name of its app.
nonisolated enum SpaceLabels {
    /// Each desktop's number on its own display, counting desktops only.
    static func desktopNumbers(_ spaces: [Bridging.ManagedSpace]) -> [CGSSpaceID: Int] {
        var counts: [String: Int] = [:]
        var numbers: [CGSSpaceID: Int] = [:]
        for space in spaces where space.kind == .desktop {
            let number = counts[space.displayIdentifier, default: 0] + 1
            counts[space.displayIdentifier] = number
            numbers[space.spaceID] = number
        }
        return numbers
    }

    /// The label for space; ownerName is the full screen app's name when known.
    static func label(for space: Bridging.ManagedSpace, desktopNumber: Int?, ownerName: String?) -> String {
        switch space.kind {
        case .desktop:
            String(localized: "Desktop \(desktopNumber ?? space.ordinal)", comment: "A desktop Space, numbered as Mission Control numbers it.")
        case .fullscreen:
            ownerName ?? String(localized: "Full Screen App", comment: "A full screen Space whose app is unknown.")
        case .other:
            String(localized: "Other Space", comment: "A Space of a kind Thaw doesn't recognize.")
        }
    }

    /// Spaces grouped by display, in the window server's display order.
    /// - Parameters:
    ///   - displayNames: Display names keyed by display UUID.
    ///   - menuBarDisplay: The UUID of the display that has the active menu bar.
    ///   - ownerName: The name of the app with a given process identifier.
    static func groups(
        _ spaces: [Bridging.ManagedSpace],
        displayNames: [String: String],
        menuBarDisplay: String?,
        ownerName: (pid_t) -> String?
    ) -> [SpaceDisplayGroup] {
        let numbers = desktopNumbers(spaces)
        var order: [String] = []
        var choices: [String: [SpaceChoice]] = [:]
        for space in spaces {
            if choices[space.displayIdentifier] == nil {
                order.append(space.displayIdentifier)
            }
            let name = space.ownerPID.flatMap(ownerName)
            choices[space.displayIdentifier, default: []].append(SpaceChoice(
                id: space.persistentKey,
                label: label(for: space, desktopNumber: numbers[space.spaceID], ownerName: name),
                kind: space.kind,
                ownerPID: space.ownerPID,
                isMissing: false
            ))
        }
        return order.map { identifier in
            SpaceDisplayGroup(
                id: identifier,
                displayName: displayNames[identifier] ?? String(localized: "Display", comment: "A display whose name Thaw doesn't know."),
                hasMenuBar: identifier == menuBarDisplay || (order.count == 1 && menuBarDisplay != nil),
                spaces: choices[identifier] ?? []
            )
        }
    }

    /// Spaces profiles still name that the window server no longer lists. Kept so the choice stays visible.
    /// - Parameter mapped: Each stored key with the name stored beside it.
    static func missing(mapped: [(key: String, name: String?)], present: [Bridging.ManagedSpace]) -> [SpaceChoice] {
        let presentKeys = Set(present.map(\.persistentKey))
        var seen: Set<String> = []
        return mapped.compactMap { entry in
            guard !presentKeys.contains(entry.key), seen.insert(entry.key).inserted else { return nil }
            return SpaceChoice(
                id: entry.key,
                label: entry.name ?? String(localized: "A Space"),
                kind: .desktop,
                ownerPID: nil,
                isMissing: true
            )
        }
    }

    /// Fills in the owner of each full screen Space whose entry names none: the
    /// first app with an ordinary window that lives on that Space.
    /// - Parameters:
    ///   - windows: Ordinary windows in front-to-back order.
    ///   - spacesOfWindow: The Spaces a window is on.
    static func resolvingOwners(
        _ spaces: [Bridging.ManagedSpace],
        windows: [(pid: pid_t, windowID: CGWindowID)],
        spacesOfWindow: (CGWindowID) -> [CGSSpaceID]
    ) -> [Bridging.ManagedSpace] {
        let unowned = Set(spaces.filter { $0.kind == .fullscreen && $0.ownerPID == nil }.map(\.spaceID))
        guard !unowned.isEmpty else { return spaces }
        var owners: [CGSSpaceID: pid_t] = [:]
        for window in windows where owners.count < unowned.count {
            for spaceID in spacesOfWindow(window.windowID) where unowned.contains(spaceID) && owners[spaceID] == nil {
                owners[spaceID] = window.pid
            }
        }
        return spaces.map { space in
            guard let owner = owners[space.spaceID] else { return space }
            return Bridging.ManagedSpace(
                spaceID: space.spaceID,
                persistentKey: space.persistentKey,
                displayIdentifier: space.displayIdentifier,
                ordinal: space.ordinal,
                kind: space.kind,
                ownerPID: owner
            )
        }
    }

    /// The label of the Space with spaceID, for storing beside a profile's key.
    static func label(ofSpaceID spaceID: CGSSpaceID, in spaces: [Bridging.ManagedSpace], ownerName: (pid_t) -> String?) -> String? {
        guard let space = spaces.first(where: { $0.spaceID == spaceID }) else { return nil }
        return label(for: space, desktopNumber: desktopNumbers(spaces)[spaceID], ownerName: space.ownerPID.flatMap(ownerName))
    }
}

extension SpaceLabels {
    /// The live Space list with full screen owners filled in. Walks the window list only when an owner is missing.
    static func liveSpaces() -> [Bridging.ManagedSpace] {
        let spaces = Bridging.getManagedSpaces()
        guard spaces.contains(where: { $0.kind == .fullscreen && $0.ownerPID == nil }) else { return spaces }
        let windows = WindowInfo.createWindows().filter { $0.layer == 0 }.map { (pid: $0.ownerPID, windowID: $0.windowID) }
        return resolvingOwners(spaces, windows: windows) { Bridging.getSpaceList(for: $0) }
    }

    static func liveOwnerName(_ pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
