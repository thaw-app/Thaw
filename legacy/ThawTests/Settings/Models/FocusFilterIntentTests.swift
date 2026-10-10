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

/// Covers ``ThawFocusFilter`` and ``ProfileEntityQuery``, the App Intents
/// surface that lets a macOS Focus mode switch Thaw's menu bar profile.
///
/// `perform()` writes the `FocusFilterRequestedProfileID` default and posts a
/// `DistributedNotificationCenter` notification. Only the default is asserted:
/// the post is delivered on a run loop the test can't join, so asserting it
/// would be flaky. `ProfileManagerPersistenceTests` covers the receiving half.
///
/// Filter cases run in `withScratchDefaults`. The suite stays `.serialized`
/// because some cases read `nonisolated(unsafe) static var`s.
///
/// Gap: `ProfileEntityQuery.allProfiles()` hardcodes the Application Support
/// path with no injection point, so these cases only assert invariants that
/// hold for both an empty and a populated manifest.
@MainActor
@Suite("Thaw Focus Filter intent", .serialized)
struct FocusFilterIntentTests {
    /// The `UserDefaults` key the filter hands to `ProfileManager`. Pinned as a
    /// literal because renaming it on one side silently stops profile switching.
    private static let requestedProfileKey = "FocusFilterRequestedProfileID"

    // MARK: Performing the filter

    @Test("Performing with a selected profile stores that profile's identifier")
    func performStoresTheSelectedProfileIdentifier() async throws {
        try await withScratchDefaults { suite in
            let identifier = UUID().uuidString
            let filter = ThawFocusFilter()
            filter.profile = ProfileEntity(id: identifier, name: "Work")

            _ = try await filter.perform()

            #expect(suite.string(forKey: Self.requestedProfileKey) == identifier)
        }
    }

    @Test("Performing with no profile clears a previously requested identifier")
    func performWithoutAProfileClearsTheStoredIdentifier() async throws {
        try await withScratchDefaults { suite in
            // A Focus turning off performs the filter with no profile, so the
            // request left by the Focus turning on has to be withdrawn rather
            // than left standing.
            suite.set(UUID().uuidString, forKey: Self.requestedProfileKey)
            let filter = ThawFocusFilter()

            _ = try await filter.perform()

            #expect(suite.string(forKey: Self.requestedProfileKey) == nil)
        }
    }

    @Test("Performing with an identifier that is not a UUID clears the stored identifier")
    func performWithANonUUIDIdentifierClearsTheStoredIdentifier() async throws {
        try await withScratchDefaults { suite in
            suite.set(UUID().uuidString, forKey: Self.requestedProfileKey)
            let filter = ThawFocusFilter()
            // The entity's id is a plain `String`, so a stale or hand-built
            // entity can carry something that is not a profile identifier.
            filter.profile = ProfileEntity(id: "not-a-uuid", name: "Bogus")

            _ = try await filter.perform()

            #expect(suite.string(forKey: Self.requestedProfileKey) == nil)
        }
    }

    @Test("Performing with an empty identifier clears the stored identifier")
    func performWithAnEmptyIdentifierClearsTheStoredIdentifier() async throws {
        try await withScratchDefaults { suite in
            suite.set(UUID().uuidString, forKey: Self.requestedProfileKey)
            let filter = ThawFocusFilter()
            filter.profile = ProfileEntity(id: "", name: "")

            _ = try await filter.perform()

            #expect(suite.string(forKey: Self.requestedProfileKey) == nil)
        }
    }

    @Test("Performing replaces the identifier requested by an earlier Focus")
    func performReplacesAPreviouslyRequestedIdentifier() async throws {
        try await withScratchDefaults { suite in
            let superseded = UUID().uuidString
            let requested = UUID().uuidString
            suite.set(superseded, forKey: Self.requestedProfileKey)
            let filter = ThawFocusFilter()
            filter.profile = ProfileEntity(id: requested, name: "Focus")

            _ = try await filter.perform()

            // Switching directly from one Focus to another performs the new
            // filter without ever performing the old one's "off" pass.
            #expect(suite.string(forKey: Self.requestedProfileKey) == requested)
        }
    }

