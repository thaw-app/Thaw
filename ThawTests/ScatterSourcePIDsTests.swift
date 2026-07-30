//
//  ScatterSourcePIDsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers `MenuBarItem.scatterSourcePIDs(_:toIndices:windowCount:)`.
///
/// Only windows that actually need resolving are sent to the XPC service —
/// control items are skipped, because their PID is already known locally and
/// asking would trigger an expensive scan of every running app's extras menu
/// bar (#820). That makes the reply a dense array indexed against the
/// *request*, not against the window list, and lining the two back up is the
/// whole job. Getting it wrong attributes one app's PID to another app's
/// item, which is the identity confusion the sourcePID work exists to
/// prevent.
@Suite("Source PID scatter")
struct ScatterSourcePIDsTests {
    @Test("Resolved PIDs land on the windows that were sent")
    func pidsLandOnRequestedWindows() {
        // Windows 0 and 3 are control items and were never sent, so they
        // stay nil while 1 and 2 take the two returned PIDs in order.
        let scattered = MenuBarItem.scatterSourcePIDs(
            [501, 502],
            toIndices: [1, 2],
            windowCount: 4
        )

        #expect(scattered ?? [] == [nil, 501, 502, nil])
    }

    @Test("A nil in the reply stays nil at its own position")
    func unresolvedEntriesStayNil() {
        // The service resolving some but not all of a batch is ordinary;
        // it must not shift the ones that did resolve.
        let scattered = MenuBarItem.scatterSourcePIDs(
            [501, nil, 503],
            toIndices: [0, 1, 2],
            windowCount: 3
        )

        #expect(scattered ?? [] == [501, nil, 503])
    }

    @Test("Non-contiguous request indices keep their positions")
    func sparseIndicesKeepPositions() {
        let scattered = MenuBarItem.scatterSourcePIDs(
            [601, 602],
            toIndices: [0, 4],
            windowCount: 5
        )

        #expect(scattered ?? [] == [601, nil, nil, nil, 602])
    }

    @Test("Sending nothing yields an all-nil list rather than a refusal")
    func emptyRequestIsNotAFailure() {
        // Every window was a control item. There is nothing to scatter, but
        // nothing went wrong either, so this must not read as a mismatch.
        let scattered = MenuBarItem.scatterSourcePIDs([], toIndices: [], windowCount: 3)

        #expect(scattered ?? [] == [nil, nil, nil])
    }

    @Test("Zero windows yields an empty list")
    func zeroWindows() {
        #expect(MenuBarItem.scatterSourcePIDs([], toIndices: [], windowCount: 0) ?? [nil] == [])
    }

    @Test(
        "A reply of the wrong length is refused outright",
        arguments: [
            [pid_t?](),
            [501],
            [501, 502, 503],
        ]
    )
    func lengthMismatchIsRefused(resolved: [pid_t?]) {
        // Refused rather than zipped as far as it goes: a length mismatch
        // means the positional correspondence itself is broken, so every
        // entry is suspect, not just the missing tail. Treating all as
        // unresolved is recoverable; misattributing a PID is not.
        #expect(MenuBarItem.scatterSourcePIDs(resolved, toIndices: [1, 2], windowCount: 4) == nil)
    }

    @Test("An out-of-range index is skipped rather than trapping")
    func outOfRangeIndexIsSkipped() {
        // Defensive: the indices come from the caller's own window list, so
        // this should be unreachable, but scattering must not crash the app
        // if it ever is.
        let scattered = MenuBarItem.scatterSourcePIDs(
            [501, 502],
            toIndices: [0, 99],
            windowCount: 2
        )

        #expect(scattered ?? [] == [501, nil])
    }
}
