//
//  LogRotationSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Log rotation settings", .serialized, .scratchDefaults)
struct LogRotationSettingsTests {
    private let suites = ScratchSuites(prefix: "LogRotationSettingsTests")

    @Test("Thaw 2's stored log settings carry over unchanged")
    func readsThaw2Keys() throws {
        let defaults = try #require(suites.make())
        defaults.set(25, forKey: "DiagnosticLogMaxSizeMB")
        defaults.set(14, forKey: "DiagnosticLogRetentionDays")
        defaults.set("hourly", forKey: "DiagnosticLogRotationInterval")

        let policy = ToolsSettings.persistedRotationPolicy(in: defaults)
        #expect(policy.maxFileSizeBytes == 25 * 1024 * 1024)
        #expect(policy.retentionDays == 14)
        #expect(policy.rotationInterval == 3600)
    }

    @Test("With nothing stored, Thaw 2's defaults apply: 10 MB, 2 days, no timed rotation")
    func defaults() throws {
        let policy = try ToolsSettings.persistedRotationPolicy(in: #require(suites.make()))
        #expect(policy.maxFileSizeBytes == 10 * 1024 * 1024)
        #expect(policy.retentionDays == 2)
        #expect(policy.rotationInterval == 0)
        #expect(policy.maxFileCount == 50)
    }

    @Test("Unreadable or out-of-range stored values fall back or are held in range")
    func badValues() throws {
        let defaults = try #require(suites.make())
        defaults.set("weekly", forKey: "DiagnosticLogRotationInterval")
        defaults.set(-3, forKey: "DiagnosticLogRetentionDays")
        defaults.set(Int.max, forKey: "DiagnosticLogMaxSizeMB")

        let policy = ToolsSettings.persistedRotationPolicy(in: defaults)
        #expect(policy.rotationInterval == 0, "an unknown interval reads as off")
        #expect(policy.retentionDays == 1)
        #expect(policy.maxFileSizeBytes == 1_000_000 * 1024 * 1024)
    }

    @Test("Loading the stored settings hands the logger one policy, never one that is half defaults")
    func loadSendsOnePolicy() {
        Defaults.store.set(25, forKey: "DiagnosticLogMaxSizeMB")
        Defaults.store.set(30, forKey: "DiagnosticLogRetentionDays")
        let settings = ToolsSettings()
        var sent = [DiagnosticLogger.RotationPolicy]()
        settings.sendRotationPolicy = { sent.append($0) }

        settings.loadInitialState()

        #expect(sent.map(\.retentionDays) == [30], "a policy with the default 2 days would delete logs kept for 30")
        #expect(sent.first?.maxFileSizeBytes == 25 * 1024 * 1024)
    }

    @Test("Changing a setting stores it under Thaw 2's key and hands the logger the new policy")
    func changesReachTheLogger() {
        let settings = ToolsSettings()
        settings.diagnosticLogRetentionDays = 9
        settings.diagnosticLogRotationInterval = .daily
        #expect(Defaults.store.integer(forKey: "DiagnosticLogRetentionDays") == 9)
        #expect(Defaults.store.string(forKey: "DiagnosticLogRotationInterval") == "daily")
        #expect(DiagnosticLogger.shared.rotationPolicy?.retentionDays == 9)
        #expect(DiagnosticLogger.shared.rotationPolicy?.rotationInterval == 86400)
    }
}