    @Test("Performing twice with the same profile leaves the same identifier stored")
    func performIsIdempotentForTheSameProfile() async throws {
        try await withScratchDefaults { suite in
            let identifier = UUID().uuidString
            let filter = ThawFocusFilter()
            filter.profile = ProfileEntity(id: identifier, name: "Work")

            _ = try await filter.perform()
            _ = try await filter.perform()

            #expect(suite.string(forKey: Self.requestedProfileKey) == identifier)
        }
    }

    // MARK: Display representation

    /// Both sides resolve through the same string catalog, so the comparison
    /// holds in every localization.
    @Test("The filter's display representation names the selected profile")
    func displayRepresentationNamesTheSelectedProfile() throws {
        // Held in a variable rather than written inline, so the expectation's
        // interpolation resolves the same "Profile: %@" catalog entry the
        // production string does instead of folding into a literal key.
        let name = "Work"
        let filter = ThawFocusFilter()
        filter.profile = ProfileEntity(id: UUID().uuidString, name: name)

        let representation = filter.displayRepresentation

        #expect(String(localized: representation.title) == String(localized: "Set Menu Bar Profile"))
        let subtitle = try #require(representation.subtitle)
        #expect(String(localized: subtitle) == String(localized: "Profile: \(name)"))
    }

    @Test("The filter's display representation says so when no profile is selected")
    func displayRepresentationReportsNoSelection() throws {
        let filter = ThawFocusFilter()

        let representation = filter.displayRepresentation

        let subtitle = try #require(representation.subtitle)
        #expect(String(localized: subtitle) == String(localized: "No profile selected"))
    }

    @Test("The filter is presented to the system under the Profiles category")
    func intentMetadata() throws {
        // `title` and `description` are `nonisolated(unsafe) static var`s, so
        // only read them. The category name groups the filter in the picker.
        #expect(String(localized: ThawFocusFilter.title) == String(localized: "Set Menu Bar Profile"))

        let description: IntentDescription = try #require(ThawFocusFilter.description)
        #expect(
            String(localized: description.descriptionText)
                == String(localized: "Apply a Thaw menu bar profile when this Focus activates.")
        )
        let categoryName = try #require(description.categoryName)
        #expect(String(localized: categoryName) == String(localized: "Profiles"))
    }

    // MARK: Profile entity query

    @Test("Querying an identifier that names no profile returns nothing")
    func queryForAnUnknownIdentifierReturnsNothing() async throws {
        // A freshly minted UUID cannot be in the on-disk manifest, so this
        // holds whether or not the machine has real profiles.
        let unknown = UUID().uuidString

        let entities = try await ProfileEntityQuery().entities(for: [unknown])

        #expect(entities.isEmpty)
    }

    @Test("Querying an empty identifier list returns nothing")
    func queryForNoIdentifiersReturnsNothing() async throws {
        let entities = try await ProfileEntityQuery().entities(for: [])

        #expect(entities.isEmpty)
    }

    @Test("Every suggested entity is identified by a profile UUID")
    func suggestedEntitiesAreIdentifiedByUUIDs() async throws {
        // Whatever the manifest holds, each id must round-trip to a `UUID`,
        // since `ThawFocusFilter.perform()` validates that before storing it.
        let entities = try await ProfileEntityQuery().suggestedEntities()

        for entity in entities {
            #expect(UUID(uuidString: entity.id) != nil, "suggested a non-UUID identifier: \(entity.id)")
        }
    }

    @Test("Suggested entities are the pool the identifier query draws from")
    func suggestedEntitiesAgreeWithTheIdentifierQuery() async throws {
        let query = ProfileEntityQuery()
        let suggested = try await query.suggestedEntities()

        let byIdentifier = try await query.entities(for: suggested.map(\.id))

        #expect(byIdentifier.map(\.id) == suggested.map(\.id))
        #expect(byIdentifier.map(\.name) == suggested.map(\.name))
    }

    @Test("The entity's default query answers the same as a freshly built one")
    func defaultQueryMatchesAFreshQuery() async throws {
        // `defaultQuery` is a `nonisolated(unsafe) static var`; this suite is
        // serialized and only reads it.
        let unknown = UUID().uuidString

        let viaDefault = try await ProfileEntity.defaultQuery.entities(for: [unknown])
        let viaFresh = try await ProfileEntityQuery().entities(for: [unknown])

        #expect(viaDefault.isEmpty)
        #expect(viaDefault.map(\.id) == viaFresh.map(\.id))
    }
}
