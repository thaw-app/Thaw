//
//  AppRunningTrigger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

struct AppRunningTrigger: Codable, Equatable, Identifiable {
    struct Target: Codable, Equatable, Identifiable {
        var id: String
        var name: String
    }

    var id = UUID()
    var appBundleID = ""
    var appName = ""
    var targets: [Target] = []
    var isEnabled = true

    /// Ported from the 2.2 appRunning condition; background apps count too.
    func matches(runningBundleIDs: Set<String>) -> Bool {
        isEnabled && !appBundleID.isEmpty && runningBundleIDs.contains(appBundleID)
    }

    var isValid: Bool {
        !appBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !targets.isEmpty
            && targets.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty }
            && Set(targets.map(\.id)).count == targets.count
    }
}
