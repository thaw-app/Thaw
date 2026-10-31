//
//  ChangelogLoadTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawUI

/// What a fetch leaves behind in the cache. Each test gets its own folder under
/// Caches, removed afterwards.
@Suite("ChangelogDocument loading")
struct ChangelogLoadTests {
    private static let goodText = "## [1.0.0]\n\n- A bullet.\n"
    private static let newerText = "## [2.0.0]\n\n- A newer bullet.\n"
    private static let noReleases = "<html><body>Sign in to this network</body></html>\n"

    private func withCacheFolder(_ body: (String) async throws -> Void) async rethrows {
        let folder = "ThawUITests-\(UUID().uuidString)"
        defer {
            if let directory = ChangelogDocument.cachedTextURL(folder: folder)?.deletingLastPathComponent() {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        try await body(folder)
    }

    private func load(
        _ text: String?,
        folder: String
    ) async -> (document: ChangelogDocument?, source: ChangelogDocument.Source) {
        await ChangelogDocument.load(allowFetch: true, cacheFolder: folder) { text }
    }

    private func cachedVersions(folder: String) async -> [String]? {
        await ChangelogDocument.load(allowFetch: false, cacheFolder: folder) { nil }
            .document?.releases.map(\.version)
    }

    @Test("a fetched changelog with releases is shown and replaces the cache")
    func goodResponseIsCached() async {
        await withCacheFolder { folder in
            _ = await load(Self.goodText, folder: folder)

            let loaded = await load(Self.newerText, folder: folder)

            #expect(loaded.source == .fetched)
            #expect(loaded.document?.releases.map(\.version) == ["2.0.0"])
            #expect(await cachedVersions(folder: folder) == ["2.0.0"])
        }
    }

    @Test("a response with no releases falls back to the cache and leaves it intact")
    func emptyResponseKeepsCache() async {
        await withCacheFolder { folder in
            _ = await load(Self.goodText, folder: folder)

            let loaded = await load(Self.noReleases, folder: folder)

            #expect(loaded.source == .cached)
            #expect(loaded.document?.releases.map(\.version) == ["1.0.0"])
            #expect(await cachedVersions(folder: folder) == ["1.0.0"])
        }
    }

    @Test("a response with no releases and no cache is unavailable, and nothing is cached")
    func emptyResponseWithoutCache() async {
        await withCacheFolder { folder in
            let loaded = await load(Self.noReleases, folder: folder)

            #expect(loaded.source == .unavailable)
            #expect(loaded.document == nil)
            #expect(await cachedVersions(folder: folder) == nil)
        }
    }

    @Test("a failed fetch falls back to the cache")
    func failedFetchUsesCache() async {
        await withCacheFolder { folder in
            _ = await load(Self.goodText, folder: folder)

            let loaded = await load(nil, folder: folder)

            #expect(loaded.source == .cached)
            #expect(loaded.document?.releases.map(\.version) == ["1.0.0"])
        }
    }
}
