//
//  RunningApplicationSnapshotTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
struct RunningApplicationSnapshotTests {
    @Test("Collecting liveness from the main actor runs system queries off the main thread")
    func collectionLeavesMainThread() async {
        MainActor.assertIsolated()
        let snapshot = await RunningApplicationSnapshot.current {
            #expect(!Thread.isMainThread, "LaunchServices queries must not block UI events")
            return RunningApplicationSnapshot(processIDs: [111, 222], bundleIdentifiers: ["com.live.app"])
        }
        #expect(snapshot.processIDs == [111, 222])
        #expect(snapshot.bundleIdentifiers == ["com.live.app"])
        MainActor.assertIsolated()
    }
}
