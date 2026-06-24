//
//  MenuBarItemTriggersManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation

/// Runtime status for a trigger's condition evaluation and item-move pipeline.
enum MenuBarItemTriggerRuntimeStatus: Equatable {
    /// The trigger is turned off.
    case off
    /// The trigger is on, but at least one required source is disabled.
    case inactive
    /// A changed decision is waiting for the source-specific settle delay.
    case settling
    /// The trigger has a queued or in-flight item move.
    case moving
    /// The reveal decision has been applied.
    case active
    /// The hide decision has been applied, or nothing needs to reveal.
    case idle
    /// A reveal decision is true, but no apply is currently queued.
    case pending
    /// A higher-priority met trigger currently owns the same target item.
    case overridden(by: [String])
    /// The trigger move was deferred by another layout operation.
    case deferred
    /// The target item or required controls are unavailable.
    case unavailable
    /// The trigger move was attempted but failed.
    case failed

    var isTerminalForDisplay: Bool {
        switch self {
        case .overridden, .deferred, .unavailable, .failed:
            true
        case .off, .inactive, .settling, .moving, .active, .idle, .pending:
            false
        }
    }
}

/// Owns the user's menu bar item triggers, persists them, and applies them
/// by revealing or hiding their target items as system conditions change.
///
/// Each enabled trigger is re-evaluated whenever the aggregated
/// ``SystemState`` changes (and periodically as a safety net, which also
/// covers time-of-day schedules). When a trigger's reveal decision flips,
/// its target item is moved into the configured reveal or hide section
/// after a short debounce, so brief fluctuations do not thrash the menu bar.
@MainActor
final class MenuBarItemTriggersManager: ObservableObject {
    /// The user's configured triggers.
    @Published var triggers: [MenuBarItemTrigger] {
        didSet {
            guard !suppressPersist else { return }
            persist()
            // A trigger may have been added, edited, or re-enabled; drop the
            // memoized state so the next evaluation re-applies. (The actual
            // move is still a no-op when the item is already in the right
            // section, so this does not warp the cursor on no-op edits.)
            lastAppliedReveal.removeAll()
            lastAppliedItemIdentifiers.removeAll()
            pendingMoveReveal.removeAll()
            pendingMoveItemIdentifiers.removeAll()
            runtimeStatuses.removeAll()
            runScriptsIfNeeded()
            refreshImageHashesIfNeeded()
            scheduleEvaluation()
        }
    }

    /// Runtime apply/move status for each trigger, surfaced in the settings UI.
    @Published private(set) var runtimeStatuses = [UUID: MenuBarItemTriggerRuntimeStatus]()

    /// Per-source feature flags, also surfaced in the Developer pane.
    let featureFlags = TriggerFeatureFlagsManager()

    /// The shared app state.
    private weak var appState: AppState?

    /// Monitors the aggregated system state.
    let systemMonitor = SystemStateMonitor()

    /// The reveal decision currently reflected in each target item's
    /// placement, used to skip redundant moves.
    private var lastAppliedReveal = [UUID: Bool]()

    /// Target identifiers included in the most recently applied move.
    private var lastAppliedItemIdentifiers = [UUID: Set<String>]()

    /// Reveal decisions with an in-flight move queued. These are not yet
    /// reflected in the menu bar, but suppress duplicate queueing while the
    /// move chain catches up.
    private var pendingMoveReveal = [UUID: Bool]()

    /// Target identifiers included in a queued or in-flight move.
    private var pendingMoveItemIdentifiers = [UUID: Set<String>]()

    /// Per-trigger debounced apply tasks. A flipped decision only moves its
    /// item after the new state has held for the condition's settle interval.
    private var pendingApplyTasks = [UUID: Task<Void, Never>]()

    /// Fallback settle when a trigger has no condition-specific interval.
    private let fallbackSettleInterval: Duration = .seconds(1)

    /// True while loading from defaults; suppresses writeback.
    private var suppressPersist = false

    private var cancellables = Set<AnyCancellable>()

    /// Debounced forced-evaluation task, restarted on each edit.
    private var debouncedEvaluationTask: Task<Void, Never>?

    /// Cached results of script-result conditions, keyed by script path,
    /// injected into the system state at evaluation time.
    private var scriptOutcomes = [String: ScriptOutcome]()

    /// Guards against overlapping script-run passes.
    private var isRunningScripts = false

    /// Cached perceptual hashes of watched items for image-comparison
    /// conditions, keyed by tag identifier, injected into the system state.
    private var imageHashes = [String: UInt64]()

