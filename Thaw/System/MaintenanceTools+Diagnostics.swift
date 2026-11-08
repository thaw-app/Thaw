//
//  MaintenanceTools+Diagnostics.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// The files Troubleshooting hands over: an item list, capture samples and the logs.
nonisolated extension MaintenanceTools {
    /// Whether folder holds any capture samples to show.
    static func hasCaptureSamples(in folder: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return !contents.isEmpty
    }

    /// Copies a fresh item list, the one thaw://dump-items writes, to destination.
    @MainActor
    static func saveItemList(to destination: URL) throws {
        guard let dump = ItemEnumerationDump.run() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try replaceItem(at: destination, withCopyOf: dump)
    }

    /// The folder an export zips: the logs, and the capture samples when there are any.
    static func stageDiagnostics(logs: URL, samples: URL, in staging: URL) throws -> URL {
        let fileManager = FileManager.default
        let root = staging.appending(path: "Thaw Diagnostics", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: root)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: logs.path(percentEncoded: false)) {
            try fileManager.copyItem(at: logs, to: root.appending(path: "Logs", directoryHint: .isDirectory))
        }
        if hasCaptureSamples(in: samples) {
            try fileManager.copyItem(at: samples, to: root.appending(path: "Capture Samples", directoryHint: .isDirectory))
        }
        return root
    }

    @concurrent
    static func exportDiagnostics(logs: URL, samples: URL, to destination: URL) async throws {
        let staging = FileManager.default.temporaryDirectory.appending(path: "ThawDiagnosticsExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        let root = try stageDiagnostics(logs: logs, samples: samples, in: staging)
        try? FileManager.default.removeItem(at: destination)
        try await run(path: "/usr/bin/ditto", arguments: zipArguments(source: root, destination: destination))
    }

    /// ditto keeps the folder name inside the zip and leaves resource forks out of it.
    static func zipArguments(source: URL, destination: URL) -> [String] {
        ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path(percentEncoded: false), destination.path(percentEncoded: false)]
    }

    private static func replaceItem(at destination: URL, withCopyOf source: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
