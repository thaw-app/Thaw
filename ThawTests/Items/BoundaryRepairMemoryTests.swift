//
//  BoundaryRepairMemoryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Boundary repair memory")
struct BoundaryRepairMemoryTests {
    private let clock = TestClock()

    private func makeMemory() -> BoundaryRepairMemory {
        let clock = clock
        return BoundaryRepairMemory(now: { clock.now })
    }

    private func item(_ title: String, pid: pid_t = 100) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("test.memory"), title: title),
            windowID: 1,
            ownerPID: pid,
            sourcePID: pid,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private func begin(
        _ memory: BoundaryRepairMemory,
        _ items: [MenuBarItem],
        display: CGDirectDisplayID = 1,
        stranded: Set<String> = [],
        thawPress: Bool = false
    ) -> BoundaryRepairMemory.EntryReport {
        memory.beginPass(
            liveItems: items,
            displayID: display,
            isStrandedMarked: { stranded.contains($0.title ?? "") },
            displayChangeIsThawPress: { thawPress }
        )
    }

    private func fail(_ memory: BoundaryRepairMemory, _ item: MenuBarItem) -> BoundaryRepairBreaker<PostRestrictionRepairItemID>.Outcome {
        memory.record(repaired: false, for: PostRestrictionRepairItemID(item))
    }

    @Test("Items that left the bar are forgotten")
    func prunesDepartedItems() {
        let memory = makeMemory()
        let gone = item("Gone")
        let kept = item("Kept")
        memory.unrepairableItemIDs = [PostRestrictionRepairItemID(gone), PostRestrictionRepairItemID(kept)]
        memory.breaker.suppress(PostRestrictionRepairItemID(gone))
        memory.breaker.addTrip(for: PostRestrictionRepairItemID(kept))

        _ = begin(memory, [kept])

        #expect(memory.unrepairableItemIDs == [PostRestrictionRepairItemID(kept)])
        #expect(!memory.breaker.isSuppressed(PostRestrictionRepairItemID(gone)))
        #expect(memory.breaker.trips(for: PostRestrictionRepairItemID(kept)) == 1)
    }

    @Test("A strand from an earlier launch starts suppressed, once")
    func seedsCarriedStrandsOnce() {
        let memory = makeMemory()
        let strand = item("Strand")
        let other = item("Other")

        let first = begin(memory, [strand, other], stranded: ["Strand"])
        #expect(first.carriedStrands.map(\.title) == ["Strand"])
        #expect(memory.breaker.isSuppressed(PostRestrictionRepairItemID(strand)))
        #expect(memory.seededStrandIDs == [PostRestrictionRepairItemID(strand)])

        memory.breaker.rearm(PostRestrictionRepairItemID(strand))
        let second = begin(memory, [strand, other], stranded: ["Strand"])
        #expect(second.carriedStrands.isEmpty)
        #expect(!memory.breaker.isSuppressed(PostRestrictionRepairItemID(strand)))
    }

    @Test("A display change re-arms suppressed strands")
    func displayChangeRearms() {
        let memory = makeMemory()
        let strand = item("Strand")
        memory.breaker.suppress(PostRestrictionRepairItemID(strand))

        let first = begin(memory, [strand], display: 1)
        #expect(first.displayChange == nil, "the first pass has no display to compare against")
        #expect(memory.lastDisplayID == 1)

        let second = begin(memory, [strand], display: 2)
        #expect(second.displayChange == .rearmed(suppressedCount: 1))
        #expect(!memory.breaker.isSuppressed(PostRestrictionRepairItemID(strand)))
        #expect(memory.lastDisplayID == 2)
    }

    @Test("A display change from Thaw's own press keeps strands suppressed")
    func thawPressKeepsSuppression() {
        let memory = makeMemory()
        let strand = item("Strand")
        _ = begin(memory, [strand], display: 1)
        memory.breaker.suppress(PostRestrictionRepairItemID(strand), at: clock.now)

        let report = begin(memory, [strand], display: 2, thawPress: true)

        #expect(report.displayChange == .causedByThawPress)
        #expect(memory.breaker.isSuppressed(PostRestrictionRepairItemID(strand)))
        #expect(memory.lastDisplayID == 2)
    }

    @Test("The Thaw press check is only asked when the display changed")
    func thawPressCheckedOnlyOnChange() {
        let memory = makeMemory()
        var asked = 0
        for _ in 0 ..< 2 {
            _ = memory.beginPass(
                liveItems: [],
                displayID: 1,
                isStrandedMarked: { _ in false },
                displayChangeIsThawPress: {
                    asked += 1
                    return true
                }
            )
        }
        #expect(asked == 0)
    }

    @Test("A suppression re-arms once its cooldown ends")
    func cooldownRearms() async throws {
        let memory = makeMemory()
        let strand = item("Strand")
        let id = PostRestrictionRepairItemID(strand)
        for _ in 0 ..< BoundaryRepairMemory.tripLimit {
            _ = fail(memory, strand)
        }
        #expect(memory.suppressionHolds(for: id))

        try await clock.sleep(for: BoundaryRepairMemory.suppressionCooldown - .seconds(1))
        #expect(begin(memory, [strand]).rearmedExpired == 0)
        #expect(memory.suppressionHolds(for: id))

        try await clock.sleep(for: .seconds(1))
        #expect(!memory.suppressionHolds(for: id))
        #expect(begin(memory, [strand]).rearmedExpired == 1)
        #expect(!memory.breaker.isSuppressed(id))
    }

    @Test("The trip limit suppresses on the second failure in a row")
    func tripLimit() {
        let memory = makeMemory()
        let strand = item("Strand")

        let first = fail(memory, strand)
        #expect(!first.suppressed)
        #expect(first.trips == 1)
        let second = fail(memory, strand)
        #expect(second.suppressed)
        #expect(second.trips == BoundaryRepairMemory.tripLimit)
    }

    @Test("A repair that worked clears the count")
    func repairClearsTrips() {
        let memory = makeMemory()
        let strand = item("Strand")
        _ = fail(memory, strand)
        memory.record(repaired: true, for: PostRestrictionRepairItemID(strand))
        #expect(!fail(memory, strand).suppressed)
    }

    @Test("An unjudgeable reveal sets the item aside for the cooldown")
    func unjudgeableSuppresses() async throws {
        let memory = makeMemory()
        let id = PostRestrictionRepairItemID(item("Strand"))

        let outcome = memory.record(.unjudgeable(.sharedOwner), for: id)

        #expect(outcome.suppressed)
        #expect(memory.suppressionHolds(for: id))
        try await clock.sleep(for: BoundaryRepairMemory.suppressionCooldown)
        #expect(!memory.suppressionHolds(for: id))
    }

    @Test("The wrapped application menu decline is reported once when it starts and once when it ends")
    func wrappedMenuDecline() {
        let memory = makeMemory()
        #expect(!memory.endWrappedMenuDecline())
        #expect(memory.declineForWrappedMenu())
        #expect(!memory.declineForWrappedMenu())
        #expect(memory.endWrappedMenuDecline())
        #expect(!memory.endWrappedMenuDecline())
    }
}
