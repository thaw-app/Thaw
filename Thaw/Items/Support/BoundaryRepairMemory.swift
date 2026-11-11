//
//  BoundaryRepairMemory.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// What the boundary repair remembers between passes: which items it gave up on, which still owe a
/// physical seat, and the display the last pass ran against.
@MainActor
final class BoundaryRepairMemory {
    enum DisplayChange: Equatable {
        /// Thaw's own press moved the bar, so the strands stay suppressed.
        case causedByThawPress
        case rearmed(suppressedCount: Int)
    }

    /// What one pass's entry bookkeeping did, so the caller can log it.
    struct EntryReport {
        /// Items suppressed because an earlier launch gave up on them.
        var carriedStrands: [MenuBarItem] = []
        var displayChange: DisplayChange?
        /// Suppressions re-armed because their cooldown ended.
        var rearmedExpired = 0
    }

    /// Consecutive failed passes before an item stops being repaired; a strand two full drag budgets
    /// can't cross has a structural blocker.
    static let tripLimit = 2

    /// How long a suppression holds, so a structural blocker doesn't become a drag storm.
    static let suppressionCooldown: Duration = .seconds(60)

    /// Each item's run of failed passes and whether the repair has given up on it for now. A suppression
    /// clears when the owner quits, the display changes, its cooldown passes, or on relaunch.
    var breaker = BoundaryRepairBreaker<PostRestrictionRepairItemID>()

    /// Visible items a synthetic move could not repair after an assertion reflow. The owner's PID is part
    /// of the key, so ID churn doesn't re-arm them but a relaunch does.
    var unrepairableItemIDs = Set<PostRestrictionRepairItemID>()

    /// Items whose persisted stranded verdict already seeded this session's suppression, so later re-arms hold.
    var seededStrandIDs = Set<PostRestrictionRepairItemID>()

    /// Items the layout pane just moved into the visible section. MenuBarAgent re-allows a concealed item at
    /// the slot it remembers, so the strand pass drags these across the divider whatever the check says.
    var pendingPhysicalSeatIDs = Set<String>()

    private(set) var lastDisplayID: CGDirectDisplayID?

    /// Whether the repair declines drags because the application menu wraps past the notch.
    private(set) var isDecliningForWrappedMenu = false

    private let now: @MainActor () -> ContinuousClock.Instant

    init(now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }) {
        self.now = now
    }

    /// The bookkeeping each pass does before it looks at the bar.
    /// - Parameters:
    ///   - isStrandedMarked: Whether an earlier launch recorded the item as stranded.
    ///   - displayChangeIsThawPress: Asked only when the display changed; a yes is used up.
    func beginPass(
        liveItems: [MenuBarItem],
        displayID: CGDirectDisplayID,
        isStrandedMarked: (MenuBarItem) -> Bool,
        displayChangeIsThawPress: () -> Bool
    ) -> EntryReport {
        var report = EntryReport()
        let liveItemIDs = Set(liveItems.map(PostRestrictionRepairItemID.init))
        unrepairableItemIDs.formIntersection(liveItemIDs)
        breaker.prune(keeping: liveItemIDs)

        // Seeded once per item, so the cooldown and display re-arms still apply afterwards.
        report.carriedStrands = liveItems.filter { item in
            !seededStrandIDs.contains(PostRestrictionRepairItemID(item)) && isStrandedMarked(item)
        }
        for item in report.carriedStrands {
            let id = PostRestrictionRepairItemID(item)
            seededStrandIDs.insert(id)
            breaker.suppress(id, at: now())
        }

        // A display change re-seats the bar, unless Thaw's press caused it: that would re-ladder under an open menu.
        if let lastDisplayID, lastDisplayID != displayID {
            if displayChangeIsThawPress() {
                report.displayChange = .causedByThawPress
            } else {
                report.displayChange = .rearmed(suppressedCount: breaker.suppressedCount)
                breaker.rearmAll()
            }
        }
        lastDisplayID = displayID

        report.rearmedExpired = breaker.rearmExpired(now: now(), cooldown: Self.suppressionCooldown)
        return report
    }

    /// Starts declining drags; true only when it was not declining yet, so the caller logs once.
    func declineForWrappedMenu() -> Bool {
        defer { isDecliningForWrappedMenu = true }
        return !isDecliningForWrappedMenu
    }

    /// Ends the decline; true only when it was declining.
    func endWrappedMenuDecline() -> Bool {
        defer { isDecliningForWrappedMenu = false }
        return isDecliningForWrappedMenu
    }

    func suppressionHolds(for id: PostRestrictionRepairItemID) -> Bool {
        breaker.suppressionHolds(for: id, now: now(), cooldown: Self.suppressionCooldown)
    }

    @discardableResult
    func record(repaired: Bool, for id: PostRestrictionRepairItemID) -> BoundaryRepairBreaker<PostRestrictionRepairItemID>.Outcome {
        breaker.record(repaired: repaired, for: id, tripLimit: Self.tripLimit, now: now())
    }

    @discardableResult
    func record(_ judgement: MoveJudgement, for id: PostRestrictionRepairItemID) -> BoundaryRepairBreaker<PostRestrictionRepairItemID>.Outcome {
        breaker.record(judgement, for: id, tripLimit: Self.tripLimit, now: now())
    }
}