    /// Guards against overlapping image-capture passes.
    private var isRefreshingImages = false

    /// Serializes all trigger-driven item moves. Each batch awaits the
    /// previous one so synthetic-drag moves never overlap — overlapping
    /// moves desync the move engine's cursor hide/show and can strand items.
    private var moveChain = Task<Void, Never> {}

    private let diagLog = DiagLog(category: "MenuBarItemTriggers")

    struct TriggerPriorityAction: Equatable {
        var reveal: Bool
        var identifiers: [String]

        var identifierSet: Set<String> {
            Set(identifiers)
        }
    }

    struct TriggerPriorityPlan {
        var actions = [UUID: TriggerPriorityAction]()
        var overriddenBy = [UUID: [String]]()
        var unavailableTriggerIDs = Set<UUID>()

        mutating func setAction(reveal: Bool, identifiers: [String], for triggerID: UUID) {
            let dedupedIdentifiers = Array(NSOrderedSet(array: identifiers).compactMap { $0 as? String })
            if var action = actions[triggerID], action.reveal == reveal {
                action.identifiers = Array(NSOrderedSet(array: action.identifiers + dedupedIdentifiers).compactMap { $0 as? String })
                actions[triggerID] = action
            } else {
                actions[triggerID] = TriggerPriorityAction(reveal: reveal, identifiers: dedupedIdentifiers)
            }
        }
    }

    /// The system state used for evaluation, with cached script results
    /// merged in (the monitor itself does not run scripts).
    private var evaluationState: SystemState {
        var state = systemMonitor.state
        state.scriptOutcomes = scriptOutcomes
        state.imageHashes = imageHashes
        return state
    }

    init() {
        suppressPersist = true
        triggers = Self.load()
        suppressPersist = false
    }

    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState

        systemMonitor.start(flags: featureFlags)

