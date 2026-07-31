//
//  GeneralSettingsSnapshotTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``GeneralSettingsSnapshot``'s value semantics and its `Codable`
/// conformance.
///
/// The snapshot is the on-disk shape of a profile's General pane, so the icon
/// payloads, the enum-backed Ice Bar location, and the raw rehide strategy all
/// have to survive a round trip unchanged.
///
/// Reads only; nothing here touches the defaults domain, so the suite is safe
/// to run in parallel with the rest.
@Suite("General settings snapshot")
struct GeneralSettingsSnapshotTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Helper Methods

    private func makeDefaultSnapshot() -> GeneralSettingsSnapshot {
        GeneralSettingsSnapshot(
            showIceIcon: true,
            iceIcon: .defaultIceIcon,
            lastCustomIceIcon: nil,
            customIceIconIsTemplate: true,
            useIceBar: false,
            useIceBarOnlyOnNotchedDisplay: false,
            iceBarLocation: .dynamic,
            iceBarLocationOnHotkey: false,
            showOnClick: true,
            showOnDoubleClick: false,
            showOnHover: false,
            showOnScroll: false,
            autoRehide: true,
            rehideStrategyRawValue: 0,
            rehideInterval: 15
        )
    }

    private func makeCustomSnapshot() -> GeneralSettingsSnapshot {
        // Use one of the user selectable icons
        let ellipsisIcon = ControlItemImageSet.userSelectableIceIcons.first { $0.name == .ellipsis } ?? .defaultIceIcon
        let chevronIcon = ControlItemImageSet.userSelectableIceIcons.first { $0.name == .chevron } ?? .defaultIceIcon

        return GeneralSettingsSnapshot(
            showIceIcon: false,
            iceIcon: ellipsisIcon,
            lastCustomIceIcon: chevronIcon,
            customIceIconIsTemplate: false,
            useIceBar: true,
            useIceBarOnlyOnNotchedDisplay: true,
            iceBarLocation: .mousePointer,
            iceBarLocationOnHotkey: true,
            showOnClick: false,
            showOnDoubleClick: true,
            showOnHover: true,
            showOnScroll: true,
            autoRehide: false,
            rehideStrategyRawValue: 2,
            rehideInterval: 30
        )
    }

    // MARK: - Initialization Tests

    @Test("The default snapshot holds the values it was built with")
    func defaultSnapshotValues() {
        let snapshot = makeDefaultSnapshot()

        #expect(snapshot.showIceIcon)
        #expect(snapshot.lastCustomIceIcon == nil)
        #expect(snapshot.customIceIconIsTemplate)
        #expect(!snapshot.useIceBar)
        #expect(!snapshot.useIceBarOnlyOnNotchedDisplay)
        #expect(snapshot.iceBarLocation == .dynamic)
        #expect(!snapshot.iceBarLocationOnHotkey)
        #expect(snapshot.showOnClick)
        #expect(!snapshot.showOnDoubleClick)
        #expect(!snapshot.showOnHover)
        #expect(!snapshot.showOnScroll)
        #expect(snapshot.autoRehide)
        #expect(snapshot.rehideStrategyRawValue == 0)
        #expect(snapshot.rehideInterval == 15)
    }

    @Test("A custom snapshot holds the values it was built with")
    func customSnapshotValues() {
        let snapshot = makeCustomSnapshot()

        #expect(!snapshot.showIceIcon)
        #expect(snapshot.lastCustomIceIcon != nil)
        #expect(!snapshot.customIceIconIsTemplate)
        #expect(snapshot.useIceBar)
        #expect(snapshot.useIceBarOnlyOnNotchedDisplay)
        #expect(snapshot.iceBarLocation == .mousePointer)
        #expect(snapshot.iceBarLocationOnHotkey)
        #expect(!snapshot.showOnClick)
        #expect(snapshot.showOnDoubleClick)
        #expect(snapshot.showOnHover)
        #expect(snapshot.showOnScroll)
        #expect(!snapshot.autoRehide)
        #expect(snapshot.rehideStrategyRawValue == 2)
        #expect(snapshot.rehideInterval == 30)
    }

    // MARK: - Encode/Decode Tests

    @Test("The default snapshot survives a round trip")
    func encodeDecodeDefaultSnapshot() throws {
        let original = makeDefaultSnapshot()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        #expect(decoded.showIceIcon == original.showIceIcon)
        #expect(decoded.customIceIconIsTemplate == original.customIceIconIsTemplate)
        #expect(decoded.useIceBar == original.useIceBar)
        #expect(decoded.iceBarLocation == original.iceBarLocation)
        #expect(decoded.showOnClick == original.showOnClick)
        #expect(decoded.autoRehide == original.autoRehide)
        #expect(decoded.rehideStrategyRawValue == original.rehideStrategyRawValue)
        #expect(decoded.rehideInterval == original.rehideInterval)
    }

    @Test("A custom snapshot survives a round trip")
    func encodeDecodeCustomSnapshot() throws {
        let original = makeCustomSnapshot()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        #expect(decoded.showIceIcon == false)
        #expect(decoded.customIceIconIsTemplate == false)
        #expect(decoded.useIceBar == true)
        #expect(decoded.useIceBarOnlyOnNotchedDisplay == true)
        #expect(decoded.iceBarLocation == .mousePointer)
        #expect(decoded.iceBarLocationOnHotkey == true)
        #expect(decoded.showOnClick == false)
        #expect(decoded.showOnDoubleClick == true)
        #expect(decoded.showOnHover == true)
        #expect(decoded.showOnScroll == true)
        #expect(decoded.autoRehide == false)
        #expect(decoded.rehideStrategyRawValue == 2)
        #expect(decoded.rehideInterval == 30)
    }

    @Test("An absent last custom icon survives a round trip")
    func encodeDecodeWithNilLastCustomIcon() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.lastCustomIceIcon = nil

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        #expect(decoded.lastCustomIceIcon == nil)
    }

    @Test("A stored last custom icon survives a round trip")
    func encodeDecodeWithLastCustomIcon() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.lastCustomIceIcon = ControlItemImageSet.userSelectableIceIcons.first { $0.name == .chevron }

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        #expect(decoded.lastCustomIceIcon != nil)
    }

    // MARK: - IceBarLocation Tests

    @Test("Every Ice Bar location survives a round trip")
    func allIceBarLocations() throws {
        for location in IceBarLocation.allCases {
            var snapshot = makeDefaultSnapshot()
            snapshot.iceBarLocation = location

            let data = try encoder.encode(snapshot)
            let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

            #expect(decoded.iceBarLocation == location)
        }
    }

    // MARK: - RehideStrategy Tests

    @Test("Every rehide strategy raw value survives a round trip")
    func allRehideStrategyRawValues() throws {
        for strategy in RehideStrategy.allCases {
            var snapshot = makeDefaultSnapshot()
            snapshot.rehideStrategyRawValue = strategy.rawValue

            let data = try encoder.encode(snapshot)
            let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

            #expect(decoded.rehideStrategyRawValue == strategy.rawValue)
        }
    }

    // MARK: - Edge Cases

    @Test("A large rehide interval survives a round trip")
    func largeRehideInterval() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.rehideInterval = 3600 // 1 hour

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        #expect(decoded.rehideInterval == 3600)
    }

    @Test("A zero rehide interval survives a round trip")
    func zeroRehideInterval() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.rehideInterval = 0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        #expect(decoded.rehideInterval == 0)
    }

    @Test("A fractional rehide interval survives a round trip")
    func fractionalShowOnHoverDelay() throws {
        var snapshot = makeDefaultSnapshot()
        // showOnHoverDelay not in GeneralSettingsSnapshot, but rehideInterval is TimeInterval
        snapshot.rehideInterval = 15.5

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        #expect(abs(decoded.rehideInterval - 15.5) < 0.001)
    }
}
