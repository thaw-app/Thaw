//
//  ProfileCatalog.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawModuleKit

/// A profile as the module shows it: enough to pick one by name.
public struct ProfileSummary: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Reads Thaw's profiles folder. The module never writes there; Thaw owns
/// the profiles, the module only lists them and reads the scripts a profile
/// carried before scripts moved into the module.
public struct ProfileCatalog: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The folder Thaw keeps its profiles in.
    public static var thaw: ProfileCatalog {
        ProfileCatalog(directory: URL.applicationSupportDirectory.appending(path: "Thaw/Profiles", directoryHint: .isDirectory))
    }

    private struct Entry: Decodable {
        let id: UUID
        let name: String
    }

    private struct File: Decodable {
        let automation: ProfileAutomation?
    }

    public func profiles() -> [ProfileSummary] {
        guard let data = try? Data(contentsOf: directory.appending(path: "profiles.json")),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            return []
        }
        return entries.map { ProfileSummary(id: $0.id, name: $0.name) }
    }

    public func automation(forProfileID id: UUID) -> ProfileAutomation? {
        guard let data = try? Data(contentsOf: directory.appending(path: "\(id.uuidString).json")),
              let automation = try? JSONDecoder().decode(File.self, from: data).automation,
              !automation.isEmpty
        else {
            return nil
        }
        return automation
    }
}
