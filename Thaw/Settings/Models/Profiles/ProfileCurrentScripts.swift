//
//  ProfileCurrentScripts.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawModuleKit

extension Profile {
    /// The profile with the scripts the user has now, for an export or a copy. Scripts are edited
    /// in the Scripts module, so the profile file can hold an older set or none.
    func withCurrentScripts(moduleDefaults: UserDefaults?) -> Profile {
        var profile = self
        profile.automation = SavedScripts.automation(forProfileID: id, inFile: automation, moduleDefaults: moduleDefaults)
        return profile
    }
}

extension UserDefaults {
    /// The Scripts module's defaults for this Thaw, or nil without a bundle ID.
    static var scriptsModule: UserDefaults? {
        Bundle.main.bundleIdentifier.flatMap { UserDefaults(suiteName: SavedScripts.domain(hostBundleIdentifier: $0)) }
    }
}
