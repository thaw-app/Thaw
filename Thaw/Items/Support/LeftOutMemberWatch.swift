//
//  LeftOutMemberWatch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Watches for Visible members a pass placed the others without, and has them placed once one shows up.
///
/// At login an app's item can appear after the visible pass stopped waiting for it, so the pass
/// writes the order without it. MenuBarAgent then puts the item where it puts a new one, next to
/// Thaw's icon. The mirror rarely notices: it holds off while items keep appearing, and it can
/// only spot an arrival against an earlier record of the bar. Its first record would then keep the
/// wrong spot, so the watch asks for the arrival restore as soon as the item is in the cache. The
/// restore marks the authored order pending at once, and the mirror keeps that order meanwhile.
@MainActor
enum LeftOutMemberWatch {
    private static let diagLog = DiagLog(category: "LeftOutMemberWatch")

    /// How often the watch looks at the item cache.
    static nonisolated let pollInterval: Duration = .seconds(2)

    /// How many restores one watch asks for. Another is asked for only after the last one ended
    /// without placing the members, as when a gate turned it away.
    static nonisolated let maximumRestores = 3

    /// What the manager looks like to the watch at one look.
    nonisolated struct Situation: Equatable {
        /// False once a newer watch has started.
        var isCurrentWatch = true
        /// Whether any member left out recently still waits for a pass.
        var hasLeftOutMembers = true
        /// The left-out members that are in the Visible section now.
        var liveLeftOutMembers: Set<String> = []
        var arrangementIsManual = false
        /// Whether the user ⌘-dragged an item since the watch started; their placement stands.
        var userDraggedSinceStart = false
        /// A drag in progress, or one that ended within the quiet period after it.
        var isUserArranging = false
        /// A profile or a layout reset is being applied, and places the members itself.
        var isLayoutBeingApplied = false
        var isSectionRevealed = false
        /// Whether another visible order write is already waiting to run; it places the members.
        var isOrderApplyPending = false
        /// The arrival restore does not run this soon after a restriction change.
        var isWithinRestrictionSettleWindow = false
    }

    /// What the watch does after a look.
    nonisolated enum Step: Equatable {
        case wait
        case stop
        case restore(Set<String>)
    }

    static nonisolated func step(_ situation: Situation) -> Step {
        guard situation.isCurrentWatch,
              situation.hasLeftOutMembers,
              !situation.arrangementIsManual,
              !situation.userDraggedSinceStart
        else {
            return .stop
        }
        guard !situation.liveLeftOutMembers.isEmpty,
              !situation.isUserArranging,
              !situation.isLayoutBeingApplied,
              !situation.isSectionRevealed,
              !situation.isOrderApplyPending,
              !situation.isWithinRestrictionSettleWindow
        else {
            return .wait
        }
        return .restore(situation.liveLeftOutMembers)
    }

    /// Looks after each interval until a look stops the watch or it has asked for the most
    /// restores it may. Returns how many restores it asked for.
    @discardableResult
    static func run(
        interval: Duration = pollInterval,
        maximumRestores: Int = maximumRestores,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        look: () -> Situation?,
        restore: (Set<String>) -> Void
    ) async -> Int {
        var restores = 0
        while restores < maximumRestores {
            do { try await sleep(interval) } catch { return restores }
            guard let situation = look() else { return restores }
            switch step(situation) {
            case .wait:
                continue
            case .stop:
                return restores
            case let .restore(members):
                restore(members)
                restores += 1
            }
        }
        return restores
    }

    /// Records the members a visible pass is about to place the others without, and starts a
    /// watch for them that replaces any running one. The task holds the manager weakly.
    @discardableResult
    static func noteLeftOut(_ members: Set<String>, by manager: MenuBarItemManager) -> Task<Void, Never> {
        manager.missingRepublishMemo.noteMissing(members, at: .now)
        let generation = manager.missingRepublishMemo.startWatch()
        let startedAt = ContinuousClock.now
        return Task { @MainActor [weak manager] in
            await run(
                look: { manager.map { situation(of: $0, generation: generation, startedAt: startedAt) } },
                restore: { members in
                    diagLog.notice("\(members.sorted().joined(separator: ", ")) showed up after a visible pass placed the rest without them; restoring the recorded order")
                    manager?.scheduleArrivalOrderRestore()
                }
            )
        }
    }

    /// The manager as the watch started at generation sees it now.
    static func situation(of manager: MenuBarItemManager, generation: Int, startedAt: ContinuousClock.Instant) -> Situation {
        let now = ContinuousClock.now
        let memo = manager.missingRepublishMemo
        // The cache files items by their assigned section, wherever MenuBarAgent drew them.
        let liveVisible = Set(manager.itemCache[.visible].map(\.uniqueIdentifier))
        return Situation(
            isCurrentWatch: memo.watchGeneration == generation,
            hasLeftOutMembers: memo.hasLeftOutMembers(now: now),
            liveLeftOutMembers: memo.leftOutMembers(amongLive: liveVisible, now: now),
            arrangementIsManual: manager.arrangementIsManual,
            userDraggedSinceStart: manager.lastUserMenuBarDragEnd.map { $0 > startedAt } ?? false,
            isUserArranging: manager.isUserArrangingMenuBar,
            isLayoutBeingApplied: manager.isApplyingProfileLayout || manager.isResettingLayout,
            isSectionRevealed: manager.appState?.menuBarManager.sectionController.revealedSection != nil,
            isOrderApplyPending: manager.authoredVisibleOrderPendingPhysicalApply,
            isWithinRestrictionSettleWindow: manager.barSettling.hold(for: .layoutReorder) != nil
        )
    }
}
