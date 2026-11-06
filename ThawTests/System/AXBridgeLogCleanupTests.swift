//
//  AXBridgeLogCleanupTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Retired AX bridge logs")
struct AXBridgeLogCleanupTests {
    @Test("Old AX bridge logs are removed and other logs are kept")
    func removesOnlyAXBridgeLogs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-ax-bridge-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = ["ax-bridge-ABC-0.txt", "ax-bridge-ABC-1.txt", "thaw_2026-10-04_10-00-00.log", "notes.txt"]
        for name in names {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }

        MigrationManager().removeAXBridgeLogs(in: directory)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(remaining == ["notes.txt", "thaw_2026-10-04_10-00-00.log"])
    }

    @Test("A missing log folder is not an error")
    func toleratesAMissingFolder() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-ax-bridge-missing-\(UUID().uuidString)", isDirectory: true)
        MigrationManager().removeAXBridgeLogs(in: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
