//
//  FocusFilterIntentTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppIntents
import Foundation
import Testing
@testable import Thaw

/// The profile list and labels the system shows when someone sets up Thaw's
/// Focus filter. The query reads a manifest in a throwaway directory.
/// perform() is left out: it writes the app's own defaults and posts to every process.
@MainActor
@Suite("Focus filter intent", .serialized)
struct FocusFilterIntentTests {
    private func withQuery(
        seeding names: [String],
        _ body: (ProfileEntityQuery, [ProfileMetadata]) async throws -> Void
    ) async throws {
        let tmp = try ProfileTestDirectory.make(seeding: names)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let profiles = ProfileManager(profilesDirectory: tmp).profiles
        try await body(ProfileEntityQuery(manifestURL: tmp.appendingPathComponent("profiles.json")), profiles)
    }

    @Test("Suggestions list every profile in the manifest, in order")
    func suggestionsListEveryProfile() async throws {
        try await withQuery(seeding: ["Work", "Home"]) { query, profiles in
            let entities = try await query.suggestedEntities()
            #expect(entities.map(\.name) == ["Work", "Home"])
            #expect(entities.map(\.id) == profiles.map(\.id.uuidString))
        }
    }

    @Test("Looking up identifiers returns only the matching profiles")
    func lookupMatchesIdentifiers() async throws {
        try await withQuery(seeding: ["Work", "Home", "Travel"]) { query, profiles in
            let entities = try await query.entities(for: [profiles[2].id.uuidString, UUID().uuidString])
            #expect(entities.map(\.name) == ["Travel"])
            #expect(try await query.entities(for: []).isEmpty)
        }
    }

    @Test("A missing or unreadable manifest, or none at all, lists no profiles")
    func unreadableManifestListsNothing() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let missing = tmp.appendingPathComponent("absent.json")
        let garbage = tmp.appendingPathComponent("garbage.json")
        try Data("not a manifest".utf8).write(to: garbage)

        #expect(try await ProfileEntityQuery(manifestURL: missing).suggestedEntities().isEmpty)
        #expect(try await ProfileEntityQuery(manifestURL: garbage).suggestedEntities().isEmpty)
        #expect(try await ProfileEntityQuery(manifestURL: nil).suggestedEntities().isEmpty)
    }

    @Test("By default the query reads Thaw's manifest in Application Support")
    func defaultManifestLocation() throws {
        let url = try #require(ProfileEntity.defaultQuery.manifestURL)
        let appSupport = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        #expect(url == appSupport.appendingPathComponent("Thaw/Profiles/profiles.json"))
    }

    @Test("A profile shows its own name, and the type reads as a menu bar profile")
    func entityLabels() {
        let entity = ProfileEntity(id: UUID().uuidString, name: "Deep Work")
        #expect(String(localized: entity.displayRepresentation.title) == "Deep Work")
        #expect(String(localized: ProfileEntity.typeDisplayRepresentation.name) == "Menu Bar Profile")
    }

    @Test("The filter names the chosen profile, or says none is chosen")
    func filterSummary() throws {
        let filter = ThawFocusFilter()
        let empty = try #require(filter.displayRepresentation.subtitle)
        #expect(String(localized: empty) == "No profile selected")

        filter.profile = ProfileEntity(id: UUID().uuidString, name: "Deep Work")
        let chosen = try #require(filter.displayRepresentation.subtitle)
        #expect(String(localized: chosen) == "Profile: Deep Work")
        #expect(String(localized: filter.displayRepresentation.title) == "Set Menu Bar Profile")
        #expect(String(localized: ThawFocusFilter.title) == "Set Menu Bar Profile")
        #expect(ThawFocusFilter.description != nil)
    }
}
