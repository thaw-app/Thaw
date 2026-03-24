//
//  FocusFilterIntent.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppIntents

/// An entity representing a Thaw profile, exposed to the system
/// so users can pick one when configuring a Focus Filter.
struct ProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Menu Bar Profile"
    }

    static var defaultQuery = ProfileEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Queries the on-disk profile manifest so the system can list
/// available profiles without requiring the full app state.
struct ProfileEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProfileEntity] {
        allProfiles().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        allProfiles()
    }

    private func allProfiles() -> [ProfileEntity] {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let manifestURL = appSupport
            .appendingPathComponent("Thaw/Profiles/profiles.json")

        guard let data = try? Data(contentsOf: manifestURL) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifests = try? decoder.decode(
            [ProfileMetadata].self, from: data
        ) else { return [] }

        return manifests.map {
            ProfileEntity(id: $0.id.uuidString, name: $0.name)
        }
    }
}

/// Focus Filter that applies a Thaw profile when a Focus mode activates.
/// Appears in System Settings → Focus → [mode] → Focus Filters → Add "Thaw".
struct ThawFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set Menu Bar Profile"
    static var description: IntentDescription? = IntentDescription(
        "Apply a Thaw menu bar profile when this Focus activates.",
        categoryName: "Profiles"
    )

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Set Menu Bar Profile",
            subtitle: profile.map { "Profile: \($0.name)" } ?? "No profile selected"
        )
    }

    @Parameter(title: "Profile")
    var profile: ProfileEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let profile,
              let profileID = UUID(uuidString: profile.id)
        else {
            // Focus deactivated — clear the stored profile and notify.
            UserDefaults.standard.removeObject(forKey: "FocusFilterRequestedProfileID")
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.stonerl.Thaw.focusFilterDeactivated"),
                object: nil,
                deliverImmediately: true
            )
            return .result()
        }

        UserDefaults.standard.set(
            profile.id,
            forKey: "FocusFilterRequestedProfileID"
        )
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.stonerl.Thaw.focusFilterActivated"),
            object: nil,
            userInfo: ["profileID": profile.id],
            deliverImmediately: true
        )

        return .result()
    }
}
