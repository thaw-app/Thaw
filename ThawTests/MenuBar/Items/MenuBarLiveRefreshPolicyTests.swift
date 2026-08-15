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

    @Test("When both are due, Always Hidden goes first so Hidden cannot starve it")
    func alwaysHiddenNotStarvedWhenBothDue() {
        #expect(
            MenuBarLiveRefreshPolicy.nextOffscreenSection(hiddenDue: true, alwaysHiddenDue: true)
                == .alwaysHidden
        )
        #expect(
            MenuBarLiveRefreshPolicy.nextOffscreenSection(hiddenDue: true, alwaysHiddenDue: false)
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

    @Test("Sustained Hidden due-ticks still serve Always Hidden once per cycle")
    func sustainedHiddenStillServesAlwaysHidden() {
        var hiddenCaptures = 0
        var alwaysCaptures = 0
        var alwaysHiddenDue = true
        for _ in 0 ..< 30 {
            switch MenuBarLiveRefreshPolicy.nextOffscreenSection(
                hiddenDue: true,
                alwaysHiddenDue: alwaysHiddenDue
            ) {
            case .alwaysHidden:
                alwaysCaptures += 1
                alwaysHiddenDue = false
            case .hidden:
                hiddenCaptures += 1
            case .visible, nil:
                break
            }
        }
        #expect(alwaysCaptures == 1)
        #expect(hiddenCaptures == 29)
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
