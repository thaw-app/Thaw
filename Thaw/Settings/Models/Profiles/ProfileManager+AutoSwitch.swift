//
//  ProfileManager+AutoSwitch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ProfileManager {
    /// Applies the profile a settled display change resolved to. See DisplayProfileSwitch.
    func applyResolvedDisplayProfile(id: UUID) {
        guard let appState, let meta = profiles.first(where: { $0.id == id }) else { return }
        switchAutomatically(to: meta, on: appState, trigger: "the settled display change", relaunchesApps: false)
    }

    /// Makes an automatic switch's profile active and starts applying it, unless the launch gate keeps
    /// the live layout. The apply's layout task is in place on return, so a settle that ends meanwhile
    /// finds it pending instead of applying the profile again.
    /// A display-driven switch writes the profile's spacing without relaunching apps, so docking never restarts them.
    func switchAutomatically(to meta: ProfileMetadata, on appState: AppState, trigger: String, relaunchesApps: Bool = true) {
        guard !keepsLiveLayoutAtLaunch(meta) else { return }
        diagLog.info("Auto-switching to profile \(meta.name) for \(trigger)")
        do {
            let profile = try loadProfile(id: meta.id)
            let previousID = activeProfileID
            activeProfileID = meta.id
            applyProfile(profile, to: appState, previousProfileID: previousID, relaunchesApps: relaunchesApps)
        } catch {
            diagLog.error("Auto-switch for \(trigger) failed: \(error)")
        }
    }
}
