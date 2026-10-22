//
//  CompletedWalkGenerationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing

/// The kit retires a conceal snapshot only on two different complete walks,
/// so the number must tell complete walks apart and never vouch for a partial one.
@MainActor
struct CompletedWalkGenerationTests {
    private func item(_ pid: pid_t) -> MenuBarItem {
        MenuBarItem(
            tag: .init(namespace: .string("com.example.owner\(pid)"), title: "Status", instanceIndex: 0),
            windowID: UInt32(pid),
            ownerPID: 99,
            sourcePID: pid,
            bounds: CGRect(x: 100, y: 3, width: 24, height: 24),
            title: "Status",
            isOnScreen: true
        )
    }

    @Test("Nothing is vouched for before the first complete walk")
    func nilBeforeAnyCompleteWalk() {
        let snapshot = OnScreenItemSnapshot()
        #expect(snapshot.completedWalkGeneration == nil)
        snapshot.update([item(1)])
        #expect(snapshot.completedWalkGeneration == nil)
        snapshot.update([item(1)], fromCompleteWalk: false)
        #expect(snapshot.completedWalkGeneration == nil)
    }

    @Test("Each complete walk gets a larger number")
    func growsWithEachCompleteWalk() throws {
        let snapshot = OnScreenItemSnapshot()
        snapshot.update([item(1)], fromCompleteWalk: true)
        let first = try #require(snapshot.completedWalkGeneration)
        snapshot.update([item(1), item(2)], fromCompleteWalk: true)
        let second = try #require(snapshot.completedWalkGeneration)
        #expect(second > first)
    }

    @Test("Reading the same walk again gives the same number")
    func stableWhileItemsComeFromTheSameWalk() {
        let snapshot = OnScreenItemSnapshot()
        snapshot.update([item(1)], fromCompleteWalk: true)
        let generation = snapshot.completedWalkGeneration
        #expect(snapshot.completedWalkGeneration == generation)
        #expect(snapshot.items.count == 1)
    }

    @Test("A partial walk clears the number, and the next complete walk still counts up")
    func partialWalkClearsAndCountingResumes() throws {
        let snapshot = OnScreenItemSnapshot()
        snapshot.update([item(1)], fromCompleteWalk: true)
        let before = try #require(snapshot.completedWalkGeneration)
        snapshot.update([item(1)], fromCompleteWalk: false)
        #expect(snapshot.completedWalkGeneration == nil)
        snapshot.update([item(1)], fromCompleteWalk: true)
        let after = try #require(snapshot.completedWalkGeneration)
        #expect(after > before)
    }
}
