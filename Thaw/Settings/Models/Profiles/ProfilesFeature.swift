//
//  ProfilesFeature.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation

/// The switch that turns profiles on or off. Off, no profile is applied on
/// its own, the profile shortcuts do nothing and no menu lists profiles.
/// Saved profiles stay on disk, so turning it back on finds them all.
@MainActor
@Observable
final class ProfilesFeature {
    var isOn: Bool {
        didSet {
            guard oldValue != isOn else { return }
            Defaults.set(isOn, forKey: .profilesEnabled)
            onChange?()
        }
    }

    /// Called after the switch changes, so the profile shortcuts can follow it.
    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        isOn = Self.isOnInDefaults
    }

    /// The saved choice, read where no ProfilesFeature is at hand. Profiles
    /// were always on before the switch existed, so nothing saved means on.
    static var isOnInDefaults: Bool {
        Defaults.object(forKey: .profilesEnabled) as? Bool ?? true
    }
}
