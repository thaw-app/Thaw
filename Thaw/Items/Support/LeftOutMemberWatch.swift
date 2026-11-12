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
/// The cache misses a menu-bar-only app's item, which moves no menu bar window, so the watch
/// re-reads the bar for a few looks after a left-out member's app starts.
@MainActor
enum LeftOutMemberWatch {
    private static let diagLog = DiagLog(category: "LeftOutMemberWatch")

    /// How often the watch looks at the item cache.
    static nonisolated let pollInterval: Duration = .seconds(2)

    /// Restores asked for one member until a pass places it, counted across watches since a
    /// restore's own pass can start a new one. A retry follows only a restore that didn't place it.
    static nonisolated let maximumRestores = 3

    /// The looks after an owner app starts that re-read the bar, about 2, 6 and 14 s later: an app
    /// can publish its item well after it launches.
    static nonisolated let readLooks = [1, 3, 7]

    /// How long after a member is first left out the watch still re-reads the bar for it at its start.
    static nonisolated let readWindow: Duration = pollInterval * 7

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
        /// Whether this look re-reads the bar for a left-out member's item.
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

    /// Which apps of the left-out members run, and the looks since one started.
    nonisolated struct OwnerLaunches: Equatable {
        private var running: Set<String>
        private var looksSinceLaunch: Int?

        /// Starts from the owners running when the members were left out. With readingAtStart, the
        /// watch re-reads as if one had just started: a running app can publish its item late.
        init(running: Set<String>, readingAtStart: Bool = false) {
            self.running = running
            looksSinceLaunch = readingAtStart ? 0 : nil
        }

        /// Notes the owners running now. True on the readLooks looks after any owner started.
        mutating func update(running now: Set<String>) -> Bool {
            if !now.subtracting(running).isEmpty {
                looksSinceLaunch = 0
            }
            running = now
            guard let looks = looksSinceLaunch.map({ $0 + 1 }) else { return false }
            looksSinceLaunch = looks < (LeftOutMemberWatch.readLooks.last ?? 0) ? looks : nil
            return LeftOutMemberWatch.readLooks.contains(looks)
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
        // A new watch replaces the older ones, so it tracks every member still waiting, not only this pass's.
        let memo = manager.missingRepublishMemo
        let running = RunningApplicationSnapshot.readSystem().bundleIdentifiers
        let ownersAtStart = runningOwners(of: memo.leftOutIdentifiers(), runningBundleIDs: running)
        let readingAtStart = !runningOwners(of: memo.recentlyLeftOut(within: readWindow), runningBundleIDs: running).isEmpty
        return Task { @MainActor [weak manager] in
            var owners = OwnerLaunches(running: ownersAtStart, readingAtStart: readingAtStart)
            await run(
                look: {
                    let running = await RunningApplicationSnapshot.current().bundleIdentifiers
                    guard let manager else { return nil }
                    var current = situation(of: manager, generation: generation, startedAt: startedAt)
                    let waiting = manager.missingRepublishMemo.leftOutIdentifiers()
                    current.ownerRecentlyLaunched = owners.update(running: runningOwners(of: waiting, runningBundleIDs: running))
                    return current
                },
                readBar: {
                    diagLog.debug("reading the bar for a left-out member's item")
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
            hasLeftOutMembers: memo.hasLeftOutMembers(among: savedVisibleMembers(of: manager), now: now),
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

    /// The members of the saved Visible order, or nil when there is none to go by.
    static func savedVisibleMembers(of manager: MenuBarItemManager) -> Set<String>? {
        guard let order = manager.savedSectionOrder[manager.sectionKey(for: .visible)], !order.isEmpty else { return nil }
        return Set(order)
    }
}
