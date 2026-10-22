//
//  ProfileLayoutBehaviorSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Whether the profile follows the user's layout changes, and whether Thaw
/// applies it again when it starts with the profile already active.
struct ProfileLayoutBehaviorSection: View {
    @Bindable var profileManager: ProfileManager
    let profile: ProfileMetadata
    @Binding var errorMessage: String?

    var body: some View {
        ThawSection("Layout") {
            Toggle(isOn: keepsChanges) {
                ThawRowLabel(
                    "Keep layout changes in this profile",
                    detail: "Icons you move while this profile is active are saved into it. Turn off to keep the profile as a fixed layout."
                )
            }
            Toggle(isOn: reappliesAtLaunch) {
                ThawRowLabel(
                    "Apply again when \(Constants.displayName) starts",
                    detail: "Puts this profile's saved layout back each time \(Constants.displayName) starts, instead of keeping the menu bar as you left it."
                )
            }
        }
    }

    var keepsChanges: Binding<Bool> {
        binding(\.keepsLayoutChanges) { profileManager.setLayoutBehavior(keepsChanges: $0, forProfileID: profile.id) }
    }

    var reappliesAtLaunch: Binding<Bool> {
        binding(\.reappliesAtLaunch) { profileManager.setLayoutBehavior(reappliesAtLaunch: $0, forProfileID: profile.id) }
    }

    private func binding(_ keyPath: KeyPath<ProfileMetadata, Bool>, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding {
            (profileManager.profiles.first { $0.id == profile.id } ?? profile)[keyPath: keyPath]
        } set: { value in
            set(value)
            if let message = profileManager.takeManifestError() {
                errorMessage = message
            }
        }
    }
}
