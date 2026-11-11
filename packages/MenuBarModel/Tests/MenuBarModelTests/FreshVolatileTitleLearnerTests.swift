//
//  FreshVolatileTitleLearnerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import MenuBarModel
import Testing

@Suite("Fresh volatile title learner")
struct FreshVolatileTitleLearnerTests {
    /// A menu bar item for these tests.
    private func item(
        bundle: String = "com.example.chat",
        title: String,
        x: CGFloat = 1100,
        sourcePID: pid_t? = 42,
        windowID: UInt32 = 1
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .string(bundle),
                title: title,
                windowID: windowID
            ),
            windowID: windowID,
            ownerPID: sourcePID ?? 0,
            sourcePID: sourcePID,
            bounds: CGRect(x: x, y: 4, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A changing title on one stable process slot is learned")
    func learnsStableSingleItemTitleChange() {
        var learner = FreshVolatileTitleLearner()
        #expect(learner.observe([item(title: " 3")]).isEmpty)
        #expect(learner.observe([item(title: " 5")]) == ["com.example.chat"])
    }

    @Test("An app finishing its launch, from Item-0 to its name, is not learned")
    func skipsLaunchPlaceholder() {
        var learner = FreshVolatileTitleLearner()
        _ = learner.observe([item(title: "Item-0")])
        #expect(learner.observe([item(title: "Sync")]).isEmpty)
        #expect(learner.observe([item(title: "Item-0")]).isEmpty, "nor back to it")
    }

    @Test("A moved slot, changed process, or second item is not learned")
    func refusesAmbiguousObservations() {
        var moved = FreshVolatileTitleLearner()
        _ = moved.observe([item(title: "3", x: 100)])
        #expect(moved.observe([item(title: "99+", x: 110)]).isEmpty)

        var relaunched = FreshVolatileTitleLearner()
        _ = relaunched.observe([item(title: "3", sourcePID: 1)])
        #expect(relaunched.observe([item(title: "99+", sourcePID: 2)]).isEmpty)

        var siblings = FreshVolatileTitleLearner()
        _ = siblings.observe([item(title: "3", windowID: 1)])
        #expect(siblings.observe([
            item(title: "99+", windowID: 1),
            item(title: "Status", x: 1120, windowID: 2),
        ]).isEmpty)
    }

    @Test("An existing canonicalizer is left to the static rule")
    func skipsKnownVolatileOwners() {
        var learner = FreshVolatileTitleLearner()
        _ = learner.observe([item(bundle: "com.tencent.qq", title: "3")])
        #expect(learner.observe([item(bundle: "com.tencent.qq", title: "99+")]).isEmpty)
    }

    /// 2026-11-06: DeskRest counts down in its title, and with about 100 apps running no read reached every app.
    @Test("A countdown is learned across reads that skipped the app in between")
    func learnsAcrossReadsThatSkippedTheOwner() {
        var learner = FreshVolatileTitleLearner()
        _ = learner.observe([item(bundle: "com.example.timer", title: "09:58")])
        #expect(learner.observe([item(title: "3")]).isEmpty)
        #expect(learner.observe([item(bundle: "com.example.timer", title: "09:51")]) == ["com.example.timer"])
    }

    @Test("A bundle seen from two live processes is never learned, since a read can skip one")
    func refusesBundlesSharedByTwoProcesses() {
        var learner = FreshVolatileTitleLearner()
        let alive: (pid_t) -> Bool = { _ in true }
        _ = learner.observe([item(title: "3", sourcePID: 1)], isAlive: alive)
        _ = learner.observe([item(title: "Status", sourcePID: 2)], isAlive: alive)
        _ = learner.observe([item(title: "4", sourcePID: 1)], isAlive: alive)
        #expect(learner.observe([item(title: "5", sourcePID: 1)], isAlive: alive).isEmpty)

        var together = FreshVolatileTitleLearner()
        _ = together.observe([item(title: "3", sourcePID: 1, windowID: 1), item(title: "x", x: 1200, sourcePID: 2, windowID: 2)], isAlive: alive)
        _ = together.observe([item(title: "4", sourcePID: 1)], isAlive: alive)
        #expect(together.observe([item(title: "5", sourcePID: 1)], isAlive: alive).isEmpty)
    }

    @Test("A relaunch seen while the old process was still quitting is learned once that process is gone")
    func relaunchOverlapIsNotSharedForGood() {
        var learner = FreshVolatileTitleLearner()
        var running: Set<pid_t> = [1, 2]
        _ = learner.observe([item(title: "3", sourcePID: 1)], isAlive: { running.contains($0) })
        _ = learner.observe([item(title: "4", sourcePID: 2)], isAlive: { running.contains($0) })
        #expect(learner.observe([item(title: "5", sourcePID: 2)], isAlive: { running.contains($0) }).isEmpty, "both still run")

        running = [2]
        #expect(learner.observe([item(title: "6", sourcePID: 2)], isAlive: { running.contains($0) }).isEmpty)
        #expect(learner.observe([item(title: "7", sourcePID: 2)], isAlive: { running.contains($0) }) == ["com.example.chat"])
    }

    @Test("A relaunched app is learned from its new process")
    func learnsAfterARelaunch() {
        var learner = FreshVolatileTitleLearner()
        let gone: (pid_t) -> Bool = { _ in false }
        _ = learner.observe([item(title: "3", sourcePID: 1)], isAlive: gone)
        #expect(learner.observe([item(title: "4", sourcePID: 2)], isAlive: gone).isEmpty)
        #expect(learner.observe([item(title: "5", sourcePID: 2)], isAlive: gone) == ["com.example.chat"])
    }

    @Test("A title kept longer than a few reads is not compared")
    func forgetsOldTitles() {
        var learner = FreshVolatileTitleLearner()
        _ = learner.observe([item(title: "3")])
        for _ in 0 ..< FreshVolatileTitleLearner.maxReadsBetweenTitles {
            _ = learner.observe([item(bundle: "com.example.other", title: "x")])
        }
        #expect(learner.observe([item(title: "5")]).isEmpty)
    }

    @Test("An app seen with a second item since its last title is not learned")
    func forgetsAnOwnerSeenWithSiblings() {
        var learner = FreshVolatileTitleLearner()
        _ = learner.observe([item(title: "3")])
        _ = learner.observe([item(title: "3", windowID: 1), item(title: "Status", x: 1120, windowID: 2)])
        #expect(learner.observe([item(title: "5")]).isEmpty)
    }
}
