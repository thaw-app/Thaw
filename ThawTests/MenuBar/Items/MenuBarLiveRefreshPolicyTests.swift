//
//  MenuBarLiveRefreshPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Menu bar live refresh policy")
struct MenuBarLiveRefreshPolicyTests {
    @Test("Off disables every section")
    func offDisablesAllSections() {
        for section in MenuBarSection.Name.allCases {
            #expect(MenuBarLiveRefreshPolicy.refreshInterval(for: section, target: 0) == nil)
        }
    }

    @Test("Hidden and visible follow the target interval")
    func hiddenAndVisibleFollowTarget() {
        let target = 1.0 / 30.0
        #expect(MenuBarLiveRefreshPolicy.refreshInterval(for: .visible, target: target) == target)
        #expect(MenuBarLiveRefreshPolicy.refreshInterval(for: .hidden, target: target) == target)
        #expect(
            MenuBarLiveRefreshPolicy.refreshInterval(for: .alwaysHidden, target: target)
                == MenuBarCaptureService.minAlwaysHiddenInterval
        )
    }

    @Test("Always Hidden never goes faster than 1 fps")
    func alwaysHiddenCeiling() {
        #expect(MenuBarLiveRefreshPolicy.refreshInterval(for: .alwaysHidden, target: 0.2) == 1)
        #expect(MenuBarLiveRefreshPolicy.refreshInterval(for: .alwaysHidden, target: 2) == 2)
    }

    @Test("Visible uses ScreenCaptureKit; offscreen uses the capture service")
    func backends() {
        #expect(MenuBarLiveRefreshPolicy.backend(for: .visible) == .screenCaptureKit)
        #expect(MenuBarLiveRefreshPolicy.backend(for: .hidden) == .captureService)
        #expect(MenuBarLiveRefreshPolicy.backend(for: .alwaysHidden) == .captureService)
    }

    @Test("The first frame is due immediately")
    func firstFrameIsDue() {
        let now = ContinuousClock.now
        #expect(
            MenuBarLiveRefreshPolicy.isDue(
                lastCaptureAt: nil,
                now: now,
                interval: .milliseconds(33)
            )
        )
        #expect(
            !MenuBarLiveRefreshPolicy.isDue(
                lastCaptureAt: now,
                now: now,
                interval: .seconds(1)
            )
        )
        #expect(
            MenuBarLiveRefreshPolicy.isDue(
                lastCaptureAt: now,
                now: now + .seconds(1),
                interval: .seconds(1)
            )
        )
    }

    @Test("An overrun drops missed frames instead of queuing")
    func overrunDropsMissedFrames() {
        let capturedAt = ContinuousClock.now
        let now = capturedAt + .milliseconds(80)
        let deadline = MenuBarLiveRefreshPolicy.nextDeadline(
            capturedAt: capturedAt,
            interval: .milliseconds(33),
            now: now
        )
        #expect(deadline == now + .milliseconds(33))
    }

    @Test("Hidden wins when Hidden and Always Hidden are both due")
    func hiddenWinsOverAlwaysHidden() {
        #expect(
            MenuBarLiveRefreshPolicy.nextOffscreenSection(hiddenDue: true, alwaysHiddenDue: true)
                == .hidden
        )
        #expect(
            MenuBarLiveRefreshPolicy.nextOffscreenSection(hiddenDue: false, alwaysHiddenDue: true)
                == .alwaysHidden
        )
        #expect(
            MenuBarLiveRefreshPolicy.nextOffscreenSection(hiddenDue: false, alwaysHiddenDue: false)
                == nil
        )
    }

    @Test("A fast capture waits out the remainder of the interval")
    func fastCaptureSubtractsCaptureTime() {
        let capturedAt = ContinuousClock.now
        let now = capturedAt + .milliseconds(10)
        let deadline = MenuBarLiveRefreshPolicy.nextDeadline(
            capturedAt: capturedAt,
            interval: .milliseconds(33),
            now: now
        )
        #expect(deadline == capturedAt + .milliseconds(33))
    }
}
