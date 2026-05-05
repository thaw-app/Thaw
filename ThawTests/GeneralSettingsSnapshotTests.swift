//
//  GeneralSettingsSnapshotTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class GeneralSettingsSnapshotTests: XCTestCase {
    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    override func tearDown() {
        encoder = nil
        decoder = nil
        super.tearDown()
    }

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

    func testDefaultSnapshotValues() {
        let snapshot = makeDefaultSnapshot()

        XCTAssertTrue(snapshot.showIceIcon)
        XCTAssertNil(snapshot.lastCustomIceIcon)
        XCTAssertTrue(snapshot.customIceIconIsTemplate)
        XCTAssertFalse(snapshot.useIceBar)
        XCTAssertFalse(snapshot.useIceBarOnlyOnNotchedDisplay)
        XCTAssertEqual(snapshot.iceBarLocation, .dynamic)
        XCTAssertFalse(snapshot.iceBarLocationOnHotkey)
        XCTAssertTrue(snapshot.showOnClick)
        XCTAssertFalse(snapshot.showOnDoubleClick)
        XCTAssertFalse(snapshot.showOnHover)
        XCTAssertFalse(snapshot.showOnScroll)
        XCTAssertTrue(snapshot.autoRehide)
        XCTAssertEqual(snapshot.rehideStrategyRawValue, 0)
        XCTAssertEqual(snapshot.rehideInterval, 15)
    }

    func testCustomSnapshotValues() {
        let snapshot = makeCustomSnapshot()

        XCTAssertFalse(snapshot.showIceIcon)
        XCTAssertNotNil(snapshot.lastCustomIceIcon)
        XCTAssertFalse(snapshot.customIceIconIsTemplate)
        XCTAssertTrue(snapshot.useIceBar)
        XCTAssertTrue(snapshot.useIceBarOnlyOnNotchedDisplay)
        XCTAssertEqual(snapshot.iceBarLocation, .mousePointer)
        XCTAssertTrue(snapshot.iceBarLocationOnHotkey)
        XCTAssertFalse(snapshot.showOnClick)
        XCTAssertTrue(snapshot.showOnDoubleClick)
        XCTAssertTrue(snapshot.showOnHover)
        XCTAssertTrue(snapshot.showOnScroll)
        XCTAssertFalse(snapshot.autoRehide)
        XCTAssertEqual(snapshot.rehideStrategyRawValue, 2)
        XCTAssertEqual(snapshot.rehideInterval, 30)
    }

    // MARK: - Encode/Decode Tests

    func testEncodeDecodeDefaultSnapshot() throws {
        let original = makeDefaultSnapshot()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded.showIceIcon, original.showIceIcon)
        XCTAssertEqual(decoded.customIceIconIsTemplate, original.customIceIconIsTemplate)
        XCTAssertEqual(decoded.useIceBar, original.useIceBar)
        XCTAssertEqual(decoded.iceBarLocation, original.iceBarLocation)
        XCTAssertEqual(decoded.showOnClick, original.showOnClick)
        XCTAssertEqual(decoded.autoRehide, original.autoRehide)
        XCTAssertEqual(decoded.rehideStrategyRawValue, original.rehideStrategyRawValue)
        XCTAssertEqual(decoded.rehideInterval, original.rehideInterval)
    }

    func testEncodeDecodeCustomSnapshot() throws {
        let original = makeCustomSnapshot()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded.showIceIcon, false)
        XCTAssertEqual(decoded.customIceIconIsTemplate, false)
        XCTAssertEqual(decoded.useIceBar, true)
        XCTAssertEqual(decoded.useIceBarOnlyOnNotchedDisplay, true)
        XCTAssertEqual(decoded.iceBarLocation, .mousePointer)
        XCTAssertEqual(decoded.iceBarLocationOnHotkey, true)
        XCTAssertEqual(decoded.showOnClick, false)
        XCTAssertEqual(decoded.showOnDoubleClick, true)
        XCTAssertEqual(decoded.showOnHover, true)
        XCTAssertEqual(decoded.showOnScroll, true)
        XCTAssertEqual(decoded.autoRehide, false)
        XCTAssertEqual(decoded.rehideStrategyRawValue, 2)
        XCTAssertEqual(decoded.rehideInterval, 30)
    }

    func testEncodeDecodeWithNilLastCustomIcon() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.lastCustomIceIcon = nil

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        XCTAssertNil(decoded.lastCustomIceIcon)
    }

    func testEncodeDecodeWithLastCustomIcon() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.lastCustomIceIcon = ControlItemImageSet.userSelectableIceIcons.first { $0.name == .chevron }

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        XCTAssertNotNil(decoded.lastCustomIceIcon)
    }

    // MARK: - IceBarLocation Tests

    func testAllIceBarLocations() throws {
        for location in IceBarLocation.allCases {
            var snapshot = makeDefaultSnapshot()
            snapshot.iceBarLocation = location

            let data = try encoder.encode(snapshot)
            let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

            XCTAssertEqual(decoded.iceBarLocation, location)
        }
    }

    // MARK: - RehideStrategy Tests

    func testAllRehideStrategyRawValues() throws {
        for strategy in RehideStrategy.allCases {
            var snapshot = makeDefaultSnapshot()
            snapshot.rehideStrategyRawValue = strategy.rawValue

            let data = try encoder.encode(snapshot)
            let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

            XCTAssertEqual(decoded.rehideStrategyRawValue, strategy.rawValue)
        }
    }

    // MARK: - Edge Cases

    func testLargeRehideInterval() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.rehideInterval = 3600 // 1 hour

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded.rehideInterval, 3600)
    }

    func testZeroRehideInterval() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.rehideInterval = 0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded.rehideInterval, 0)
    }

    func testFractionalShowOnHoverDelay() throws {
        var snapshot = makeDefaultSnapshot()
        // showOnHoverDelay not in GeneralSettingsSnapshot, but rehideInterval is TimeInterval
        snapshot.rehideInterval = 15.5

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded.rehideInterval, 15.5, accuracy: 0.001)
    }
}
