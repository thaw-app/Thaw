//
//  ProfileListStep.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Where the up and down arrow keys move the selection in the Profiles list.
nonisolated enum ProfileListStep {
    /// The profile the arrow key selects, or nil when the key isn't up or
    /// down, nothing is selected, or the step would leave the list.
    static func profile(after current: UUID?, in profiles: [UUID], moving direction: MoveCommandDirection) -> UUID? {
        guard let current else { return nil }
        return profiles.neighbor(of: current, moving: direction)
    }
}
