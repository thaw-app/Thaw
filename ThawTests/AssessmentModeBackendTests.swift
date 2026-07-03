//
//  AssessmentModeBackendTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@MainActor
final class AssessmentModeBackendTests: XCTestCase {
    func testResolveConcealmentHidesBundleWhenNoSiblingVisible() {
        let result = AssessmentModeBackend.resolveConcealment(
            sectionAssignment: ["hidden-item": .hidden],
            allItems: [],
            knownBundleIDs: ["hidden-item": "com.example.hidden"],
            knownSystemItemIDs: [:]
        )

        XCTAssertEqual(result.concealedBundleIDs, ["com.example.hidden"])
    }

    func testResolveConcealmentKeepsBundleWhenSiblingVisible() {
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Visible"),
            windowID: 1
        )

        let result = AssessmentModeBackend.resolveConcealment(
            sectionAssignment: ["hidden-item": .hidden],
            allItems: [visible],
            knownBundleIDs: [
                "hidden-item": "com.example.app",
                visible.uniqueIdentifier: "com.example.app",
            ],
            knownSystemItemIDs: [:]
        )

        XCTAssertFalse(result.concealedBundleIDs.contains("com.example.app"))
    }

    func testResolveConcealmentNeverConcealsProtectedBundle() {
        let protected = AssessmentModeBackend.protectedBundleIDs.first ?? "com.stonerl.Thaw"

        let result = AssessmentModeBackend.resolveConcealment(
            sectionAssignment: ["hidden-item": .hidden],
            allItems: [],
            knownBundleIDs: ["hidden-item": protected],
            knownSystemItemIDs: [:],
            protectedBundleIDs: [protected]
        )

        XCTAssertTrue(result.concealedBundleIDs.isEmpty)
    }

    func testResolveConcealmentNeverConcealsDenylistedBundle() {
        let result = AssessmentModeBackend.resolveConcealment(
            sectionAssignment: ["hidden-item": .hidden],
            allItems: [],
            knownBundleIDs: ["hidden-item": "com.example.denylisted"],
            knownSystemItemIDs: [:],
            hidingUnsupportedBundleIDs: ["com.example.denylisted"]
        )

        XCTAssertTrue(result.concealedBundleIDs.isEmpty)
    }

    func testShouldReactivateFirstActivation() {
        XCTAssertTrue(
            AssessmentModeBackend.shouldReactivate(
                handleIsNil: true,
                concealedChanged: false,
                systemItemsChanged: false,
                newlyAppeared: false,
                desiredAllowed: ["com.example.allowed"],
                desiredSystemItems: AssessmentModeBackend.allSystemItems,
                desiredConcealed: ["com.example.hidden"],
                previousConfig: nil,
                lastFailed: nil,
                antiFlapWindow: .seconds(3),
                now: ContinuousClock.now
            )
        )
    }

    func testShouldReactivateNoChangeSteadyState() {
        XCTAssertFalse(
            AssessmentModeBackend.shouldReactivate(
                handleIsNil: false,
                concealedChanged: false,
                systemItemsChanged: false,
                newlyAppeared: false,
                desiredAllowed: ["com.example.allowed"],
                desiredSystemItems: AssessmentModeBackend.allSystemItems,
                desiredConcealed: ["com.example.hidden"],
                previousConfig: nil,
                lastFailed: nil,
                antiFlapWindow: .seconds(3),
                now: ContinuousClock.now
            )
        )
    }

    func testShouldReactivateSuppressesFlapWithinWindow() {
        let now = ContinuousClock.now

        XCTAssertFalse(
            AssessmentModeBackend.shouldReactivate(
                handleIsNil: false,
                concealedChanged: true,
                systemItemsChanged: false,
                newlyAppeared: false,
                desiredAllowed: ["com.example.allowed"],
                desiredSystemItems: AssessmentModeBackend.allSystemItems,
                desiredConcealed: ["com.example.hidden"],
                previousConfig: (
                    allowed: ["com.example.allowed"],
                    systemItems: AssessmentModeBackend.allSystemItems,
                    concealed: ["com.example.hidden"],
                    at: now - .seconds(1)
                ),
                lastFailed: nil,
                antiFlapWindow: .seconds(3),
                now: now
            )
        )
    }

    func testShouldReactivateRetriesAfterGenuineChange() {
        XCTAssertTrue(
            AssessmentModeBackend.shouldReactivate(
                handleIsNil: false,
                concealedChanged: true,
                systemItemsChanged: false,
                newlyAppeared: false,
                desiredAllowed: ["com.example.allowed"],
                desiredSystemItems: AssessmentModeBackend.allSystemItems,
                desiredConcealed: ["com.example.hidden"],
                previousConfig: nil,
                lastFailed: (
                    allowed: ["com.example.allowed"],
                    systemItems: AssessmentModeBackend.allSystemItems.subtracting([0])
                ),
                antiFlapWindow: .seconds(3),
                now: ContinuousClock.now
            )
        )
    }

    func testShouldReactivateSuppressesIdenticalFailedConfig() {
        XCTAssertFalse(
            AssessmentModeBackend.shouldReactivate(
                handleIsNil: false,
                concealedChanged: true,
                systemItemsChanged: false,
                newlyAppeared: false,
                desiredAllowed: ["com.example.allowed"],
                desiredSystemItems: AssessmentModeBackend.allSystemItems,
                desiredConcealed: ["com.example.hidden"],
                previousConfig: nil,
                lastFailed: (
                    allowed: ["com.example.allowed"],
                    systemItems: AssessmentModeBackend.allSystemItems
                ),
                antiFlapWindow: .seconds(3),
                now: ContinuousClock.now
            )
        )
    }

    func testIsHidingAvailableMirrorsIsAvailableAtInit() {
        let backend = AssessmentModeBackend()

        XCTAssertEqual(backend.isHidingAvailable, AssessmentModeBackend.isAvailable)
    }

    func testRefreshAvailabilityReturnsCurrentIsAvailable() {
        let backend = AssessmentModeBackend()

        let refreshed = backend.refreshAvailability()

        XCTAssertEqual(refreshed, AssessmentModeBackend.isAvailable)
        XCTAssertEqual(backend.isHidingAvailable, AssessmentModeBackend.isAvailable)
    }
}
