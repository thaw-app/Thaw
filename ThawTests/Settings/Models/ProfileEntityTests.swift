//
//  ProfileEntityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppIntents
import Foundation
import Testing
@testable import Thaw

@Suite("Profile entity")
struct ProfileEntityTests {
    // MARK: - Initialization

    @Test("An entity keeps the identifier and name it was built with")
    func initialization() {
        let entity = ProfileEntity(id: "test-id", name: "Test Profile")

        #expect(entity.id == "test-id")
        #expect(entity.name == "Test Profile")
    }

    // MARK: - Type Display Representation

    /// Pins the name the system shows when the user picks a Thaw profile in a
    /// Focus Filter. Both sides resolve through the same catalog, so the case
    /// holds in every localization.
    @Test("The entity type is presented to the system as a menu bar profile")
    func typeDisplayRepresentation() {
        let representation = ProfileEntity.typeDisplayRepresentation

        #expect(String(localized: representation.name) == String(localized: "Menu Bar Profile"))
    }

    // MARK: - Display Representation

    @Test("An entity's display representation is titled with the profile name")
    func displayRepresentationContainsName() {
        let entity = ProfileEntity(id: "123", name: "My Profile")
        let representation = entity.displayRepresentation

        #expect(String(localized: representation.title) == "My Profile")
    }
}
