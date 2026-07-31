//
//  MenuBarItemImageCacheGatingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

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
@Suite("Menu bar item image cache gating")
struct MenuBarItemImageCacheGatingTests {
    /// No visible consumer and the pane is closed: must not allow background
    /// capture even if a caller explicitly requests it. This is the fix for
    /// the sticky-flag leak amplifier.
    @Test("No consumer with the pane closed does not allow background capture")
    func noConsumerPaneClosedDoesNotAllow() {
        #expect(
            !MenuBarItemImageCache.shouldAllowBackgroundCapture(
                hasVisibleConsumer: false,
                allowBackgroundCapture: true,
                isSettingsPaneOpen: false
            )
        )
    }

    /// The settings pane is open and background capture was explicitly
    /// requested: must allow, preserving prewarm-on-open behavior.
    @Test("An open settings pane with capture requested allows background capture")
    func paneOpenAndAllowedAllows() {
        #expect(
            MenuBarItemImageCache.shouldAllowBackgroundCapture(
                hasVisibleConsumer: false,
                allowBackgroundCapture: true,
                isSettingsPaneOpen: true
            )
        )
    }

    /// A visible consumer (IceBar, search, etc.) exists: must allow regardless
    /// of the settings-pane state or whether background capture was requested.
    @Test("A visible consumer allows capture regardless of the pane state")
    func visibleConsumerAllowsRegardless() {
        #expect(
            MenuBarItemImageCache.shouldAllowBackgroundCapture(
                hasVisibleConsumer: true,
                allowBackgroundCapture: false,
                isSettingsPaneOpen: false
            )
        )
    }

    /// The pane is open but background capture was not explicitly requested,
    /// and there's no visible consumer: must not allow.
    @Test("An open settings pane without a capture request does not allow it")
    func paneOpenWithoutAllowFlagDoesNotAllow() {
        #expect(
            !MenuBarItemImageCache.shouldAllowBackgroundCapture(
                hasVisibleConsumer: false,
                allowBackgroundCapture: false,
                isSettingsPaneOpen: true
            )
        )
    }
}
