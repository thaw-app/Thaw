//
//  ProfileChangesSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// What applying the selected profile would change, and the button that
/// saves the current setup into it instead.
struct ProfileChangesSection: View {
    @Environment(AppState.self) private var appState

    let profile: Profile?
    let diff: ProfileLayoutDiff?
    let update: (ProfileManager.ProfileUpdateScope) -> Void
    let updateAll: () -> Void

    /// Read when the profile or the bar's layout changes, so drawing doesn't walk the item cache.
    @State private var liveImages: [String: MenuBarItemDisplayImage] = [:]

    var body: some View {
        ThawSection("Applying this profile changes") {
            if let profile {
                ProfilePreviewView(profile: profile, diff: diff, liveImages: liveImages, isInline: true)
            } else {
                Text("This profile couldn't be read.")
                    .foregroundStyle(ThawInk.supporting)
            }
            ThawMenu(
                primaryAction: { update(.all) },
                content: {
                    Button("Update Layout Only") { update(.layoutOnly) }
                    Button("Update Settings Only") { update(.configurationOnly) }
                    Divider()
                    Button("Update Settings in Every Profile", action: updateAll)
                },
                title: {
                    Text("Update with Current Setup")
                }
            )
            .help("Update this profile with the current layout and settings")
        }
        .onChange(of: profile?.id, initial: true) {
            liveImages = ProfilePreviewModel.liveImages(in: appState)
        }
        .onChange(of: appState.itemManager.itemCache) {
            liveImages = ProfilePreviewModel.liveImages(in: appState)
        }
    }
}
