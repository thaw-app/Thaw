//
//  ThawUIWords+Permissions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - Permissions

extension PermissionStrings {
    static let thaw = PermissionStrings(
        optional: "Optional",
        granted: "Granted",
        grantAccess: "Grant Access",
        openSettings: "Open System Settings"
    )
}

extension Permission: PermissionPresentable {
    var titleText: Text {
        Text(title)
    }
}

extension PermissionLabel {
    init(permission: any PermissionPresentable, titleFont: Font? = nil, badgePlacement: BadgePlacement = .adjacent) {
        self.init(permission: permission, strings: .thaw, titleFont: titleFont, badgePlacement: badgePlacement)
    }
}

extension PermissionStatusControl {
    init(permission: any PermissionPresentable, layout: Layout = .inline) {
        self.init(permission: permission, strings: .thaw, layout: layout)
    }
}
