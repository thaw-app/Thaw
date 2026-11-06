//
//  PickedFileTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

struct PickedFileTests {
    @Test("A plain file URL is read although it grants no security-scoped access")
    func readsPlainFileURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PickedFileTests-\(UUID().uuidString).png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try url.contentsOfPickedFile() == bytes)
    }

    @Test("A missing file throws instead of reading as empty")
    func missingFileThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PickedFileTests-missing-\(UUID().uuidString).png")
        #expect(throws: (any Error).self) {
            try url.contentsOfPickedFile()
        }
    }
}
