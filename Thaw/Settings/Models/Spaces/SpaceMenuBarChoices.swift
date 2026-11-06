//
//  SpaceMenuBarChoices.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import MenuBarModel

/// What the Spaces page set for one Space. Defaults mean nothing to apply.
nonisolated struct SpaceMenuBarChoice: Codable, Equatable, Sendable {
    var isHidden = false
    var isAutoShowDisabled = false
    var revealStripHeight: Double?

    var isEmpty: Bool {
        !isHidden && !isAutoShowDisabled && revealStripHeight == nil
    }
}

/// Every choice on the Spaces page, keyed by each Space's persistent key,
/// which survives logout where a Space's identifier does not.
nonisolated struct SpaceMenuBarChoices: Codable, Equatable, Sendable {
    var spaces: [String: SpaceMenuBarChoice] = [:]
    var isHiddenEverywhere = false
    var usesFullScreenAppearanceEverywhere = false

    func choice(forKey key: String) -> SpaceMenuBarChoice {
        spaces[key] ?? SpaceMenuBarChoice()
    }

    /// Changes the choice for key, dropping it once it is back to the defaults.
    mutating func update(key: String, _ change: (inout SpaceMenuBarChoice) -> Void) {
        var choice = choice(forKey: key)
        change(&choice)
        spaces[key] = choice.isEmpty ? nil : choice
    }
}

/// One override to send to the menu bar agent.
nonisolated enum SpaceMenuBarRequest: Equatable, Sendable {
    case hiddenEverywhere
    case fullScreenAppearanceEverywhere
    case hidden(spaceID: UInt64)
    case autoShowDisabled(spaceID: UInt64)
    case revealStripHeight(Double, spaceID: UInt64)
    case shownEverywhere
    case standardAppearanceEverywhere
    case clearOverrides(spaceID: UInt64)
}

/// Decides what to send the menu bar agent again, since it forgets every override when Thaw quits.
nonisolated enum SpaceMenuBarReapply {
    enum Scope: Equatable, Sendable {
        /// At launch or after the agent restarts.
        case everything
        /// Spaces that just appeared.
        case spaces(Set<String>)
    }

    /// The requests that restore choices, translating each key to the Space's identifier now.
    /// A key whose Space is gone sends nothing but stays stored.
    static func requests(for choices: SpaceMenuBarChoices, spaces: [Bridging.ManagedSpace], scope: Scope) -> [SpaceMenuBarRequest] {
        var requests: [SpaceMenuBarRequest] = []
        if scope == .everything {
            if choices.isHiddenEverywhere {
                requests.append(.hiddenEverywhere)
            }
            if choices.usesFullScreenAppearanceEverywhere {
                requests.append(.fullScreenAppearanceEverywhere)
            }
        }
        for space in spaces {
            if case let .spaces(keys) = scope, !keys.contains(space.persistentKey) {
                continue
            }
            guard let choice = choices.spaces[space.persistentKey], space.spaceID > 0 else { continue }
            let spaceID = UInt64(space.spaceID)
            if choice.isHidden {
                requests.append(.hidden(spaceID: spaceID))
            }
            if choice.isAutoShowDisabled {
                requests.append(.autoShowDisabled(spaceID: spaceID))
            }
            if let height = choice.revealStripHeight {
                requests.append(.revealStripHeight(height, spaceID: spaceID))
            }
        }
        return requests
    }

    /// The requests that undo what choices set, for Reset All Settings.
    static func resetRequests(for choices: SpaceMenuBarChoices, spaces: [Bridging.ManagedSpace]) -> [SpaceMenuBarRequest] {
        var requests: [SpaceMenuBarRequest] = []
        if choices.isHiddenEverywhere {
            requests.append(.shownEverywhere)
        }
        if choices.usesFullScreenAppearanceEverywhere {
            requests.append(.standardAppearanceEverywhere)
        }
        for space in spaces where space.spaceID > 0 && choices.spaces[space.persistentKey] != nil {
            requests.append(.clearOverrides(spaceID: UInt64(space.spaceID)))
        }
        return requests
    }

    /// Keys in the new list that the old one didn't have.
    static func newKeys(from old: [Bridging.ManagedSpace], to new: [Bridging.ManagedSpace]) -> Set<String> {
        Set(new.map(\.persistentKey)).subtracting(old.map(\.persistentKey))
    }

    /// The key of the Space with spaceID, or nil when the list doesn't have it.
    static func key(forSpaceID spaceID: UInt64, in spaces: [Bridging.ManagedSpace]) -> String? {
        spaces.first { UInt64(clamping: $0.spaceID) == spaceID && spaceID != 0 }?.persistentKey
    }
}

/// Tells a restarted menu bar agent apart from the one Thaw already talked to.
nonisolated struct MenuBarAgentRestartDetector {
    private var lastPIDs: Set<pid_t>?

    /// Whether pids, the agent's processes now, mean it restarted. An empty set is the gap while it relaunches.
    mutating func observe(_ pids: Set<pid_t>) -> Bool {
        guard !pids.isEmpty else { return false }
        defer { lastPIDs = pids }
        guard let lastPIDs else { return false }
        return pids != lastPIDs
    }
}
