//
//  MenuBarItemImageCacheGatingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Background capture of offscreen sections goes through a SkyLight path that
/// leaks WindowServer memory (#759), so it is gated on the settings pane being
/// open now, not ever.
@Suite("Menu bar item image cache gating")
struct MenuBarItemImageCacheGatingTests {
    /// With the pane closed and no consumer, even an explicit request is refused.
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

    /// Preserves prewarm-on-open.
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

    @Test("Trigger-only attention capture selects watched identifiers")
    func triggerOnlyAttentionCaptureIsNarrow() {
        let required = MenuBarItemImageCache.requiredCaptureIdentifiers(
            availableIdentifiers: ["mail", "calendar", "battery"],
            consumerNeedsWholeSection: false,
            globalAttentionNeedsWholeSection: false,
            attentionTriggerIdentifiers: ["calendar", "not-in-section"]
        )

        #expect(required == ["calendar"])
    }

    @Test("Visible demand unions a whole section with trigger demand")
    func visibleConsumerKeepsWholeSection() {
        let required = MenuBarItemImageCache.requiredCaptureIdentifiers(
            availableIdentifiers: ["mail", "calendar", "battery"],
            consumerNeedsWholeSection: true,
            globalAttentionNeedsWholeSection: false,
            attentionTriggerIdentifiers: ["calendar"]
        )

        #expect(required == ["mail", "calendar", "battery"])
    }

    @Test("Global attention keeps full concealed-section coverage")
    func globalAttentionKeepsWholeSection() {
        let required = MenuBarItemImageCache.requiredCaptureIdentifiers(
            availableIdentifiers: ["mail", "calendar", "battery"],
            consumerNeedsWholeSection: false,
            globalAttentionNeedsWholeSection: true,
            attentionTriggerIdentifiers: []
        )

        #expect(required == ["mail", "calendar", "battery"])
    }
}
