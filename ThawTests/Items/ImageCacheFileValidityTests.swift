//
//  ImageCacheFileValidityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// A saved image cache is only used by the build that wrote it.
@Suite("Image cache file validity")
struct ImageCacheFileValidityTests {
    @Test("A file from this format and this build is used")
    func sameBuildIsCurrent() {
        #expect(ImageCacheFileValidity.isCurrent(fileVersion: 12, fileBuild: "114", cacheVersion: 12, appBuild: "114"))
    }

    @Test("A file from another build is dropped after an update")
    func otherBuildIsStale() {
        #expect(!ImageCacheFileValidity.isCurrent(fileVersion: 12, fileBuild: "113", cacheVersion: 12, appBuild: "114"))
    }

    @Test("A file written before builds were recorded is dropped once")
    func missingBuildIsStale() {
        #expect(!ImageCacheFileValidity.isCurrent(fileVersion: 12, fileBuild: nil, cacheVersion: 12, appBuild: "114"))
    }

    @Test("A file in another format is dropped whatever the build")
    func otherFormatIsStale() {
        #expect(!ImageCacheFileValidity.isCurrent(fileVersion: 11, fileBuild: "114", cacheVersion: 12, appBuild: "114"))
        #expect(!ImageCacheFileValidity.isCurrent(fileVersion: nil, fileBuild: "114", cacheVersion: 12, appBuild: "114"))
    }

    @Test("Without a known app build, only the format decides")
    func unknownAppBuildUsesFormatOnly() {
        #expect(ImageCacheFileValidity.isCurrent(fileVersion: 12, fileBuild: nil, cacheVersion: 12, appBuild: nil))
    }
}
