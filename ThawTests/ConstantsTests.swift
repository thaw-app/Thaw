//
//  ConstantsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Tests for ``Constants/supportsSparkleUpdates``.
///
/// Sparkle update checks used to be disabled on macOS 27 preview builds via
/// an `#available(macOS 27, *)` check. That gate was removed in favor of the
/// `alpha` update channel, so `supportsSparkleUpdates` is now an
/// unconditional constant. These tests guard against a regression back to
/// the OS-version-gated behavior.
final class ConstantsTests: XCTestCase {
    func testSupportsSparkleUpdatesIsAlwaysTrue() {
        XCTAssertTrue(Constants.supportsSparkleUpdates)
    }

    func testSupportsSparkleUpdatesIsStableAcrossRepeatedAccess() {
        for _ in 0..<3 {
            XCTAssertTrue(Constants.supportsSparkleUpdates)
        }
    }
}