//
//  UpdatesManagerUpdateChannelTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
@testable import Thaw
import XCTest

/// Tests for ``UpdatesManager/updateChannel``.
///
/// `UpdatesManager` reads and writes `UserDefaults.standard` directly (there
/// is no injectable defaults store), so these tests snapshot the two keys it
/// touches — `"UpdateChannel"` and the legacy `"AllowsBetaUpdates"` boolean —
/// before each test and restore them afterward to avoid leaking state
/// between tests or polluting a developer's real defaults.
@MainActor
final class UpdatesManagerUpdateChannelTests: XCTestCase {
    private let channelKey = "UpdateChannel"
    private let legacyKey = "AllowsBetaUpdates"

    private var originalChannelValue: Any?
    private var originalLegacyValue: Any?
    private var manager: UpdatesManager!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        originalChannelValue = UserDefaults.standard.object(forKey: channelKey)
        originalLegacyValue = UserDefaults.standard.object(forKey: legacyKey)
        UserDefaults.standard.removeObject(forKey: channelKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        manager = UpdatesManager()
    }

    override func tearDown() {
        cancellables.removeAll()
        manager = nil
        UserDefaults.standard.removeObject(forKey: channelKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        if let originalChannelValue {
            UserDefaults.standard.set(originalChannelValue, forKey: channelKey)
        }
        if let originalLegacyValue {
            UserDefaults.standard.set(originalLegacyValue, forKey: legacyKey)
        }
        super.tearDown()
    }

    // MARK: - Getter: default fallback logic

    func testDefaultsToStableOrAlphaDependingOnOSAvailabilityWhenNoKeysAreSet() {
        let expected: UpdateChannel = if #available(macOS 27, *) {
            .alpha
        } else {
            .stable
        }
        XCTAssertEqual(manager.updateChannel, expected)
    }

    func testLegacyBetaFlagMapsToBetaChannelWhenNewKeyIsAbsent() {
        UserDefaults.standard.set(true, forKey: legacyKey)

        XCTAssertEqual(manager.updateChannel, .beta)
    }

    func testLegacyFlagFalseFallsThroughToOSAvailabilityDefault() {
        UserDefaults.standard.set(false, forKey: legacyKey)

        let expected: UpdateChannel = if #available(macOS 27, *) {
            .alpha
        } else {
            .stable
        }
        XCTAssertEqual(manager.updateChannel, expected)
    }

    func testNewKeyTakesPrecedenceOverLegacyFlag() {
        UserDefaults.standard.set(true, forKey: legacyKey)
        UserDefaults.standard.set(UpdateChannel.stable.rawValue, forKey: channelKey)

        XCTAssertEqual(manager.updateChannel, .stable)
    }

    func testNewKeySetToAlphaIsHonoredRegardlessOfLegacyFlag() {
        UserDefaults.standard.set(false, forKey: legacyKey)
        UserDefaults.standard.set(UpdateChannel.alpha.rawValue, forKey: channelKey)

        XCTAssertEqual(manager.updateChannel, .alpha)
    }

    func testInvalidStoredRawValueIgnoresNewKeyAndFallsBackToLegacyLogic() {
        UserDefaults.standard.set("not-a-real-channel", forKey: channelKey)
        UserDefaults.standard.set(true, forKey: legacyKey)

        XCTAssertEqual(manager.updateChannel, .beta)
    }

    func testEmptyStringStoredRawValueFallsBackToLegacyLogic() {
        UserDefaults.standard.set("", forKey: channelKey)

        let expected: UpdateChannel = if #available(macOS 27, *) {
            .alpha
        } else {
            .stable
        }
        XCTAssertEqual(manager.updateChannel, expected)
    }

    // MARK: - Setter: persistence

    func testSettingStablePersistsRawValueAndClearsLegacyFlag() {
        manager.updateChannel = .stable

        XCTAssertEqual(UserDefaults.standard.string(forKey: channelKey), "stable")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: legacyKey))
    }

    func testSettingBetaPersistsRawValueAndSetsLegacyFlag() {
        manager.updateChannel = .beta

        XCTAssertEqual(UserDefaults.standard.string(forKey: channelKey), "beta")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: legacyKey))
    }

    func testSettingAlphaPersistsRawValueAndSetsLegacyFlag() {
        manager.updateChannel = .alpha

        XCTAssertEqual(UserDefaults.standard.string(forKey: channelKey), "alpha")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: legacyKey))
    }

    func testSetThenGetRoundTripsForEveryChannel() {
        for channel in UpdateChannel.allCases {
            manager.updateChannel = channel
            XCTAssertEqual(manager.updateChannel, channel)
        }
    }

    func testSwitchingChannelsOverwritesThePreviousSelection() {
        manager.updateChannel = .alpha
        XCTAssertEqual(manager.updateChannel, .alpha)

        manager.updateChannel = .stable
        XCTAssertEqual(manager.updateChannel, .stable)
        // The legacy flag should have been cleared along with the switch.
        XCTAssertFalse(UserDefaults.standard.bool(forKey: legacyKey))
    }

    // MARK: - Setter: change notification

    func testSettingChannelSendsObjectWillChange() {
        let expectation = expectation(description: "objectWillChange fires when the channel changes")
        manager.objectWillChange
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        manager.updateChannel = .beta

        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Delegate forwarding

    func testAllowedSparkleChannelsMatchesTheSelectedChannel() {
        // `allowedChannels(for:)` simply forwards to
        // `updateChannel.allowedSparkleChannels`; verify that relationship
        // holds for every channel without needing to construct a live
        // `SPUUpdater`.
        for channel in UpdateChannel.allCases {
            manager.updateChannel = channel
            XCTAssertEqual(manager.updateChannel.allowedSparkleChannels, channel.allowedSparkleChannels)
        }
    }
}