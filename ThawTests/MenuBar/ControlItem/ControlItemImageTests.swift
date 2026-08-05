//
//  ControlItemImageTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``ControlItemImage``'s stored form and value semantics.
///
/// The enum is what a control item icon looks like on disk: it is embedded in
/// every `ControlItemImageSet`, which in turn is written to the `iceIcon`
/// default and into every exported profile. The four cases therefore have a
/// wire format that outlives the build that wrote it, and the synthesized
/// `Codable` conformance keys off the case names — renaming `.catalog` would
/// leave existing users with an undecodable icon and a blank menu bar item, so
/// the encoded shape is pinned here rather than assumed.
///
/// `nsImage(for:)` is deliberately out of scope: it needs a live `AppState`,
/// which the suite has no way to build without touching the user's real
/// profiles directory. The same limitation is noted in `ProfileManagerCRUDTests`
/// and `DisplaySettingsManagerMutationTests`.
@Suite("Control item image")
struct ControlItemImageTests {
    private var encoder: JSONEncoder {
        JSONEncoder()
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }

    /// Every case, so the round-trip tests cannot silently skip one.
    private static let allCases: [ControlItemImage] = [
        .builtin(.chevronLarge),
        .builtin(.chevronSmall),
        .symbol("circle.fill"),
        .catalog("IceCube"),
        .data(Data([0x00, 0x01, 0x02])),
    ]

    // MARK: - Codable

    @Test("Every case survives a round trip", arguments: ControlItemImageTests.allCases)
    func caseSurvivesARoundTrip(_ image: ControlItemImage) throws {
        let data = try encoder.encode(image)
        let decoded = try decoder.decode(ControlItemImage.self, from: data)

        #expect(decoded == image)
    }

    /// The case names are the stored discriminator. Renaming one silently
    /// orphans every icon a previous build wrote.
    @Test("The case names are the stored discriminators")
    func caseNamesAreTheStoredDiscriminators() throws {
        let payloads = try Self.allCases.map { image in
            let object = try JSONSerialization.jsonObject(
                with: encoder.encode(image)
            ) as? [String: Any]
            return object?.keys.first
        }

        #expect(payloads == ["builtin", "builtin", "symbol", "catalog", "data"])
    }

    @Test("The builtin case names are the stored discriminators")
    func builtinCaseNamesAreTheStoredDiscriminators() throws {
        let names: [ControlItemImage.ImageBuiltinName] = [.chevronLarge, .chevronSmall]

        let keys = try names.map { name in
            let object = try JSONSerialization.jsonObject(
                with: encoder.encode(name)
            ) as? [String: Any]
            return object?.keys.first
        }

        #expect(keys == ["chevronLarge", "chevronSmall"])
    }

    @Test("A symbol name round-trips verbatim")
    func symbolNameRoundTripsVerbatim() throws {
        let image = ControlItemImage.symbol("chevron.left.chevron.right")

        let decoded = try decoder.decode(
            ControlItemImage.self,
            from: encoder.encode(image)
        )

        guard case let .symbol(name) = decoded else {
            Issue.record("expected a symbol case, got \(decoded)")
            return
        }
        #expect(name == "chevron.left.chevron.right")
    }

    @Test("Image data round-trips byte for byte")
    func imageDataRoundTripsByteForByte() throws {
        let payload = Data((0 ..< 256).map { UInt8($0) })
        let image = ControlItemImage.data(payload)

        let decoded = try decoder.decode(
            ControlItemImage.self,
            from: encoder.encode(image)
        )

        guard case let .data(decodedPayload) = decoded else {
            Issue.record("expected a data case, got \(decoded)")
            return
        }
        #expect(decodedPayload == payload)
    }

    @Test("A builtin name round-trips inside its enclosing case", arguments: [
        ControlItemImage.ImageBuiltinName.chevronLarge,
        ControlItemImage.ImageBuiltinName.chevronSmall,
    ])
    func builtinNameRoundTrips(_ name: ControlItemImage.ImageBuiltinName) throws {
        let decoded = try decoder.decode(
            ControlItemImage.self,
            from: encoder.encode(ControlItemImage.builtin(name))
        )

        guard case let .builtin(decodedName) = decoded else {
            Issue.record("expected a builtin case, got \(decoded)")
            return
        }
        #expect(decodedName == name)
    }

    @Test("An unknown case is rejected rather than silently dropped")
    func unknownCaseIsRejected() {
        let payload = Data(#"{"vector":{"_0":"circle"}}"#.utf8)

        #expect(throws: DecodingError.self) {
            try decoder.decode(ControlItemImage.self, from: payload)
        }
    }

    @Test("An unknown builtin name is rejected")
    func unknownBuiltinNameIsRejected() {
        let payload = Data(#"{"builtin":{"_0":{"chevronHuge":{}}}}"#.utf8)

        #expect(throws: DecodingError.self) {
            try decoder.decode(ControlItemImage.self, from: payload)
        }
    }

    // MARK: - Value Semantics

    @Test("Two images with the same case and payload are equal")
    func matchingImagesAreEqual() {
        #expect(ControlItemImage.symbol("star") == ControlItemImage.symbol("star"))
        #expect(ControlItemImage.builtin(.chevronSmall) == ControlItemImage.builtin(.chevronSmall))
        #expect(ControlItemImage.data(Data([1, 2])) == ControlItemImage.data(Data([1, 2])))
    }

    @Test("A differing payload makes two images unequal")
    func differingPayloadsAreUnequal() {
        #expect(ControlItemImage.symbol("star") != ControlItemImage.symbol("star.fill"))
        #expect(ControlItemImage.builtin(.chevronSmall) != ControlItemImage.builtin(.chevronLarge))
        #expect(ControlItemImage.data(Data([1])) != ControlItemImage.data(Data([2])))
    }

    /// The same string in two different cases must not collide: the icon picker
    /// stores catalog and symbol names side by side.
    @Test("The same name in different cases stays distinct")
    func sameNameInDifferentCasesStaysDistinct() {
        #expect(ControlItemImage.symbol("IceCube") != ControlItemImage.catalog("IceCube"))
    }

    @Test("Equal images hash alike")
    func equalImagesHashAlike() {
        let images = Set(Self.allCases + Self.allCases)

        #expect(images.count == Self.allCases.count)
    }

    @Test("Distinct images occupy distinct set slots")
    func distinctImagesOccupyDistinctSlots() {
        #expect(Set(Self.allCases).count == 5)
    }
}
