//
//  HeldItemRevealsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Held item reveals")
struct HeldItemRevealsTests {
    @MainActor
    final class Recorder {
        var shown: [String] = []
        var hidden: [String] = []
    }

    private func make() -> (HeldItemReveals, Recorder) {
        let recorder = Recorder()
        let holds = HeldItemReveals(
            reveal: { recorder.shown.append($0) },
            conceal: { recorder.hidden.append($0) }
        )
        return (holds, recorder)
    }

    @Test("Releasing by bundle lets go of every item of that app the sender holds, and no one else's")
    func releasesEveryItemOfABundle() {
        let (holds, recorder) = make()
        holds.hold("com.x:a", for: "launcher")
        holds.hold("com.x:b", for: "launcher")
        holds.hold("com.x:c", for: "triggers")
        holds.hold("com.y:a", for: "launcher")

        let released = holds.release(bundle: "com.x", itemID: nil, for: "launcher")
        #expect(released == ["com.x:a", "com.x:b"])
        #expect(recorder.hidden == ["com.x:a", "com.x:b"])
        #expect(holds.isHeld("com.x:c"), "another sender's hold stays")
        #expect(holds.isHeld("com.y:a"), "another app's item stays")

        #expect(holds.release(bundle: "com.x", itemID: nil, for: "launcher").isEmpty, "nothing left to release")
        #expect(holds.release(bundle: nil, itemID: "com.y:a", for: "launcher") == ["com.y:a"])
        #expect(holds.release(bundle: nil, itemID: nil, for: "triggers").isEmpty)
    }

    @Test("Every hold shows the item and only the last release hides it")
    func showsOnEveryHoldAndHidesOnce() {
        let (holds, recorder) = make()
        holds.hold("app:Item", for: "triggers")
        holds.hold("app:Item", for: "shortcuts")
        holds.release("app:Item", for: "triggers")
        #expect(recorder.shown == ["app:Item", "app:Item"], "A later hold brings back an item a click hid")
        #expect(recorder.hidden.isEmpty)

        holds.release("app:Item", for: "shortcuts")
        #expect(recorder.hidden == ["app:Item"])
    }

    @Test("Holding twice from one sender needs only one release")
    func repeatedHoldIsOne() {
        let (holds, recorder) = make()
        holds.hold("app:Item", for: "triggers")
        holds.hold("app:Item", for: "triggers")
        holds.release("app:Item", for: "triggers")
        #expect(recorder.hidden == ["app:Item"])
    }

    @Test("Releasing an item nobody holds does nothing")
    func unknownReleaseIsIgnored() {
        let (holds, recorder) = make()
        holds.release("app:Item", for: "triggers")
        #expect(recorder.hidden.isEmpty)
    }

    @Test("When a sender quits, only the items it alone held are hidden")
    func releaseAllFromOneSender() {
        let (holds, recorder) = make()
        holds.hold("app:A", for: "triggers")
        holds.hold("app:B", for: "triggers")
        holds.hold("app:B", for: "shortcuts")

        holds.releaseAll(for: "triggers")

        #expect(recorder.hidden == ["app:A"])
        #expect(holds.isHeld("app:B"))
        #expect(!holds.isHeld("app:A"))
    }

    @Test("Other paths may conceal an item only while nobody holds it")
    func otherPathsLeaveHeldItemsShown() {
        let (holds, _) = make()
        #expect(HeldItemReveals.mayConceal("app:Item", holds: nil), "Nothing held yet")
        #expect(HeldItemReveals.mayConceal("app:Item", holds: holds))
        holds.hold("app:Item", for: "triggers")
        #expect(!HeldItemReveals.mayConceal("app:Item", holds: holds))
        #expect(HeldItemReveals.mayConceal("app:Other", holds: holds))
        holds.release("app:Item", for: "triggers")
        #expect(HeldItemReveals.mayConceal("app:Item", holds: holds))
    }

    @Test("The holds made current are the ones other paths read")
    func currentHolds() {
        let (holds, _) = make()
        holds.makeCurrent()
        #expect(HeldItemReveals.current === holds)
    }
}
