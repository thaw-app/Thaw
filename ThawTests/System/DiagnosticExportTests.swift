//
//  DiagnosticExportTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Diagnostic export")
struct DiagnosticExportTests {
    private static func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "DiagnosticExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Capture samples show only once the folder holds some")
    func samplesNeedFiles() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let samples = root.appending(path: "samples", directoryHint: .isDirectory)
        #expect(!MaintenanceTools.hasCaptureSamples(in: samples), "a missing folder has none")
        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        #expect(!MaintenanceTools.hasCaptureSamples(in: samples), "an empty folder has none")
        try Data([1]).write(to: samples.appending(path: "crop-1.png"))
        #expect(MaintenanceTools.hasCaptureSamples(in: samples))
    }

    @Test("The export holds the logs, and the capture samples when there are any")
    func stagedContents() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appending(path: "Logs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("log".utf8).write(to: logs.appending(path: "thaw.log"))
        let samples = root.appending(path: "samples", directoryHint: .isDirectory)

        let withoutSamples = try MaintenanceTools.stageDiagnostics(logs: logs, samples: samples, in: root.appending(path: "a"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: withoutSamples.path(percentEncoded: false)) == ["Logs"])

        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        try Data([1]).write(to: samples.appending(path: "crop-1.png"))
        let withSamples = try MaintenanceTools.stageDiagnostics(logs: logs, samples: samples, in: root.appending(path: "b"))
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: withSamples.path(percentEncoded: false))) == ["Logs", "Capture Samples"])
        #expect(FileManager.default.fileExists(atPath: withSamples.appending(path: "Logs/thaw.log").path(percentEncoded: false)))
    }

    @Test("Export writes a zip that unpacks to the logs")
    func exportZips() async throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appending(path: "Logs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("log".utf8).write(to: logs.appending(path: "thaw.log"))
        let zip = root.appending(path: "out.zip")

        try await MaintenanceTools.exportDiagnostics(logs: logs, samples: root.appending(path: "none"), to: zip)

        let unpacked = root.appending(path: "unpacked", directoryHint: .isDirectory)
        try await MaintenanceTools.run(path: "/usr/bin/ditto", arguments: ["-x", "-k", zip.path(percentEncoded: false), unpacked.path(percentEncoded: false)])
        #expect(FileManager.default.fileExists(atPath: unpacked.appending(path: "Thaw Diagnostics/Logs/thaw.log").path(percentEncoded: false)))
    }
}