        // Re-evaluate on every distinct system state change.
        systemMonitor.$state
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.evaluate(for: self.evaluationState, force: false)
            }
            .store(in: &cancellables)

        // A periodic forced re-evaluation reconciles drift (manual user
        // moves, late-appearing items) and advances time-of-day schedules.
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.runScriptsIfNeeded()
                self.refreshImageHashesIfNeeded()
                self.evaluate(for: self.evaluationState, force: true)
            }
            .store(in: &cancellables)

        runScriptsIfNeeded()
        refreshImageHashesIfNeeded()

        // Re-apply when feature flags change (a newly enabled source may
        // satisfy a trigger that was previously inert).
        featureFlags.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                // Run after the flag set mutates so cached sources whose
                // monitors live here (scripts and image hashes) populate
                // before the forced evaluation.
                DispatchQueue.main.async {
                    self?.runScriptsIfNeeded()
                    self?.refreshImageHashesIfNeeded()
                    self?.scheduleEvaluation()
                }
            }
            .store(in: &cancellables)

        scheduleEvaluation()
    }

    /// The current aggregated system state (for live UI readouts), with
    /// cached script results merged in.
    var currentSystemState: SystemState {
        evaluationState
    }

    /// Returns the current reveal decision using the same live frontmost-app
    /// read used by the move engine.
    func shouldRevealNow(_ trigger: MenuBarItemTrigger) -> Bool {
        trigger.shouldReveal(state: effectiveState(for: trigger, base: evaluationState))
    }

    /// Whether the trigger's target item is currently placed in its reveal
    /// section (i.e. the trigger last revealed it).
    func isCurrentlyRevealed(_ trigger: MenuBarItemTrigger) -> Bool {
        lastAppliedReveal[trigger.id] == true
    }

    /// Returns the current runtime status for a trigger.
    func runtimeStatus(for trigger: MenuBarItemTrigger) -> MenuBarItemTriggerRuntimeStatus {
        guard trigger.isEnabled else { return .off }
        guard isAvailable(trigger) else { return .inactive }

        if pendingApplyTasks[trigger.id] != nil {
            return .settling
        }
        if pendingMoveReveal[trigger.id] != nil {
            return .moving
        }
        if let status = runtimeStatuses[trigger.id],
           status.isTerminalForDisplay
        {
            return status
        }
        if let appliedReveal = lastAppliedReveal[trigger.id] {
            return appliedReveal ? .active : .idle
        }
        return shouldRevealNow(trigger) ? .pending : .idle
    }

    // MARK: - Mutation

    /// Adds a trigger.
    func add(_ trigger: MenuBarItemTrigger) {
        triggers.append(trigger)
    }

    /// Removes the trigger with the given id.
    func remove(id: UUID) {
        triggers.removeAll { $0.id == id }
        lastAppliedReveal[id] = nil
        pendingMoveReveal[id] = nil
        pendingMoveItemIdentifiers[id] = nil
        lastAppliedItemIdentifiers[id] = nil
        runtimeStatuses[id] = nil
        pendingApplyTasks[id]?.cancel()
        pendingApplyTasks[id] = nil
    }

    /// Removes the triggers at the given offsets.
    func remove(atOffsets offsets: IndexSet) {
        let removedIDs = offsets.compactMap { triggers.indices.contains($0) ? triggers[$0].id : nil }
        triggers.remove(atOffsets: offsets)
        for id in removedIDs {
            lastAppliedReveal[id] = nil
            pendingMoveReveal[id] = nil
            pendingMoveItemIdentifiers[id] = nil
            lastAppliedItemIdentifiers[id] = nil
            runtimeStatuses[id] = nil
            pendingApplyTasks[id]?.cancel()
            pendingApplyTasks[id] = nil
        }
    }

    /// Replaces the trigger sharing the given id, if present.
    func update(_ trigger: MenuBarItemTrigger) {
        guard let index = triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        triggers[index] = trigger
    }

    /// Moves a trigger from one priority position to another.
    func moveTrigger(from sourceIndex: Int, to destinationIndex: Int) {
        guard triggers.indices.contains(sourceIndex),
              triggers.indices.contains(destinationIndex),
              sourceIndex != destinationIndex
        else { return }

        let trigger = triggers.remove(at: sourceIndex)
        triggers.insert(trigger, at: destinationIndex)
    }

    /// Moves a trigger before another trigger, used by drag-and-drop priority
    /// reordering in the settings pane.
    func moveTrigger(id sourceID: UUID, before targetID: UUID) {
        guard let sourceIndex = triggers.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = triggers.firstIndex(where: { $0.id == targetID })
        else { return }

        moveTrigger(from: sourceIndex, to: targetIndex)
    }

    // MARK: - Evaluation

    /// Schedules a debounced forced evaluation against the current state.
    private func scheduleEvaluation(after delay: Duration = .milliseconds(300)) {
        debouncedEvaluationTask?.cancel()
        debouncedEvaluationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.evaluate(for: self.evaluationState, force: true)
        }
    }

    /// Evaluates every enabled trigger against the given system state.
    ///
    /// A reveal decision that has flipped relative to the item's current
    /// placement is applied immediately when `force` is `true` (startup,
    /// edits, the safety timer) or after a debounce when `false` (live state
    /// changes).
    private func evaluate(for state: SystemState, force: Bool) {
        guard let appState else { return }

        let liveIDs = Set(triggers.map(\.id))
        lastAppliedReveal = lastAppliedReveal.filter { liveIDs.contains($0.key) }
        lastAppliedItemIdentifiers = lastAppliedItemIdentifiers.filter { liveIDs.contains($0.key) }
        pendingMoveReveal = pendingMoveReveal.filter { liveIDs.contains($0.key) }
        pendingMoveItemIdentifiers = pendingMoveItemIdentifiers.filter { liveIDs.contains($0.key) }
        runtimeStatuses = runtimeStatuses.filter { liveIDs.contains($0.key) }
        for (id, task) in pendingApplyTasks where !liveIDs.contains(id) {
            task.cancel()
            pendingApplyTasks[id] = nil
        }

        let presentIdentifiers = Set(appState.itemManager.itemCache.managedItems.map(\.tag.tagIdentifier))
        let now = Date()
        let plan = priorityPlan(for: state, presentIdentifiers: presentIdentifiers, now: now)

        for trigger in triggers where trigger.isEnabled {
            guard !trigger.allItemIdentifiers.isEmpty else { continue }
            guard isAvailable(trigger) else {
                clearApplyState(for: trigger.id)
                setRuntimeStatus(.inactive, for: trigger.id)
                continue
            }

            if let names = plan.overriddenBy[trigger.id] {
                clearApplyState(for: trigger.id)
                setRuntimeStatus(.overridden(by: names), for: trigger.id)
                continue
            }

            guard let action = plan.actions[trigger.id] else {
                clearApplyState(for: trigger.id)
                if plan.unavailableTriggerIDs.contains(trigger.id) {
                    setRuntimeStatus(.unavailable, for: trigger.id)
                } else {
                    setRuntimeStatus(.idle, for: trigger.id)
                }
                continue
            }

            if appliedActionMatches(action, for: trigger.id) {
                pendingApplyTasks[trigger.id]?.cancel()
                pendingApplyTasks[trigger.id] = nil
                setRuntimeStatus(action.reveal ? .active : .idle, for: trigger.id)
                continue
            }

            if pendingActionMatches(action, for: trigger.id) {
                pendingApplyTasks[trigger.id]?.cancel()
                pendingApplyTasks[trigger.id] = nil
                setRuntimeStatus(.moving, for: trigger.id)
                continue
            }

            if action.identifiers.isEmpty {
                setRuntimeStatus(.unavailable, for: trigger.id)
                continue
            }

            if force {
                if shouldDebounceForcedApply(trigger) {
                    scheduleDebouncedApply(for: trigger.id)
                } else {
                    pendingApplyTasks[trigger.id]?.cancel()
                    pendingApplyTasks[trigger.id] = nil
                    apply(trigger, action: action)
                }
            } else {
                scheduleDebouncedApply(for: trigger.id)
            }
        }
    }

    /// Whether all of the trigger's conditions are currently available
    /// (each condition's feature flag is enabled, or it is an
    /// always-available power condition).
    private func isAvailable(_ trigger: MenuBarItemTrigger) -> Bool {
        trigger.allConditions.allSatisfy { condition in
            guard let feature = condition.kind.requiredFeature else { return true }
            return featureFlags.isEnabled(feature)
        }
    }

    func priorityPlan(
        for state: SystemState,
        presentIdentifiers: Set<String>,
        now: Date = Date()
    ) -> TriggerPriorityPlan {
        var plan = TriggerPriorityPlan()
        var metOwnerByIdentifier = [String: MenuBarItemTrigger]()
        var fallbackCandidates = [(trigger: MenuBarItemTrigger, identifiers: [String])]()

        for trigger in triggers where trigger.isEnabled {
            guard !trigger.allItemIdentifiers.isEmpty, isAvailable(trigger) else { continue }

            let presentTargets = trigger.allItemIdentifiers.filter { presentIdentifiers.contains($0) }
            guard !presentTargets.isEmpty else {
                plan.unavailableTriggerIDs.insert(trigger.id)
                continue
            }

            let triggerState = effectiveState(for: trigger, base: state)
            let reveal = trigger.shouldReveal(state: triggerState, now: now)
            if reveal {
                var ownedTargets = [String]()
                var overriddenNames = Set<String>()
                for identifier in presentTargets {
                    if let owner = metOwnerByIdentifier[identifier] {
                        overriddenNames.insert(owner.displayName)
                    } else {
                        metOwnerByIdentifier[identifier] = trigger
                        ownedTargets.append(identifier)
                    }
                }
                if !ownedTargets.isEmpty {
                    plan.setAction(reveal: true, identifiers: ownedTargets, for: trigger.id)
                }
                if !overriddenNames.isEmpty {
                    plan.overriddenBy[trigger.id] = Array(overriddenNames).sorted()
                }
            } else {
                fallbackCandidates.append((trigger, presentTargets))
            }
        }

        var fallbackClaimedIdentifiers = Set<String>()
        for candidate in fallbackCandidates {
            let identifiers = candidate.identifiers.filter { identifier in
                metOwnerByIdentifier[identifier] == nil && !fallbackClaimedIdentifiers.contains(identifier)
            }
            guard !identifiers.isEmpty else { continue }
            fallbackClaimedIdentifiers.formUnion(identifiers)
            plan.setAction(reveal: false, identifiers: identifiers, for: candidate.trigger.id)
        }

        return plan
    }

    /// Schedules a debounced apply, re-checking the live state when the
    /// debounce elapses so a decision that flipped back is never acted on.
    /// The settle interval is per-condition (long for battery thresholds,
    /// short for discrete sources) so app/network/focus triggers stay
    /// responsive.
    private func scheduleDebouncedApply(for triggerID: UUID) {
        let replacedPendingApply = pendingApplyTasks[triggerID] != nil
        pendingApplyTasks[triggerID]?.cancel()
        pendingApplyTasks[triggerID] = nil
        guard let queuedTrigger = triggers.first(where: { $0.id == triggerID }) else { return }

        let settle = settleInterval(for: queuedTrigger)
        setRuntimeStatus(.settling, for: triggerID)
        let scheduledAt = Date()
        let replaceText = replacedPendingApply ? "replaced pending; " : ""
        diagLog.debug(
            "Trigger \(queuedTrigger.displayName) \(replaceText)queued pending apply for \(formattedDuration(settle))"
        )
        pendingApplyTasks[triggerID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self else { return }
            self.pendingApplyTasks[triggerID] = nil

            guard
                let trigger = self.triggers.first(where: { $0.id == triggerID }),
                trigger.isEnabled,
                !trigger.allItemIdentifiers.isEmpty,
                self.isAvailable(trigger)
            else {
                self.refreshRuntimeStatus(for: triggerID)
                self.diagLog.debug(
                    "Trigger \(queuedTrigger.displayName) pending apply expired after "
                        + "\(self.formattedElapsed(since: scheduledAt)) but trigger is no longer available"
                )
                return
            }
            let presentIdentifiers = Set(self.appState?.itemManager.itemCache.managedItems.map(\.tag.tagIdentifier) ?? [])
            let plan = self.priorityPlan(for: self.evaluationState, presentIdentifiers: presentIdentifiers)
            if let names = plan.overriddenBy[triggerID] {
                self.setRuntimeStatus(.overridden(by: names), for: triggerID)
                self.clearApplyState(for: triggerID)
                self.diagLog.debug(
                    "Trigger \(trigger.displayName) pending apply expired after "
                        + "\(self.formattedElapsed(since: scheduledAt)); overridden by \(names.joined(separator: ", "))"
                )
                return
            }
            guard let action = plan.actions[triggerID] else {
                self.clearApplyState(for: triggerID)
                self.setRuntimeStatus(plan.unavailableTriggerIDs.contains(triggerID) ? .unavailable : .idle, for: triggerID)
                self.diagLog.debug(
                    "Trigger \(trigger.displayName) pending apply expired after "
                        + "\(self.formattedElapsed(since: scheduledAt)); no priority action remains"
                )
                return
            }
            guard !self.appliedActionMatches(action, for: triggerID) else {
                self.setRuntimeStatus(action.reveal ? .active : .idle, for: triggerID)
                self.diagLog.debug(
                    "Trigger \(trigger.displayName) pending apply expired after "
                        + "\(self.formattedElapsed(since: scheduledAt)); already applied reveal=\(action.reveal)"
                )
                return
            }
            self.diagLog.debug(
                "Trigger \(trigger.displayName) pending apply expired after "
                    + "\(self.formattedElapsed(since: scheduledAt)); applying reveal=\(action.reveal)"
            )
            self.apply(trigger, action: action)
        }
    }

    /// Records the reveal decision as applied and moves the target item.
    ///
    /// Does nothing (and does not record the decision) when the target item
    /// isn't currently present, so the trigger re-applies once it appears.
    private func apply(_ trigger: MenuBarItemTrigger, action: TriggerPriorityAction) {
        guard let appState else { return }
        let presentIDs = Set(appState.itemManager.itemCache.managedItems.map(\.tag.tagIdentifier))
        let targets = action.identifiers.filter(presentIDs.contains)
        guard !targets.isEmpty else {
            setRuntimeStatus(.unavailable, for: trigger.id)
            return
        }

        let wasRevealed = lastAppliedReveal[trigger.id] == true || pendingMoveReveal[trigger.id] == true
        pendingMoveReveal[trigger.id] = action.reveal
        pendingMoveItemIdentifiers[trigger.id] = Set(targets)
        setRuntimeStatus(.moving, for: trigger.id)

        // Notify on the transition into the revealed state.
        if action.reveal, !wasRevealed, trigger.notifyOnReveal {
            let itemName = trigger.itemDisplayName.isEmpty ? "an item" : trigger.itemDisplayName
            appState.userNotificationManager.requestAuthorization()
            appState.userNotificationManager.addRequest(
                with: .triggerFired,
                title: trigger.displayName,
                body: "Revealed \(itemName)."
            )
        }

        let section = action.reveal ? trigger.revealSection : trigger.hideSection
        diagLog.debug("Trigger \(trigger.displayName) reveal=\(action.reveal); moving \(targets.count) item(s) to \(section.logString)")
        enqueueMoves(for: trigger, action: TriggerPriorityAction(reveal: action.reveal, identifiers: targets), to: section)
    }

    /// Returns whether a queued move still matches the current trigger config
    /// and current system state.
    private func queuedMoveIsCurrent(for queuedTrigger: MenuBarItemTrigger, action queuedAction: TriggerPriorityAction) -> Bool {
        guard
            let current = triggers.first(where: { $0.id == queuedTrigger.id }),
            current == queuedTrigger,
            current.isEnabled,
            isAvailable(current)
        else {
            return false
        }

        let presentIDs = Set(appState?.itemManager.itemCache.managedItems.map(\.tag.tagIdentifier) ?? [])
        guard current.allItemIdentifiers.contains(where: presentIDs.contains) else { return false }
        let plan = priorityPlan(for: evaluationState, presentIdentifiers: presentIDs)
        guard let currentAction = plan.actions[current.id] else { return false }
        return currentAction.reveal == queuedAction.reveal && currentAction.identifierSet == queuedAction.identifierSet
    }

    private func moveOptions(for trigger: MenuBarItemTrigger) -> (
        requiredInputPause: Duration,
        inputPauseTimeout: Duration?,
        watchdogTimeout: DispatchTimeInterval?,
        maxMoveAttempts: Int,
        hideCursorAcrossAttempts: Bool
    ) {
        let isFrontmostDriven = trigger.allConditions.contains { $0.kind == .frontmostApp }
        if isFrontmostDriven {
            return (.seconds(1), .seconds(3), .seconds(2), 3, false)
        }
        return (.milliseconds(50), nil, nil, 8, true)
    }

    private func effectiveState(for trigger: MenuBarItemTrigger, base state: SystemState) -> SystemState {
        guard trigger.allConditions.contains(where: { $0.kind == .frontmostApp }) else {
            return state
        }

        var state = state
        state.frontmostAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return state
    }

    private func shouldDebounceForcedApply(_ trigger: MenuBarItemTrigger) -> Bool {
        trigger.allConditions.contains { $0.kind == .frontmostApp }
    }

    /// Appends a batch of moves to the serial move chain so only one move
    /// runs at a time, app-wide, regardless of how many triggers fire. Each
    /// queued batch revalidates immediately before moving, because frontmost
    /// app changes can enqueue opposite moves while an earlier synthetic drag
    /// is still waiting behind the chain.
    private func enqueueMoves(
        for trigger: MenuBarItemTrigger,
        action: TriggerPriorityAction,
        to section: MenuBarSection.Name
    ) {
        let queuedAt = Date()
        let previous = moveChain
        moveChain = Task { @MainActor [weak self] in
            _ = await previous.value
            guard let self, let itemManager = self.appState?.itemManager else { return }
            let batchStartedAt = Date()
            guard self.queuedMoveIsCurrent(for: trigger, action: action) else {
                if self.pendingActionMatches(action, for: trigger.id) {
                    self.clearPendingMove(for: trigger.id)
                }
                self.refreshRuntimeStatus(for: trigger.id)
                self.diagLog.debug(
                    "Skipping stale trigger move for \(trigger.displayName) after queue wait "
                        + "\(self.formattedElapsed(since: queuedAt))"
                )
                return
            }
            let options = self.moveOptions(for: trigger)
            self.diagLog.debug(
                "Starting trigger move batch for \(trigger.displayName) after queue wait "
                    + "\(self.formattedElapsed(since: queuedAt))"
            )
            for identifier in action.identifiers {
                guard self.queuedMoveIsCurrent(for: trigger, action: action) else {
                    self.diagLog.debug(
                        "Stopping stale trigger move batch for \(trigger.displayName) after "
                            + "\(self.formattedElapsed(since: batchStartedAt))"
                    )
                    if self.pendingActionMatches(action, for: trigger.id) {
                        self.clearPendingMove(for: trigger.id)
                    }
                    self.refreshRuntimeStatus(for: trigger.id)
                    return
                }
                let itemMoveStartedAt = Date()
                let result = await itemManager.moveItem(
                    withTagIdentifier: identifier,
                    toSection: section,
                    requiredInputPause: options.requiredInputPause,
                    inputPauseTimeout: options.inputPauseTimeout,
                    watchdogTimeout: options.watchdogTimeout,
                    maxMoveAttempts: options.maxMoveAttempts,
                    hideCursorAcrossAttempts: options.hideCursorAcrossAttempts,
                    shouldProceed: { [weak self] in
                        self?.queuedMoveIsCurrent(for: trigger, action: action) ?? false
                    }
                )
                switch result {
                case .moved, .alreadyInSection:
                    self.diagLog.debug(
                        "Trigger \(trigger.displayName) move for \(identifier) finished with \(result) in "
                            + "\(self.formattedElapsed(since: itemMoveStartedAt))"
                    )
                    continue
                case .deferred:
                    self.diagLog.debug(
                        "Trigger \(trigger.displayName) move for \(identifier) deferred after "
                            + "\(self.formattedElapsed(since: itemMoveStartedAt))"
                    )
                    self.setRuntimeStatus(.deferred, for: trigger.id)
                    self.finishPendingMove(for: trigger, action: action, applied: false, retry: true)
                    return
                case .failed:
                    self.diagLog.debug(
                        "Trigger \(trigger.displayName) move for \(identifier) failed with \(result) after "
                            + "\(self.formattedElapsed(since: itemMoveStartedAt))"
                    )
                    self.setRuntimeStatus(.failed, for: trigger.id)
                    self.finishPendingMove(for: trigger, action: action, applied: false, retry: false)
                    return
                case .unavailable:
                    self.diagLog.debug(
                        "Trigger \(trigger.displayName) move for \(identifier) failed with \(result) after "
                            + "\(self.formattedElapsed(since: itemMoveStartedAt))"
                    )
                    self.setRuntimeStatus(.unavailable, for: trigger.id)
                    self.finishPendingMove(for: trigger, action: action, applied: false, retry: false)
                    return
                }
            }
            self.diagLog.debug(
                "Finished trigger move batch for \(trigger.displayName) in "
                    + "\(self.formattedElapsed(since: batchStartedAt))"
            )
            self.finishPendingMove(for: trigger, action: action, applied: true, retry: false)
        }
    }

    private func settleInterval(for trigger: MenuBarItemTrigger) -> Duration {
        if let override = trigger.settleSecondsOverride, override > 0 {
            return .seconds(override)
        }
        // Use the most conservative (longest) settle across all conditions so
        // a jittery source (e.g. battery) still absorbs flapping.
        return trigger.allConditions.map(\.kind.settleInterval).max() ?? fallbackSettleInterval
    }

    private func formattedDuration(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        return formattedSeconds(seconds)
    }

    private func formattedElapsed(since start: Date) -> String {
        formattedSeconds(Date().timeIntervalSince(start))
    }

    private func formattedSeconds(_ seconds: TimeInterval) -> String {
        if seconds >= 10 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.3fs", seconds)
    }

    private func finishPendingMove(
        for trigger: MenuBarItemTrigger,
        action: TriggerPriorityAction,
        applied: Bool,
        retry: Bool
    ) {
        if pendingActionMatches(action, for: trigger.id) {
            clearPendingMove(for: trigger.id)
        }
        if applied {
            lastAppliedReveal[trigger.id] = action.reveal
            lastAppliedItemIdentifiers[trigger.id] = action.identifierSet
            setRuntimeStatus(action.reveal ? .active : .idle, for: trigger.id)
            return
        }
        lastAppliedReveal[trigger.id] = nil
        lastAppliedItemIdentifiers[trigger.id] = nil
        guard retry, queuedMoveIsCurrent(for: trigger, action: action) else { return }
        diagLog.debug("Retrying deferred trigger move for \(trigger.displayName) after layout settles")
        scheduleEvaluation(after: .seconds(1))
    }

    private func appliedActionMatches(_ action: TriggerPriorityAction, for triggerID: UUID) -> Bool {
        lastAppliedReveal[triggerID] == action.reveal &&
            lastAppliedItemIdentifiers[triggerID] == action.identifierSet
    }

    private func pendingActionMatches(_ action: TriggerPriorityAction, for triggerID: UUID) -> Bool {
        pendingMoveReveal[triggerID] == action.reveal &&
            pendingMoveItemIdentifiers[triggerID] == action.identifierSet
    }

    private func clearPendingMove(for triggerID: UUID) {
        pendingMoveReveal[triggerID] = nil
        pendingMoveItemIdentifiers[triggerID] = nil
    }

    private func clearApplyState(for triggerID: UUID) {
        pendingApplyTasks[triggerID]?.cancel()
        pendingApplyTasks[triggerID] = nil
        clearPendingMove(for: triggerID)
        lastAppliedReveal[triggerID] = nil
        lastAppliedItemIdentifiers[triggerID] = nil
    }

    private func setRuntimeStatus(_ status: MenuBarItemTriggerRuntimeStatus, for triggerID: UUID) {
        guard runtimeStatuses[triggerID] != status else { return }
        runtimeStatuses[triggerID] = status
    }

    private func refreshRuntimeStatus(for triggerID: UUID) {
        guard let trigger = triggers.first(where: { $0.id == triggerID }) else {
            runtimeStatuses[triggerID] = nil
            return
        }
        setRuntimeStatus(runtimeStatus(for: trigger), for: triggerID)
    }

    // MARK: - Scripts

    /// Runs every distinct script referenced by an enabled script-result
    /// condition (when the feature is on), updating cached outcomes and
    /// re-evaluating when any result changes.
    private func runScriptsIfNeeded() {
        guard featureFlags.isEnabled(.scriptResult), !isRunningScripts else { return }

        // Collect distinct, non-empty script paths in use by enabled triggers.
        var paths = Set<String>()
        for trigger in triggers where trigger.isEnabled {
            for condition in trigger.allConditions {
                if case let .scriptResult(path, _) = condition {
                    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { paths.insert(trimmed) }
                }
            }
        }

        // Drop cached outcomes for paths no longer referenced.
        let removed = Set(scriptOutcomes.keys).subtracting(paths)
        let removedAny = !removed.isEmpty
        for path in removed {
            scriptOutcomes[path] = nil
        }

        guard !paths.isEmpty else {
            if removedAny {
                evaluate(for: evaluationState, force: true)
            }
            return
        }

        isRunningScripts = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRunningScripts = false }

            var changed = removedAny
            for path in paths {
                let outcome = await TriggerScriptRunner.run(path: path)
                let resolved = outcome ?? ScriptOutcome(exitCode: -1, output: "")
                if self.scriptOutcomes[path] != resolved {
                    self.scriptOutcomes[path] = resolved
                    changed = true
                }
            }

            if changed {
                self.evaluate(for: self.evaluationState, force: false)
            }
        }
    }

    // MARK: - Image comparison

    /// Captures the current perceptual hash for every watched item used by an
    /// enabled image-comparison condition (when the feature is on), updating
    /// the cache and re-evaluating when any hash changes.
    private func refreshImageHashesIfNeeded() {
        guard featureFlags.isEnabled(.imageComparison), !isRefreshingImages else { return }

        var ids = Set<String>()
        for trigger in triggers where trigger.isEnabled {
            for condition in trigger.allConditions {
                if case let .imageChanged(itemIdentifier, _) = condition, !itemIdentifier.isEmpty {
                    ids.insert(itemIdentifier)
                }
            }
        }

        let removed = Set(imageHashes.keys).subtracting(ids)
        let removedAny = !removed.isEmpty
        for id in removed {
            imageHashes[id] = nil
        }

        guard !ids.isEmpty else {
            if removedAny {
                evaluate(for: evaluationState, force: true)
            }
            return
        }

        isRefreshingImages = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRefreshingImages = false }

            var changed = removedAny
            for id in ids {
                guard let hash = await self.currentImageHash(forItemIdentifier: id) else {
                    if self.imageHashes[id] != nil {
                        self.imageHashes[id] = nil
                        changed = true
                    }
                    continue
                }
                if self.imageHashes[id] != hash {
                    self.imageHashes[id] = hash
                    changed = true
                }
            }
            if changed {
                self.evaluate(for: self.evaluationState, force: false)
            }
        }
    }

    /// Captures the watched item's window and returns its perceptual hash.
    private func currentImageHash(forItemIdentifier id: String) async -> UInt64? {
        guard
            let appState,
            let item = appState.itemManager.itemCache.managedItems.first(where: { $0.tag.tagIdentifier == id })
        else {
            return nil
        }

        let image = await ScreenCapture.captureWindowAsync(with: item.windowID)
            ?? ScreenCapture.captureWindow(with: item.windowID)
        guard let image else { return nil }
        return ImageHashing.averageHash(image)
    }

    /// Captures a reference hash for the given item now (used by the editor's
    /// "Capture reference" button).
    func captureReferenceHash(forItemIdentifier id: String) async -> UInt64? {
        await currentImageHash(forItemIdentifier: id)
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(triggers) else {
            diagLog.error("Failed to encode menu bar item triggers")
            return
        }
        Defaults.set(data, forKey: .menuBarItemTriggers)
    }

    private static func load() -> [MenuBarItemTrigger] {
        guard let data = Defaults.data(forKey: .menuBarItemTriggers) else {
            return []
        }
        do {
            return try JSONDecoder().decode([MenuBarItemTrigger].self, from: data)
        } catch {
            return []
        }
    }
}
