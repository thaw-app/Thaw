//
//  SpacingApplyModeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// `SpacingApplyMode`: whether a spacing change restarts menu bar apps or waits
/// for the next restart (#1075).
@Suite("Spacing apply mode")
struct SpacingApplyModeTests {
    @Test("Defaults to relaunching apps")
    func defaultsToRelaunchApps() {
        #expect(SpacingApplyMode.allCases == [.relaunchApps, .writeOnly])
    }

    @Test("Round-trips through its raw value")
    func rawValueRoundTrips() {
        for mode in SpacingApplyMode.allCases {
            #expect(SpacingApplyMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test("Encodes and decodes as the raw string")
    func codableRoundTrips() throws {
        for mode in SpacingApplyMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SpacingApplyMode.self, from: data)
            #expect(decoded == mode)
            // Defaults stores the raw string, so the JSON must be a plain string for
            // `Defaults.string -> init(rawValue:)` to read it back.
            let asString = try #require(String(data: data, encoding: .utf8))
            #expect(asString.contains(mode.rawValue))
        }
    }
}
