//
//  MaintenanceToolsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the error a failed command reports. The resets themselves kill live processes and
/// delete the user's real preference files, so a test that ran them would wreck its machine.
@Suite("Maintenance tools")
struct MaintenanceToolsTests {
    @Test("A failed command names the command and its exit status")
    func commandFailureDescribesItself() throws {
        let error = MaintenanceTools.ToolError.commandFailed("killall", 1, "No matching processes")
        let description = try #require(error.errorDescription)

        #expect(description.contains("killall"))
        #expect(description.contains("1"))
        #expect(description.contains("No matching processes"))
    }

    @Test("A failure with no output leaves the detail off rather than dangling")
    func commandFailureWithoutDetail() throws {
        let blank = MaintenanceTools.ToolError.commandFailed("tccutil", 64, "   \n  ")
        let description = try #require(blank.errorDescription)

        #expect(description.contains("tccutil"))
        #expect(description.contains("64"))
        // Whitespace-only output is treated as no output at all, so the
        // sentence ends after the status instead of trailing a colon.
        #expect(!description.contains(":"))
    }
}
