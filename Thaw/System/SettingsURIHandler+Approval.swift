//
//  SettingsURIHandler+Approval.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension SettingsURIHandler {
    /// Whether sender may change settings without being asked, by the gate handleSettingsURL applies:
    /// a built-in trusted sender always, anyone else only with the Settings URI on and an approval stored.
    static func isApproved(
        _ sender: SettingsURISender?,
        isEnabled: () -> Bool = { isEnabled() },
        builtInTrust: (SettingsURISender) -> Bool = { isBuiltInTrustedSender($0) }
    ) -> Bool {
        guard let sender else { return false }
        if builtInTrust(sender) {
            return true
        }
        return isEnabled() && isWhitelisted(sender: sender, builtInTrust: builtInTrust)
    }
}
