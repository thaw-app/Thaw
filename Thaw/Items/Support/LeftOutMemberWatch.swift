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
///
/// The cache only notices on its own an item that moves the menu bar window list, and on macOS 27
/// a menu-bar-only app publishes its item without a window. So after the app of a left-out member
/// starts, the watch re-reads the bar for a few looks.
@MainActor
enum LeftOutMemberWatch {
    private static let diagLog = DiagLog(category: "LeftOutMemberWatch")

    /// How often the watch looks at the item cache.
    static nonisolated let pollInterval: Duration = .seconds(2)

    /// How many restores are asked for one member until a pass places it, across watches: a
    /// restore's own pass can leave the member out again and start a new watch. Another is asked
    /// for only after the last one ended without placing the member, as when a gate turned it away.
    static nonisolated let maximumRestores = 3

    /// How many looks re-read the bar after the app of a left-out member starts. An app publishes
    /// its item a few seconds after it launches.
    static nonisolated let readsAfterOwnerLaunch = 3

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
        /// Whether the app of a left-out member started recently. On macOS 27 a menu-bar-only app
        /// publishes its item without a window, so the cache's window-list gate misses it.
        var ownerRecentlyLaunched = false
    }

    /// What the watch does after a look.
    nonisolated enum Step: Equatable {
        case wait
        case stop
        /// Re-read the bar, then look again.
        case readBar
        case restore(Set<String>)
    }

    /// Which apps of the left-out members run, and how many more looks re-read the bar after one started.
    nonisolated struct OwnerLaunches: Equatable {
        private var running: Set<String>
        private var readsLeft = 0

        /// Starts from the owners running when the members were left out.
        init(running: Set<String>) {
            self.running = running
        }

        /// Notes the owners running now. True while the bar should be re-read: for
        /// readsAfterOwnerLaunch looks after any owner started.
        mutating func update(running now: Set<String>) -> Bool {
            if !now.subtracting(running).isEmpty {
                readsLeft = LeftOutMemberWatch.readsAfterOwnerLaunch
            }
            running = now
            guard readsLeft > 0 else { return false }
            readsLeft -= 1
            return true
        }
    }

    /// The bundle identifiers of the members' apps that run now. Members not named by a bundle
    /// identifier have no app to watch for.
    static nonisolated func runningOwners(of members: Set<String>, runningBundleIDs: Set<String>) -> Set<String> {
        Set(members.compactMap { identifier in
            let namespace = MenuBarItemTag.persistentIdentifierParts(identifier)?.namespace ?? identifier
            return namespace.contains(".") && runningBundleIDs.contains(namespace) ? namespace : nil
        })
    }

    static nonisolated func step(_ situation: Situation) -> Step {
        guard situation.isCurrentWatch,
              situation.hasLeftOutMembers,
              !situation.arrangementIsManual,
              !situation.userDraggedSinceStart
        else {
            return .stop
        }
        if situation.liveLeftOutMembers.isEmpty, situation.ownerRecentlyLaunched {
            return .readBar
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
    /// restores it may, re-reading the bar when a look asks for it. Returns how many restores it asked for.
    @discardableResult
    static func run(
        interval: Duration = pollInterval,
        maximumRestores: Int = maximumRestores,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        look: () async -> Situation?,
        readBar: () async -> Void = {},
        restore: (Set<String>) -> Void
    ) async -> Int {
        var restores = 0
        while restores < maximumRestores {
            do { try await sleep(interval) } catch { return restores }
            guard let situation = await look() else { return restores }
            switch step(situation) {
            case .wait:
                continue
            case .stop:
                return restores
            case .readBar:
                await readBar()
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
        let ownersAtStart = runningOwners(of: members, runningBundleIDs: RunningApplicationSnapshot.readSystem().bundleIdentifiers)
        return Task { @MainActor [weak manager] in
            var owners = OwnerLaunches(running: ownersAtStart)
            await run(
                look: {
                    let running = await RunningApplicationSnapshot.current().bundleIdentifiers
                    guard let manager else { return nil }
                    var current = situation(of: manager, generation: generation, startedAt: startedAt)
                    current.ownerRecentlyLaunched = owners.update(running: runningOwners(of: members, runningBundleIDs: running))
                    return current
                },
                readBar: {
                    diagLog.debug("the app of a left-out member started; reading the bar for its item")
                    await manager?.cacheItemsRegardless()
                },
                restore: { members in
                    diagLog.notice("\(members.sorted().joined(separator: ", ")) showed up after a visible pass placed the rest without them; restoring the recorded order")
                    manager?.missingRepublishMemo.noteRestoreAsked(for: members)
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
            liveLeftOutMembers: memo.leftOutMembers(amongLive: liveVisible, restoreLimit: maximumRestores, now: now),
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
