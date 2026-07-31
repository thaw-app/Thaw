//
//  NewItemsPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

// MARK: - NewItemsPlacement.Relation Tests

/// Pins the wire format of `MenuBarItemManager.NewItemsPlacement.Relation`.
///
/// The relation is persisted inside `newItemsPlacementData`, so its raw
/// values are a stored format: renaming a case is safe, but changing the
/// raw value silently discards an existing user's placement preference and
/// falls back to the section default. These cases fail loudly if that ever
/// happens.
///
/// Reads only; nothing here touches the defaults domain, so the suite is
/// safe to run in parallel with the rest.
@Suite("New items placement relation")
struct NewItemsPlacementRelationTests {
    // MARK: - Raw Values

    @Test("leftOfAnchor keeps its raw value")
    func leftOfAnchorRawValue() {
        let relation = MenuBarItemManager.NewItemsPlacement.Relation.leftOfAnchor
        #expect(relation.rawValue == "leftOfAnchor")
    }

    @Test("rightOfAnchor keeps its raw value")
    func rightOfAnchorRawValue() {
        let relation = MenuBarItemManager.NewItemsPlacement.Relation.rightOfAnchor
        #expect(relation.rawValue == "rightOfAnchor")
    }

    @Test("sectionDefault keeps its raw value")
    func sectionDefaultRawValue() {
        let relation = MenuBarItemManager.NewItemsPlacement.Relation.sectionDefault
        #expect(relation.rawValue == "sectionDefault")
    }

    // MARK: - Init from Raw Value

    @Test("leftOfAnchor round-trips through its raw value")
    func initFromLeftOfAnchorRawValue() {
        let relation = MenuBarItemManager.NewItemsPlacement.Relation(rawValue: "leftOfAnchor")
        #expect(relation == .leftOfAnchor)
    }

    @Test("rightOfAnchor round-trips through its raw value")
    func initFromRightOfAnchorRawValue() {
        let relation = MenuBarItemManager.NewItemsPlacement.Relation(rawValue: "rightOfAnchor")
        #expect(relation == .rightOfAnchor)
    }

    @Test("sectionDefault round-trips through its raw value")
    func initFromSectionDefaultRawValue() {
        let relation = MenuBarItemManager.NewItemsPlacement.Relation(rawValue: "sectionDefault")
        #expect(relation == .sectionDefault)
    }

    @Test("An unrecognized raw value produces nil")
    func initFromInvalidRawValue() {
        let relation = MenuBarItemManager.NewItemsPlacement.Relation(rawValue: "invalid")
        #expect(relation == nil)
    }

    // MARK: - Codable

    @Test("A relation encodes as its bare raw value")
    func relationEncode() throws {
        let relation = MenuBarItemManager.NewItemsPlacement.Relation.leftOfAnchor
        let encoder = JSONEncoder()
        let data = try encoder.encode(relation)
        let json = String(data: data, encoding: .utf8)

        #expect(json == "\"leftOfAnchor\"")
    }

    @Test("A relation decodes from its bare raw value")
    func relationDecode() throws {
        let json = "\"rightOfAnchor\""
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let relation = try decoder.decode(MenuBarItemManager.NewItemsPlacement.Relation.self, from: data)

        #expect(relation == .rightOfAnchor)
    }

    @Test("Decoding an unrecognized relation throws")
    func relationDecodeInvalid() throws {
        let json = "\"invalidValue\""
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()

        #expect(throws: (any Error).self) {
            try decoder.decode(MenuBarItemManager.NewItemsPlacement.Relation.self, from: data)
        }
    }

    // MARK: - Equality

    @Test("Relations compare equal only to themselves")
    func relationEquality() {
        #expect(
            MenuBarItemManager.NewItemsPlacement.Relation.leftOfAnchor
                == MenuBarItemManager.NewItemsPlacement.Relation.leftOfAnchor
        )
        #expect(
            MenuBarItemManager.NewItemsPlacement.Relation.leftOfAnchor
                != MenuBarItemManager.NewItemsPlacement.Relation.rightOfAnchor
        )
    }
}

// MARK: - NewItemsPlacement Tests

/// Covers `MenuBarItemManager.NewItemsPlacement` construction, equality, and
/// its `Codable` conformance.
///
/// The placement is persisted as JSON under `newItemsPlacementData` and
/// compared against the stored value to decide whether a newly detected menu
/// bar item needs to be moved. That makes both the encoded shape and the
/// synthesized `Equatable` conformance load-bearing.
///
/// Reads only; nothing here touches the defaults domain, so the suite is
/// safe to run in parallel with the rest.
@Suite("New items placement")
struct NewItemsPlacementTests {
    // MARK: - Initialization

    @Test("A section-default placement stores its section and no anchor")
    func basicInit() {
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        #expect(placement.sectionKey == "hidden")
        #expect(placement.anchorIdentifier == nil)
        #expect(placement.relation == .sectionDefault)
    }

    @Test("A left-of-anchor placement stores its anchor")
    func initWithAnchor() {
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "com.example.app:Item",
            relation: .leftOfAnchor
        )

