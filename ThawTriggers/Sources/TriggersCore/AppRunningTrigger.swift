//
//  AppRunningTrigger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

public struct AppRunningTrigger: Codable, Equatable, Identifiable, Sendable {
    public struct Target: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var id = UUID()
    public var appBundleID = ""
    public var appName = ""
    public var targets: [Target] = []
    public var isEnabled = true

    public init(id: UUID = UUID(), appBundleID: String = "", appName: String = "", targets: [Target] = [], isEnabled: Bool = true) {
        self.id = id
        self.appBundleID = appBundleID
        self.appName = appName
        self.targets = targets
        self.isEnabled = isEnabled
    }

    /// Whether the trigger's app is running. Background apps count too.
    public func matches(runningBundleIDs: Set<String>) -> Bool {
        isEnabled && !appBundleID.isEmpty && runningBundleIDs.contains(appBundleID)
    }

    public var isValid: Bool {
        !appBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !targets.isEmpty
            && targets.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty }
            && Set(targets.map(\.id)).count == targets.count
    }
}
