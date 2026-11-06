//
//  ProfileManager+PendingApply.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ProfileManager {
    var pendingApplyProfileID: UUID? {
        layoutTask == nil ? nil : layoutTaskProfileID
    }
}
