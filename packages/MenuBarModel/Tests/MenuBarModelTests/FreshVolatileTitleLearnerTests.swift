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
}
