//
//  MenuBarItemImageCacheDiskSaveTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import os.lock
import Testing
@testable import Thaw

/// Re-stamping, skipping and failing saves, with the store's clock and queue in the test's hands.
@Suite("Image cache saves", .timeLimit(.minutes(1)))
@MainActor
struct MenuBarItemImageCacheDiskSaveTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: ScratchDefaults.name("MenuBarItemImageCacheDiskSaveTests"), directoryHint: .isDirectory)
    private let queue = DispatchQueue(label: "MenuBarItemImageCacheDiskSaveTests")
    /// Whole seconds near now, so a file the store stamps is young enough for readSaveFile() to keep.
    private static let base = Date().timeIntervalSince1970.rounded(.down)
    private let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: base))
    private let tag = MenuBarItemTag(namespace: .string("com.example.save"), title: "Save", instanceIndex: 0)

    private func makeStore(cachesDirectory: URL? = nil) -> MenuBarItemImageCacheDiskStore {
        let clock = clock
        return MenuBarItemImageCacheDiskStore(
            cachesDirectory: cachesDirectory ?? directory,
            now: { clock.withLock { $0 } },
            queue: queue
        )
    }

    private func advance(by seconds: TimeInterval) {
        clock.withLock { $0 += seconds }
    }

    private static func capture() -> MenuBarItemGlyphCapture {
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return MenuBarItemGlyphCapture(cgImage: context.makeImage()!, scale: 2)
    }

    /// Saves and waits for the store's serial queue to finish the drain.
    private func save(_ store: MenuBarItemImageCacheDiskStore, _ capture: MenuBarItemGlyphCapture, concealed: Set<String> = []) {
        store.enqueueSave([tag: capture], concealedIdentifiers: concealed)
        queue.sync {}
    }

    private func root(at url: URL) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    }

    private func timestamp(at url: URL) throws -> TimeInterval? {
        try root(at: url)["timestamp"] as? TimeInterval
    }

    @Test("A save stamps the file with the store's clock")
    func saveUsesClock() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore()
        let url = try #require(store.cacheFileURL)
        save(store, Self.capture())
        #expect(try timestamp(at: url) == Self.base)
    }

    @Test("An unchanged cache saved again soon after is not written")
    func unchangedSoonIsSkipped() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore()
        let url = try #require(store.cacheFileURL)
        let capture = Self.capture()
        save(store, capture)
        try FileManager.default.removeItem(at: url)

        advance(by: 5)
        save(store, capture)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("An unchanged cache past the refresh interval only gets a new timestamp")
    func unchangedLaterIsRestamped() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore()
        let url = try #require(store.cacheFileURL)
        let capture = Self.capture()
        save(store, capture)
        // A marker a full rewrite would drop shows that only the timestamp was replaced.
        var marked = try root(at: url)
        marked["marker"] = "kept"
        try PropertyListSerialization.data(fromPropertyList: marked, format: .binary, options: 0).write(to: url)

        advance(by: 20)
        save(store, capture)
        let restamped = try root(at: url)
        #expect(restamped["timestamp"] as? TimeInterval == Self.base + 20)
        #expect(restamped["marker"] as? String == "kept")
    }

    @Test("A different concealed set counts as a change and rewrites the file")
    func concealedChangeRewrites() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore()
        let url = try #require(store.cacheFileURL)
        let capture = Self.capture()
        save(store, capture)
        try FileManager.default.removeItem(at: url)

        advance(by: 1)
        save(store, capture, concealed: [tag.tagIdentifier])
        let entry = try #require(store.readSaveFile()?.entries[tag.tagIdentifier])
        #expect(entry["concealed"] as? Bool == true)
        #expect(try timestamp(at: url) == Self.base + 1)
    }

    @Test("A re-stamp that finds the file gone writes it out in full")
    func missingFileIsRewritten() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore()
        let url = try #require(store.cacheFileURL)
        let capture = Self.capture()
        save(store, capture)
        try FileManager.default.removeItem(at: url)

        advance(by: 20)
        save(store, capture)
        let file = try #require(store.readSaveFile())
        #expect(try store.decodeEntry(#require(file.entries[tag.tagIdentifier]), legacyJSON: false)?.scale == 2)
        #expect(try timestamp(at: url) == Self.base + 20)
    }

    @Test("A re-stamp that finds another version's file writes the current one")
    func otherVersionIsRewritten() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore()
        let url = try #require(store.cacheFileURL)
        let capture = Self.capture()
        save(store, capture)
        var stale = try root(at: url)
        let currentVersion = try #require(stale["version"] as? Int)
        stale["version"] = -1
        try PropertyListSerialization.data(fromPropertyList: stale, format: .binary, options: 0).write(to: url)

        advance(by: 20)
        save(store, capture)
        #expect(try root(at: url)["version"] as? Int == currentVersion)
    }

    @Test("A re-stamp that cannot write falls back to a full write, which also fails, and keeps nothing")
    func unwritableFileIsNotRecorded() throws {
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = makeStore()
        let url = try #require(store.cacheFileURL)
        let capture = Self.capture()
        save(store, capture)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)

        advance(by: 20)
        save(store, capture)
        #expect(try timestamp(at: url) == Self.base)

        // The failure was not recorded as a write, so a request a second later still reaches the file.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        advance(by: 1)
        save(store, capture)
        #expect(try timestamp(at: url) == Self.base + 21)
    }

    @Test("A save whose folder cannot be made leaves no file")
    func uncreatableFolder() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "blocker", directoryHint: .notDirectory)
        try Data("x".utf8).write(to: blocker)
        let store = makeStore(cachesDirectory: blocker)
        let url = try #require(store.cacheFileURL)
        save(store, Self.capture())
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A save replaces the legacy JSON file")
    func saveDeletesLegacyFile() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore()
        let legacy = try #require(store.legacyCacheFileURL)
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy)
        save(store, Self.capture())
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }
}
