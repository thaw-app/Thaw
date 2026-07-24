//
//  MenuBarItemImageCacheGatingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterizes the gating decision that bounds the perpetual background
/// capture loop feeding the SkyLight WindowServer leak (#759).
///
/// `settingsPaneHasBeenOpened` used to be a sticky flag: once the user opened
/// the layout settings pane a single time, it stayed `true` for the process
/// lifetime, and every space/screen/appearance/item-cache change from then on
/// triggered a full background capture of all sections — including offscreen
/// sections through the leaking SkyLight path — even with every Thaw window
/// closed. `shouldAllowBackgroundCapture` now gates on whether the pane is
/// *currently* open, bounding the window in which background captures can run.
final class MenuBarItemImageCacheGatingTests: XCTestCase {
    /// No visible consumer and the pane is closed: must not allow background
    /// capture even if a caller explicitly requests it. This is the fix for
    /// the sticky-flag leak amplifier.
    func testNoConsumerPaneClosedDoesNotAllow() {
        XCTAssertFalse(
            MenuBarItemImageCache.shouldAllowBackgroundCapture(
                hasVisibleConsumer: false,
                allowBackgroundCapture: true,
                isSettingsPaneOpen: false
            )
        )
    }

    /// The settings pane is open and background capture was explicitly
    /// requested: must allow, preserving prewarm-on-open behavior.
    func testPaneOpenAndAllowedAllows() {
        XCTAssertTrue(
            MenuBarItemImageCache.shouldAllowBackgroundCapture(
                hasVisibleConsumer: false,
                allowBackgroundCapture: true,
                isSettingsPaneOpen: true
            )
        )
    }

    /// A visible consumer (IceBar, search, etc.) exists: must allow regardless
    /// of the settings-pane state or whether background capture was requested.
    func testVisibleConsumerAllowsRegardless() {
        XCTAssertTrue(
            MenuBarItemImageCache.shouldAllowBackgroundCapture(
                hasVisibleConsumer: true,
                allowBackgroundCapture: false,
                isSettingsPaneOpen: false
            )
        )
    }

    /// The pane is open but background capture was not explicitly requested,
    /// and there's no visible consumer: must not allow.
    func testPaneOpenWithoutAllowFlagDoesNotAllow() {
        XCTAssertFalse(
            MenuBarItemImageCache.shouldAllowBackgroundCapture(
                hasVisibleConsumer: false,
                allowBackgroundCapture: false,
                isSettingsPaneOpen: true
            )
        )
    }

    /// The pane was opened once but has since closed, and no consumer is
    /// visible: must not allow. This is the sticky-flag regression this plan
    /// fixes — previously `settingsPaneHasBeenOpened` never reset to `false`.
    func testPaneOpenedThenClosedDoesNotAllow() {
        XCTAssertFalse(
            MenuBarItemImageCache.shouldAllowBackgroundCapture(
                hasVisibleConsumer: false,
                allowBackgroundCapture: true,
                isSettingsPaneOpen: false
            )
        )
    }
}
