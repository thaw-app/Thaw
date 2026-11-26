//
//  ScreenCaptureFallbackTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Screen capture fallback before macOS 26")
@MainActor
struct ScreenCaptureFallbackTests {
    /// The window-list fallback is synchronous, so it must leave the caller's
    /// actor or a MainActor caller is blocked for the whole capture.
    @Test(
        "A MainActor job queued before the capture runs before the capture returns",
        .enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26, "The fallback only runs before macOS 26")
    )
    func fallbackLeavesTheMainActorFree() async {
        var mainActorJobRan = false
        Task { @MainActor in mainActorJobRan = true }

        _ = await ScreenCapture.captureWindowsAsync(with: [])

        #expect(mainActorJobRan)
    }
}
