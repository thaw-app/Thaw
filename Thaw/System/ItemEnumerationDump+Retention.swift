//
//  ItemEnumerationDump+Retention.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ItemEnumerationDump {
    nonisolated static let keptDumpCount = 5

    nonisolated static func isDump(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("item-dump-") && url.pathExtension == "json"
    }

    /// The dumps older than the newest keepCount.
    nonisolated static func dumpsToPrune(_ files: [(url: URL, created: Date)], keepCount: Int = keptDumpCount) -> [URL] {
        files
            .filter { isDump($0.url) }
            .sorted { lhs, rhs in
                lhs.created == rhs.created ? lhs.url.path > rhs.url.path : lhs.created > rhs.created
            }
            .dropFirst(max(0, keepCount))
            .map(\.url)
    }

    static func pruneDumps(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        let dated = files.map { url in
            (url: url, created: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast)
        }
        for url in dumpsToPrune(dated) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
