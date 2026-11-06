//
//  LayoutBatchMoveExecutor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Carries out a move of one or more items as one Layout drop; thaw://move-item and the pane's selection share it.
///
/// Every item is checked before anything is written, and the whole batch goes to the
/// move path in a single call, so the bar is re-laid once rather than once per item.
@MainActor
struct LayoutBatchMoveExecutor {
    /// The Layout pane's sections as the request is checked against them.
    var snapshot: () -> LayoutBatchMoveSnapshot
    /// Tells the repair lane that the user is arranging the bar.
    var noteUserInput: (RepairOrchestrator.Cause) -> Void
    /// Hands a checked plan to the Layout pane's drop path; false when that path declined it.
    var commit: (LayoutBatchMovePlan) async -> Bool
    /// Waits to see whether the bar took a committed Visible plan; nil skips the wait.
    var barFollows: ((LayoutBatchMovePlan) async -> Bool)?

    func run(_ command: LayoutBatchMove) async -> LayoutBatchMoveOutcome {
        let plan: LayoutBatchMovePlan
        switch command.plan(in: snapshot()) {
        case let .success(checked): plan = checked
        case let .failure(error): return .refused(error)
        }
        guard !plan.changesNothing else {
            // A retry after notApplied matches the saved order, so only the bar can say it worked.
            if plan.target == .visible, let barFollows, await !barFollows(plan) {
                return .notApplied(plan)
            }
            return .unchanged(plan)
        }
        // A user edit, so automatic passes queued before it yield and the write budget resets.
        noteUserInput(.userEdit)
        guard await commit(plan) else { return .refused(.moveRefused) }
        if plan.target == .visible, let barFollows, await !barFollows(plan) {
            return .notApplied(plan)
        }
        return .moved(plan)
    }
}

extension LayoutBatchMoveExecutor {
    /// With verifiesBar, run waits for the Visible order to reach the bar; the Layout pane leaves it off so it never waits.
    init(appState: AppState, verifiesBar: Bool = false) {
        self.init(
            snapshot: { Self.snapshot(appState: appState) },
            noteUserInput: { appState.itemManager.repairs.interruptAutomaticWork(by: $0) },
            commit: { plan in
                guard let drop = Self.drop(for: plan, appState: appState) else { return false }
                return await LayoutDropCommit.perform(drop, appState: appState)
            },
            barFollows: verifiesBar ? { plan in await Self.visibleOrderReachesBar(plan, appState: appState) } : nil
        )
    }

    /// The manager debounces 400 ms, then runs a few passes of a few seconds each, so wait slightly longer than that.
    static var barApplyBudget: Duration {
        .milliseconds(400) + .milliseconds(2500) * MenuBarItemManager.authoredVisibleOrderApplyAttempts
    }

    private static func visibleOrderReachesBar(_ plan: LayoutBatchMovePlan, appState: AppState) async -> Bool {
        let controller = appState.menuBarManager.sectionController
        return await pollBarFollows(
            budget: barApplyBudget,
            sleep: { try? await Task.sleep(for: $0) },
            matches: {
                let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                return appState.itemManager.liveOrderMatches(
                    plan.targetOrder,
                    section: .visible,
                    controller: controller,
                    items: items
                )
            }
        )
    }

    /// Checks after the apply's debounce and then every interval; true on the first match, false once the budget is spent.
    /// The sleep is injected so the elapsed time is counted, not measured.
    static func pollBarFollows(
        budget: Duration,
        initialDelay: Duration = .milliseconds(400),
        interval: Duration = .seconds(1),
        sleep: (Duration) async -> Void,
        matches: () async -> Bool
    ) async -> Bool {
        var elapsed = initialDelay
        await sleep(initialDelay)
        while true {
            if await matches() { return true }
            guard elapsed < budget else { return false }
            await sleep(interval)
            elapsed += interval
        }
    }

    private static func editorItems(appState: AppState) -> [MenuBarSectionName: [MenuBarItem]] {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let enabled = MenuBarSectionName.allCases.filter {
            appState.menuBarManager.section(withName: $0)?.isEnabled == true
        }
        return Dictionary(uniqueKeysWithValues: enabled.map {
            ($0, LayoutDisplayedItems.editorItems(in: $0, appState: appState, runningApplications: running))
        })
    }

    static func snapshot(appState: AppState) -> LayoutBatchMoveSnapshot {
        let systemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        let reorderable = systemItemHiding && LayoutBarPaddingView.allowsAnchoredSystemItemReordering(appState: appState)
        let sections = editorItems(appState: appState)
        return LayoutBatchMoveSnapshot(sections: Dictionary(uniqueKeysWithValues: sections.map { section, items in
            var groupAtIndex = [Int: String]()
            for group in appState.itemGroupManager.resolvedGroups(for: items) where group.memberIndices.count > 1 {
                for index in group.memberIndices {
                    groupAtIndex[index] = "\(section.rawValue):\(group.origin)"
                }
            }
            return (section, items.enumerated().map { index, item in
                LayoutBatchMoveSnapshot.Entry(
                    id: item.uniqueIdentifier,
                    isControlItem: item.isControlItem,
                    groupID: groupAtIndex[index],
                    assignableSections: assignableSections(for: item, experimentalSystemItemHiding: systemItemHiding),
                    reordersInVisible: item.isPhysicallyOrderable(experimentalSystemItemHiding: reorderable)
                )
            })
        }))
    }

    private static func assignableSections(for item: MenuBarItem, experimentalSystemItemHiding: Bool) -> Set<MenuBarSectionName> {
        Set(MenuBarSectionName.allCases.filter {
            MenuBarBackendProvider.current.canAssign(item, to: $0, experimentalSystemItemHiding: experimentalSystemItemHiding)
        })
    }

    /// The plan as a Layout pane drop, read again so it acts on the items as they are now.
    /// Nil when an item has gone since the plan was made.
    static func drop(for plan: LayoutBatchMovePlan, appState: AppState) -> LayoutDropCommit.Drop? {
        let byID = Dictionary(
            editorItems(appState: appState).values.flatMap(\.self).map { ($0.uniqueIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let items = plan.itemIDs.compactMap { byID[$0] }
        let targetOrder = plan.targetOrder.compactMap { byID[$0] }
        guard items.count == plan.itemIDs.count, targetOrder.count == plan.targetOrder.count else {
            return nil
        }
        return LayoutDropCommit.Drop(
            items: items,
            source: plan.source,
            target: plan.target,
            previousTargetOrder: plan.previousTargetOrder.compactMap { byID[$0] },
            targetOrder: targetOrder,
            isBatch: items.count > 1
        )
    }
}
