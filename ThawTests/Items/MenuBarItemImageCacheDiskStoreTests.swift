//
//  MenuBarItemImageCacheDiskStoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import ImageIO
import MenuBarModel
import Testing
@testable import Thaw

/// Saving and reading the image cache file, in a throwaway Caches directory.
@Suite("Image cache file", .timeLimit(.minutes(1)))
@MainActor
struct MenuBarItemImageCacheDiskStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: ScratchDefaults.name("MenuBarItemImageCacheDiskStoreTests"), directoryHint: .isDirectory)

    private let queue = DispatchQueue(label: "MenuBarItemImageCacheDiskStoreTests")

    private var store: MenuBarItemImageCacheDiskStore {
        MenuBarItemImageCacheDiskStore(cachesDirectory: directory, queue: queue)
    }

    private static func capture() -> MenuBarItemGlyphCapture {
        let context = CGContext(
            data: nil, width: 20, height: 16, bitsPerComponent: 8, bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 16))
        return MenuBarItemGlyphCapture(cgImage: context.makeImage()!, scale: 1)
    }

    /// The save runs on the store's queue, which the test owns, so draining it means the write is done.
    private func waitForFile(_ url: URL) async -> Bool {
        queue.sync {}
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func writePlist(_ root: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: url)
    }

    @Test("A saved cache reads back with its concealed flag")
    func saveAndRead() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store
        let url = try #require(store.cacheFileURL)
        #expect(url.path.hasPrefix(directory.path))
        let tag = MenuBarItemTag(namespace: .string("com.example.a"), title: "A", instanceIndex: 0)
        store.enqueueSave([tag: Self.capture()], concealedIdentifiers: [tag.tagIdentifier])
        #expect(await waitForFile(url))

        let file = try #require(store.readSaveFile())
        #expect(!file.isLegacyJSON)
        let entry = try #require(file.entries[tag.tagIdentifier])
        #expect(entry["concealed"] as? Bool == true)
        #expect(store.decodeEntry(entry, legacyJSON: false)?.scale == 1)
    }

    @Test("An empty cache writes nothing")
    func emptyCacheWritesNothing() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store
        store.enqueueSave([:])
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.readSaveFile() == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("A file from another cache version is deleted, not read")
    func otherVersionIsDeleted() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store
        let url = try #require(store.cacheFileURL)
        try writePlist(["version": -1, "timestamp": Date().timeIntervalSince1970, "images": [String: Any]()], to: url)
        #expect(store.readSaveFile() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A file from another build is deleted when the app knows its build")
    func otherBuildIsDeleted() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store
        let url = try #require(store.cacheFileURL)
        let tag = MenuBarItemTag(namespace: .string("com.example.b"), title: "B", instanceIndex: 0)
        store.enqueueSave([tag: Self.capture()])
        #expect(await waitForFile(url))
        var root = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        root["build"] = "not-this-build"
        try writePlist(root, to: url)

        let read = store.readSaveFile()
        if ImageCacheFileValidity.appBuild == nil {
            #expect(read != nil)
        } else {
            #expect(read == nil)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("A legacy JSON file is read when there is no plist, with base64 pixels")
    func legacyJSONIsRead() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store
        let legacy = try #require(store.legacyCacheFileURL)
        let pngData = try #require(Self.png(Self.capture().cgImage))
        var root: [String: Any] = try [
            "version": currentVersion(),
            "timestamp": Date().timeIntervalSince1970,
            "images": ["a:A": ["png": pngData.base64EncodedString(), "scale": 2.0]],
        ]
        root["build"] = ImageCacheFileValidity.appBuild
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: root).write(to: legacy)

        let file = try #require(store.readSaveFile())
        #expect(file.isLegacyJSON)
        let entry = try #require(file.entries["a:A"])
        let decoded = try #require(store.decodeEntry(entry, legacyJSON: true))
        #expect(decoded.scale == 2)
        #expect(decoded.cgImage.width == 20)
        #expect(store.decodeEntry(entry, legacyJSON: false) == nil)
    }

    @Test("A file older than the longest lifetime is deleted, not read")
    func expiredFileIsDeleted() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store
        let url = try #require(store.cacheFileURL)
        store.enqueueSave([MenuBarItemTag(namespace: .string("com.example.c"), title: "C", instanceIndex: 0): Self.capture()])
        #expect(await waitForFile(url))
        var root = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        root["timestamp"] = Date().timeIntervalSince1970 - MenuBarItemImageCacheDiskStore.stableCacheAgeSeconds - 60
        try writePlist(root, to: url)

        #expect(store.readSaveFile() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A file that is not a property list reads as nothing and is left alone")
    func unreadableFile() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store
        let url = try #require(store.cacheFileURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: url)
        #expect(store.readSaveFile() == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Each volatility class gets its own lifetime, and a concealed item the longest")
    func lifetimes() {
        let store = store
        #expect(store.diskCacheTTL(for: .stable) == MenuBarItemImageCacheDiskStore.stableCacheAgeSeconds)
        #expect(store.diskCacheTTL(for: .occasional) == 600)
        #expect(store.diskCacheTTL(for: .live) == 30)
        #expect(store.diskCacheTTL(for: nil) == 30)
        #expect(store.diskCacheTTL(for: .live, wasConcealed: true) == MenuBarItemImageCacheDiskStore.stableCacheAgeSeconds)
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The cache version, read from a file the store wrote rather than copied into the test.
    private func currentVersion() throws -> Int {
        let probeDirectory = directory.appending(path: "probe", directoryHint: .isDirectory)
        let queue = DispatchQueue(label: "MenuBarItemImageCacheDiskStoreTests.probe")
        let probe = MenuBarItemImageCacheDiskStore(cachesDirectory: probeDirectory, queue: queue)
        probe.enqueueSave([MenuBarItemTag(namespace: .string("com.example.p"), title: "P", instanceIndex: 0): Self.capture()])
        queue.sync {}
        let url = try #require(probe.cacheFileURL)
        let root = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        return try #require(root["version"] as? Int)
    }

    @Test("No Caches directory means no file")
    func noDirectory() {
        let store = MenuBarItemImageCacheDiskStore(cachesDirectory: nil)
        #expect(store.cacheFileURL == nil)
        #expect(store.legacyCacheFileURL == nil)
        #expect(store.readSaveFile() == nil)
    }
}
