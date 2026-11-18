//
//  ImageCacheFileValidityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// A saved image cache is used whole only by the build that wrote it.
@Suite("Image cache file validity")
struct ImageCacheFileValidityTests {
    @Test("A file from this format and this build is used")
    func sameBuildIsCurrent() {
        #expect(ImageCacheFileValidity.isCurrent(fileVersion: 12, fileBuild: "114", cacheVersion: 12, appBuild: "114"))
    }

    @Test("A file from another build is not current after an update")
    func otherBuildIsNotCurrent() {
        #expect(!ImageCacheFileValidity.isCurrent(fileVersion: 12, fileBuild: "113", cacheVersion: 12, appBuild: "114"))
        #expect(ImageCacheFileValidity.verdict(fileVersion: 12, fileBuild: "113", cacheVersion: 12, appBuild: "114") == .otherBuild)
    }

    @Test("A file written before builds were recorded counts as another build's")
    func missingBuildIsOtherBuild() {
        #expect(ImageCacheFileValidity.verdict(fileVersion: 12, fileBuild: nil, cacheVersion: 12, appBuild: "114") == .otherBuild)
    }

    @Test("A file in another format is dropped whatever the build")
    func otherFormatIsStale() {
        #expect(ImageCacheFileValidity.verdict(fileVersion: 11, fileBuild: "114", cacheVersion: 12, appBuild: "114") == .otherFormat)
        #expect(ImageCacheFileValidity.verdict(fileVersion: 11, fileBuild: "113", cacheVersion: 12, appBuild: "114") == .otherFormat)
        #expect(ImageCacheFileValidity.verdict(fileVersion: nil, fileBuild: "114", cacheVersion: 12, appBuild: "114") == .otherFormat)
    }

    @Test("Without a known app build, only the format decides")
    func unknownAppBuildUsesFormatOnly() {
        #expect(ImageCacheFileValidity.isCurrent(fileVersion: 12, fileBuild: nil, cacheVersion: 12, appBuild: nil))
    }

    @Test("The build comes from the app bundle")
    func appBuildMatchesBundle() {
        #expect(ImageCacheFileValidity.appBuild == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }
}
