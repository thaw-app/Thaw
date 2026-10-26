//
//  MenuBarItemImageCacheDiskStoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Saving and reading the image cache file, in a throwaway Caches directory.
@Suite("Image cache file", .timeLimit(.minutes(1)))
@MainActor
struct MenuBarItemImageCacheDiskStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: ScratchDefaults.name("MenuBarItemImageCacheDiskStoreTests"), directoryHint: .isDirectory)

    private var store: MenuBarItemImageCacheDiskStore {
        MenuBarItemImageCacheDiskStore(cachesDirectory: directory)
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

    /// The save runs on the store's background queue, which can wait long behind a busy machine
    /// and says nothing when it is done, so this checks for the file until it is there, under the
    /// suite's time limit rather than a deadline of its own.
    private func waitForFile(_ url: URL) async -> Bool {
        while !FileManager.default.fileExists(atPath: url.path) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
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

    @Test("No Caches directory means no file")
    func noDirectory() {
        let store = MenuBarItemImageCacheDiskStore(cachesDirectory: nil)
        #expect(store.cacheFileURL == nil)
        #expect(store.legacyCacheFileURL == nil)
        #expect(store.readSaveFile() == nil)
    }
}
