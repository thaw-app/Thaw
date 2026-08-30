//
//  MoveEndpointIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Move endpoint identity")
struct MoveEndpointIdentityTests {
    private func item(
        windowID: CGWindowID,
        x: CGFloat,
        ownerPID: pid_t = 80,
        sourcePID: pid_t? = 81,
        title: String
    ) -> MenuBarItem {
        .fixture(
            tag: .appItem(bundleID: "com.example.MoveEndpoint", title: title),
            windowID: windowID,
            bounds: CGRect(x: x, y: 0, width: 24, height: 33),
            sourcePID: sourcePID,
            ownerPID: ownerPID,
            title: title
        )
    }

    @Test("A same-tag replacement is not the planned endpoint")
    func replacementWindowIsRejected() {
        let expected = item(windowID: 40, x: 100, title: "Item")
        let replacement = item(windowID: 41, x: 100, title: "Item")

        #expect(!MenuBarItemManager.moveEndpointIsCurrent(replacement, expected: expected))
    }

    @Test("A recycled window owned by another process is rejected")
    func recycledWindowIsRejected() {
        let expected = item(windowID: 40, x: 100, ownerPID: 80, title: "Item")
        let recycled = item(windowID: 40, x: 100, ownerPID: 90, title: "Item")

        #expect(!MenuBarItemManager.moveEndpointIsCurrent(recycled, expected: expected))
    }

    @Test("A resolved source must still match after the gate")
    func changedSourceIsRejected() {
        let expected = item(windowID: 40, x: 100, sourcePID: 81, title: "Item")
        let changed = item(windowID: 40, x: 100, sourcePID: 82, title: "Item")

        #expect(!MenuBarItemManager.moveEndpointIsCurrent(changed, expected: expected))
    }

    @Test("The exact resolver returns fresh endpoint geometry")
    func exactResolverReturnsFreshRecords() throws {
        let source = item(windowID: 40, x: 100, title: "Source")
        let target = item(windowID: 42, x: 300, title: "Target")
        let movedSource = item(windowID: 40, x: 180, title: "Source")
        let movedTarget = item(windowID: 42, x: 360, title: "Target")

        let endpoints = try MenuBarItemManager.currentMoveEndpoints(
            in: [movedTarget, movedSource],
            expectedSource: source,
            expectedDestination: target
        ).get()

        #expect(endpoints.source.bounds.minX == 180)
        #expect(endpoints.target.bounds.minX == 360)
    }

    @Test("A recycled source or anchor stops the transaction")
    func recycledEndpointStopsTransaction() {
        let source = item(windowID: 40, x: 100, title: "Source")
        let target = item(windowID: 42, x: 300, title: "Target")
        let recycledSource = item(windowID: 40, x: 180, ownerPID: 999, title: "Source")
        let recycledTarget = item(windowID: 42, x: 120, sourcePID: 999, title: "Target")

        #expect(MenuBarItemManager.currentMoveEndpoints(
            in: [recycledSource, target],
            expectedSource: source,
            expectedDestination: target
        ) == .failure(.recycledSource))
        #expect(MenuBarItemManager.currentMoveEndpoints(
            in: [source, recycledTarget],
            expectedSource: source,
            expectedDestination: target
        ) == .failure(.recycledDestination))
    }

    @Test("Exact endpoints produce deterministic ordinal positions")
    func exactEndpointsProduceIndices() {
        let source = item(windowID: 40, x: 100, title: "Source")
        let middle = item(windowID: 41, x: 200, title: "Middle")
        let destination = item(windowID: 42, x: 300, title: "Destination")

        #expect(
            MenuBarItemManager.moveEndpointIndices(
                in: [destination, source, middle],
                sourceWindowID: source.windowID,
                destinationWindowID: destination.windowID
            ) == .init(source: 0, destination: 2)
        )
    }

    @Test("Equal-X endpoint geometry stays unverified")
    func equalXIsAmbiguous() {
        let source = item(windowID: 40, x: 100, title: "Source")
        let destination = item(windowID: 42, x: 100, title: "Destination")

        #expect(MenuBarItemManager.moveEndpointIndices(
            in: [source, destination],
            sourceWindowID: source.windowID,
            destinationWindowID: destination.windowID
        ) == nil)
    }

    @Test("An anchor absent from the selected display cannot verify")
    func missingDisplayEndpointIsRejected() {
        let source = item(windowID: 40, x: 100, title: "Source")
        let destination = item(windowID: 42, x: 300, title: "Destination")

        #expect(MenuBarItemManager.moveEndpointIndices(
            in: [source],
            sourceWindowID: source.windowID,
            destinationWindowID: destination.windowID
        ) == nil)
    }
}
