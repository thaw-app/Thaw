//
//  AutomaticMoveFailureReportingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Automatic move failure reporting")
struct AutomaticMoveFailureReportingTests {
    private let item = MenuBarItem.fixture(
        tag: .appItem(bundleID: "com.example.status", title: "Status"),
        windowID: 42
    )

    @Test("Transient move outcomes are deferrals")
    func transientOutcomesAreDeferred() {
        let errors: [any Error] = [
            CancellationError(),
            MenuBarItemManager.EventError.missingItemBounds(item),
            MenuBarItemManager.EventError.missingDestinationBounds(item),
            MenuBarItemManager.EventError.menuTrackingActive(item),
            MenuBarItemManager.EventError.staleDestination(item),
            MenuBarItemManager.EventError.moveSuperseded(item),
            MenuBarItemManager.EventError.moveEngineBusy(item),
            MenuBarItemManager.EventError.unsafeMovePath(item),
        ]

        for error in errors {
            #expect(MenuBarItemManager.automaticMoveFailureDisposition(for: error) == .deferred)
        }
    }

    @Test("An unresolved Control Center placeholder is a deferral")
    func unresolvedPlaceholderIsDeferred() {
        let unresolved = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-0"),
            windowID: 43,
            sourcePID: nil
        )

        #expect(
            MenuBarItemManager.automaticMoveFailureDisposition(
                for: MenuBarItemManager.EventError.itemNotMovable(unresolved)
            ) == .deferred
        )
    }

    @Test("Terminal event outcomes are reportable")
    func terminalOutcomesAreReportable() {
        let errors: [any Error] = [
            MenuBarItemManager.EventError.cannotComplete,
            MenuBarItemManager.EventError.invalidEventSource,
            MenuBarItemManager.EventError.missingMouseLocation,
            MenuBarItemManager.EventError.eventCreationFailure(item),
            MenuBarItemManager.EventError.eventOperationTimeout(item),
            MenuBarItemManager.EventError.itemResponseTimeout(item),
            MenuBarItemManager.EventError.ownerUnresponsive(item),
            MenuBarItemManager.EventError.eventWindowMismatch(item),
            MenuBarItemManager.EventError.dropReverted(item),
            MenuBarItemManager.EventError.moveTimedOut(item),
            NSError(domain: "AutomaticMoveFailureReportingTests", code: 1),
        ]

        for error in errors {
            #expect(MenuBarItemManager.automaticMoveFailureDisposition(for: error) == .report)
        }
    }

    @Test("A static immovability refusal is reportable")
    func staticImmovabilityIsReportable() {
        let prohibited = MenuBarItem.fixture(tag: .clock, windowID: 44)

        #expect(
            MenuBarItemManager.automaticMoveFailureDisposition(
                for: MenuBarItemManager.EventError.itemNotMovable(prohibited)
            ) == .report
        )
    }

    @Test("The same-item cooldown suppresses before but not at its boundary")
    func itemCooldownBoundary() {
        let now = Date(timeIntervalSince1970: 1000)

        #expect(
            MenuBarItemManager.automaticMoveFailurePresentationDecision(
                now: now,
                lastForItem: now.addingTimeInterval(-599),
                lastOverall: nil
            ) == .suppressSameItem(elapsed: 599)
        )
        #expect(
            MenuBarItemManager.automaticMoveFailurePresentationDecision(
                now: now,
                lastForItem: now.addingTimeInterval(-600),
                lastOverall: nil
            ) == .present
        )
    }

    @Test("The burst cooldown suppresses before but not at its boundary")
    func burstCooldownBoundary() {
        let now = Date(timeIntervalSince1970: 1000)

        #expect(
            MenuBarItemManager.automaticMoveFailurePresentationDecision(
                now: now,
                lastForItem: nil,
                lastOverall: now.addingTimeInterval(-29)
            ) == .suppressBurst(elapsed: 29)
        )
        #expect(
            MenuBarItemManager.automaticMoveFailurePresentationDecision(
                now: now,
                lastForItem: nil,
                lastOverall: now.addingTimeInterval(-30)
            ) == .present
        )
    }

    @Test("A rate-limited failure is still persisted")
    func rateLimitedFailureStillPersists() {
        let plan = MenuBarItemManager.automaticMoveFailureHandlingPlan(
            disposition: .report,
            presentationDecision: .suppressBurst(elapsed: 1)
        )

        #expect(plan.shouldPersist)
        #expect(!plan.shouldPresent)
    }

    @Test("A deferral is neither persisted nor presented")
    func deferralDoesNothing() {
        let plan = MenuBarItemManager.automaticMoveFailureHandlingPlan(
            disposition: .deferred,
            presentationDecision: .present
        )

        #expect(!plan.shouldPersist)
        #expect(!plan.shouldPresent)
    }

    @Test("Visible Settings uses a sheet; background work uses a notification")
    func presentationRoute() {
        #expect(
            MenuBarItemManager.automaticMoveFailurePresentationRoute(settingsWindowVisible: true)
                == .settingsSheet
        )
        #expect(
            MenuBarItemManager.automaticMoveFailurePresentationRoute(settingsWindowVisible: false)
                == .notification
        )
    }

    @Test("A live report path is revealed from its notification")
    func liveNotificationReportIsRevealed() {
        let path = "/tmp/Thaw-move-diagnostic.txt"

        #expect(
            UserNotificationManager.moveFailureOpenAction(
                reportPath: path,
                reportExists: true
            ) == .revealReport(URL(fileURLWithPath: path))
        )
    }

    @Test("A missing or pruned notification report falls back to Settings")
    func missingNotificationReportOpensSettings() {
        #expect(
            UserNotificationManager.moveFailureOpenAction(
                reportPath: nil,
                reportExists: false
            ) == .openSettings
        )
        #expect(
            UserNotificationManager.moveFailureOpenAction(
                reportPath: "/tmp/pruned-report.txt",
                reportExists: false
            ) == .openSettings
        )
    }
}
