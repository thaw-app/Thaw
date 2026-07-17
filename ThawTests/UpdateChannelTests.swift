//
//  UpdateChannelTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class UpdateChannelTests: XCTestCase {
    // MARK: - Raw values

    func testRawValues() {
        XCTAssertEqual(UpdateChannel.stable.rawValue, "stable")
        XCTAssertEqual(UpdateChannel.beta.rawValue, "beta")
        XCTAssertEqual(UpdateChannel.alpha.rawValue, "alpha")
    }

    func testInitFromValidRawValue() {
        XCTAssertEqual(UpdateChannel(rawValue: "stable"), .stable)
        XCTAssertEqual(UpdateChannel(rawValue: "beta"), .beta)
        XCTAssertEqual(UpdateChannel(rawValue: "alpha"), .alpha)
    }

    func testInitFromInvalidRawValueReturnsNil() {
        XCTAssertNil(UpdateChannel(rawValue: "nightly"))
        XCTAssertNil(UpdateChannel(rawValue: ""))
        XCTAssertNil(UpdateChannel(rawValue: "Stable"))
    }

    // MARK: - Identifiable

    func testIdMatchesRawValue() {
        for channel in UpdateChannel.allCases {
            XCTAssertEqual(channel.id, channel.rawValue)
        }
    }

    // MARK: - CaseIterable

    func testAllCasesContainsExactlyThreeChannels() {
        XCTAssertEqual(UpdateChannel.allCases, [.stable, .beta, .alpha])
    }

    // MARK: - allowedSparkleChannels

    func testStableAllowsNoAdditionalChannels() {
        XCTAssertEqual(UpdateChannel.stable.allowedSparkleChannels, [])
    }

    func testBetaAllowsOnlyBetaChannel() {
        XCTAssertEqual(UpdateChannel.beta.allowedSparkleChannels, ["beta"])
    }

    func testAlphaAllowsOnlyAlphaChannel() {
        XCTAssertEqual(UpdateChannel.alpha.allowedSparkleChannels, ["alpha"])
    }

    func testAllowedSparkleChannelsAreMutuallyExclusive() {
        // No channel should ever grant access to a sibling channel's items.
        for channel in UpdateChannel.allCases {
            let others = Set(UpdateChannel.allCases.filter { $0 != channel }.map(\.rawValue))
            XCTAssertTrue(channel.allowedSparkleChannels.isDisjoint(with: others))
        }
    }
}