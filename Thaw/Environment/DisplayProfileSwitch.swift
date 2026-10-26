//
//  DisplayProfileSwitch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// What the resolveProfile step reads from the profile manager and asks of it.
@MainActor
protocol DisplayProfileTarget: AnyObject {
    var profiles: [ProfileMetadata] { get }
    var activeProfileID: UUID? { get }
    var focusFilterActive: Bool { get }
    func applyResolvedDisplayProfile(id: UUID)
}

extension ProfileManager: DisplayProfileTarget {}

/// The resolveProfile step of a display change. It remembers which display owned the menu bar at the
/// last change it resolved, which the resolution needs to tell a new display from a new size.
@MainActor
final class DisplayProfileSwitch {
    private(set) var lastDisplayUUID: String?

    init(displayUUID: String? = Bridging.getActiveMenuBarDisplayUUID()) {
        lastDisplayUUID = displayUUID
    }

    /// A display reached while Focus or a Space's profile wins still counts as reached. A nil display
    /// leaves the last one to compare the next change against.
    func settle(displayUUID: String?, activeSpaceKey: String?, on target: some DisplayProfileTarget) {
        let situation = DisplayProfileResolution.Situation(
            displayUUID: displayUUID,
            previousDisplayUUID: lastDisplayUUID,
            activeSpaceKey: activeSpaceKey,
            focusFilterActive: target.focusFilterActive,
            activeProfileID: target.activeProfileID
        )
        if let displayUUID {
            lastDisplayUUID = displayUUID
        }
        guard let id = DisplayProfileResolution.resolve(situation, profiles: target.profiles) else { return }
        target.applyResolvedDisplayProfile(id: id)
    }
}
