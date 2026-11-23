//
//  ItemEnumerationDumpRetentionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Item dump retention")
struct ItemEnumerationDumpRetentionTests {
    @Test("Only the newest dumps stay, and other files are left alone")
    func prunesOldDumps() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        func file(_ name: String, _ age: Double) -> (url: URL, created: Date) {
            (URL(fileURLWithPath: "/logs/\(name)"), base.addingTimeInterval(-age))
        }
        let files = [file("item-dump-3.json", 3), file("item-dump-1.json", 1), file("item-dump-2.json", 2), file("thaw.log", 99), file("item-dump-4.json", 4)]

        let pruned = ItemEnumerationDump.dumpsToPrune(files, keepCount: 2)
        #expect(pruned.map(\.lastPathComponent) == ["item-dump-3.json", "item-dump-4.json"])
        #expect(ItemEnumerationDump.dumpsToPrune(files).isEmpty)
    }

    @Test("Pruning a folder deletes only the dumps past the newest five")
    @MainActor
    func prunesFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ItemDumpPrune-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let dumps = (1 ... 6).map { "item-dump-\($0).json" }
        for (age, name) in (dumps + ["thaw.log"]).enumerated() {
            let url = folder.appending(path: name)
            try Data().write(to: url)
            try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_000_000 - Double(age))], ofItemAtPath: url.path(percentEncoded: false))
        }

        ItemEnumerationDump.pruneDumps(in: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted() == dumps.dropLast() + ["thaw.log"])
    }
}