        #expect(placement.sectionKey == "visible")
        #expect(placement.anchorIdentifier == "com.example.app:Item")
        #expect(placement.relation == .leftOfAnchor)
    }

    @Test("A right-of-anchor placement stores its anchor")
    func initWithRightOfAnchor() {
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "alwaysHidden",
            anchorIdentifier: "com.other.app:OtherItem",
            relation: .rightOfAnchor
        )

        #expect(placement.sectionKey == "alwaysHidden")
        #expect(placement.anchorIdentifier == "com.other.app:OtherItem")
        #expect(placement.relation == .rightOfAnchor)
    }

    // MARK: - Default Value

    @Test("The default value carries no anchor and the section default relation")
    func defaultValueShape() {
        let defaultValue = MenuBarItemManager.NewItemsPlacement.defaultValue

        #expect(defaultValue.anchorIdentifier == nil)
        #expect(defaultValue.relation == .sectionDefault)
    }

    @Test("The default value's section matches the defaults domain")
    func defaultValueSectionKey() {
        let defaultValue = MenuBarItemManager.NewItemsPlacement.defaultValue

        // Default section should be "hidden" per Defaults.DefaultValue.newItemsSection
        #expect(defaultValue.sectionKey == Defaults.DefaultValue.newItemsSection)
    }

    // MARK: - Equality

    @Test("Identical placements compare equal")
    func equalityIdentical() {
        let placement1 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.app:Item",
            relation: .leftOfAnchor
        )
        let placement2 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.app:Item",
            relation: .leftOfAnchor
        )

        #expect(placement1 == placement2)
    }

    @Test("A different section breaks equality")
    func equalityDifferentSection() {
        let placement1 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
        let placement2 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        #expect(placement1 != placement2)
    }

    @Test("A different anchor breaks equality")
    func equalityDifferentAnchor() {
        let placement1 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "anchor1",
            relation: .leftOfAnchor
        )
        let placement2 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "anchor2",
            relation: .leftOfAnchor
        )

        #expect(placement1 != placement2)
    }

    @Test("A different relation breaks equality")
    func equalityDifferentRelation() {
        let placement1 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "anchor",
            relation: .leftOfAnchor
        )
        let placement2 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "anchor",
            relation: .rightOfAnchor
        )

        #expect(placement1 != placement2)
    }

    @Test("A nil anchor never equals a set anchor")
    func equalityNilVsNonNilAnchor() {
        let placement1 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
        let placement2 = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.app:Item",
            relation: .sectionDefault
        )

        #expect(placement1 != placement2)
    }

    // MARK: - Codable

    @Test("An anchorless placement encodes its section and relation")
    func encodeBasic() throws {
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(placement)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"sectionKey\":\"hidden\""))
        #expect(json.contains("\"relation\":\"sectionDefault\""))
    }

    @Test("An anchored placement encodes its anchor and relation")
    func encodeWithAnchor() throws {
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "com.example.app:StatusItem",
            relation: .leftOfAnchor
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(placement)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"anchorIdentifier\":\"com.example.app:StatusItem\""))
        #expect(json.contains("\"relation\":\"leftOfAnchor\""))
    }

    @Test("An explicit null anchor decodes as nil")
    func decodeBasic() throws {
        let json = """
        {
            "sectionKey": "hidden",
            "anchorIdentifier": null,
            "relation": "sectionDefault"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()

        let placement = try decoder.decode(MenuBarItemManager.NewItemsPlacement.self, from: data)

        #expect(placement.sectionKey == "hidden")
        #expect(placement.anchorIdentifier == nil)
        #expect(placement.relation == .sectionDefault)
    }

    @Test("An anchored placement decodes every field")
    func decodeWithAnchor() throws {
        let json = """
        {
            "sectionKey": "alwaysHidden",
            "anchorIdentifier": "com.test.app:Item",
            "relation": "rightOfAnchor"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()

        let placement = try decoder.decode(MenuBarItemManager.NewItemsPlacement.self, from: data)

        #expect(placement.sectionKey == "alwaysHidden")
        #expect(placement.anchorIdentifier == "com.test.app:Item")
        #expect(placement.relation == .rightOfAnchor)
    }

    @Test("Decoding an unrecognized relation throws")
    func decodeInvalidRelation() throws {
        let json = """
        {
            "sectionKey": "hidden",
            "anchorIdentifier": null,
            "relation": "invalidRelation"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()

        #expect(throws: (any Error).self) {
            try decoder.decode(MenuBarItemManager.NewItemsPlacement.self, from: data)
        }
    }

    @Test("A missing anchor key decodes as nil")
    func decodeMissingOptionalField() throws {
        let json = """
        {
            "sectionKey": "hidden",
            "relation": "sectionDefault"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()

        // anchorIdentifier is Optional<String>, so missing key decodes as nil
        let placement = try decoder.decode(MenuBarItemManager.NewItemsPlacement.self, from: data)

        #expect(placement.sectionKey == "hidden")
        #expect(placement.anchorIdentifier == nil)
        #expect(placement.relation == .sectionDefault)
    }

    // MARK: - Round Trip

    @Test("An anchorless placement survives a round trip")
    func roundTripBasic() throws {
        let original = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarItemManager.NewItemsPlacement.self, from: data)

        #expect(original == decoded)
    }

    @Test("An anchor with spaces and dots survives a round trip")
    func roundTripWithAnchor() throws {
        let original = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.complexapp.identifier:Very Long Item Name With Spaces",
            relation: .leftOfAnchor
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarItemManager.NewItemsPlacement.self, from: data)

        #expect(original == decoded)
    }

    @Test("The default value survives a round trip")
    func roundTripDefaultValue() throws {
        let original = MenuBarItemManager.NewItemsPlacement.defaultValue

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarItemManager.NewItemsPlacement.self, from: data)

        #expect(original == decoded)
    }

    // MARK: - All Relations

    @Test("Every relation can be carried by a placement")
    func allRelationsCovered() {
        // Ensure all three relations can be used in placements
        let leftPlacement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "test",
            anchorIdentifier: "anchor",
            relation: .leftOfAnchor
        )
        let rightPlacement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "test",
            anchorIdentifier: "anchor",
            relation: .rightOfAnchor
        )
        let defaultPlacement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "test",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        #expect(leftPlacement.relation == .leftOfAnchor)
        #expect(rightPlacement.relation == .rightOfAnchor)
        #expect(defaultPlacement.relation == .sectionDefault)
    }
}
