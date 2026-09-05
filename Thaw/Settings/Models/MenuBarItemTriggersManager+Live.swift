//
//  MenuBarItemTriggersManager+Live.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Collections
import Foundation

/// The live half of ``MenuBarItemTriggersManager``: everything whose substance
/// needs a running `AppState`. Setup and its observations, the evaluation pass
/// that reads the item cache, the debounced apply, the serial move chain and
/// its retry bookkeeping, reveal notifications, script runs, and the image
/// capture behind the icon-watching conditions. None of that can run in a unit
/// test, so this file is excluded from coverage in sonar-project.properties.
///
/// The measured half (MenuBarItemTriggersManager.swift) keeps the decisions:
/// the priority plan, identifier resolution, feature availability, runtime
/// status, ownership, CRUD and persistence. New decision logic belongs there,
/// not here; methods in this file should stay thin orchestration over those
/// measured primitives, mirroring the ProfileManager / ProfileManager+Live
/// split.
extension MenuBarItemTriggersManager {
    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState

        systemMonitor.start(flags: featureFlags)

        // Item-manager setup follows settings setup. Claim configured targets
        // up front so its initial cache cannot restore a persisted pre-trigger
        // position before the first live evaluation establishes the action.
        let configuredTargetIdentifiers = Set(
            triggers
                .filter { $0.isEnabled && isAvailable($0) }
                .flatMap(\.allItemIdentifiers)
        )
        appState.itemManager.setTriggerControlledItemIdentifiers(configuredTargetIdentifiers)

        // Re-evaluate on every distinct system state change.
        systemMonitor.$state
            // The monitor is seeded before the item manager has populated
            // its cache. Ignoring this replay keeps the configured targets
            // claimed above until the cache observer below can build a plan
            // from real items; otherwise that empty-cache evaluation would
            // immediately release them and let initial saved-layout restore
            // race the trigger's first move.
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.evaluate(for: self.evaluationState, force: false)
            }
            .store(in: &cancellables)

        // A cache update is the authoritative signal that an item moved to a
        // different section. Watching it lets triggers repair a manual or
        // external move promptly, rather than trusting a stale Boolean memo
        // until the condition itself happens to flip.
        // `MenuBarItemManager` is @Observable, so its old `$itemCache`
        // projection is gone. Match the app's Observations async-sequence
        // pattern; `scheduleEvaluation(after:)` already coalesces, which is
        // what the old `.debounce` provided.
        itemCacheObservationTask?.cancel()
        itemCacheObservationTask = Task { @MainActor [weak self, weak appState] in
            let changes = Observations { appState?.itemManager.itemCache }
            var isFirst = true
            for await _ in changes {
                guard let self else { return }
                if isFirst {
                    isFirst = false
                    continue
                }
                self.scheduleEvaluation(after: .milliseconds(150))
            }
        }

        // Always-Hidden may be requested by a trigger while the section is
        // disabled. Re-evaluate immediately when that capability changes so
        // a previous hidden fallback migrates to Always-Hidden (and vice
        // versa) without waiting for the next condition flip.
        alwaysHiddenObservationTask?.cancel()
        alwaysHiddenObservationTask = Task { @MainActor [weak self, weak appState] in
            let changes = Observations { appState?.settings.advanced.enableAlwaysHiddenSection }
            var previous: Bool??
            for await isEnabled in changes {
                guard let self else { return }
                defer { previous = isEnabled }
                guard previous != nil, previous != isEnabled else { continue }
                self.scheduleEvaluation(after: .milliseconds(150))
            }
        }

        // A periodic forced re-evaluation reconciles drift (manual user
        // moves, late-appearing items) and advances time-of-day schedules.
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.runScriptsIfNeeded()
                self.refreshImageHashesIfNeeded()
                self.updateAttentionDetectionDemand()
                self.evaluate(for: self.evaluationState, force: true)
            }
            .store(in: &cancellables)

        runScriptsIfNeeded()
        refreshImageHashesIfNeeded()
        updateAttentionDetectionDemand()

        // Re-apply when feature flags change (a newly enabled source may
        // satisfy a trigger that was previously inert).
        featureFlags.addChangeHandler { [weak self] in
            // `isAvailable` reads the flags, so ownership changes with them.
            self?.refreshControlledIdentifiers()
            // Run after the flag set mutates so cached sources whose
            // monitors live here (scripts and image hashes) populate
            // before the forced evaluation.
            DispatchQueue.main.async {
                self?.runScriptsIfNeeded()
                self?.refreshImageHashesIfNeeded()
                self?.scheduleEvaluation()
            }
        }

        scheduleEvaluation()
    }

    /// Evaluates every enabled trigger against the given system state.
    ///
    /// A reveal decision that has flipped relative to the item's current
    /// placement is applied immediately when `force` is `true` (startup,
    /// edits, the safety timer) or after a debounce when `false` (live state
    /// changes).
    func evaluate(for state: SystemState, force: Bool) {
        guard let appState else { return }

        // Setup claims configured trigger targets before ItemManager's first
        // live cache. Never turn that claim into an empty plan while the cache
        // is still unpopulated: doing so briefly releases the saved-layout
        // shield and lets startup restore fight the first trigger move.
        guard !appState.itemManager.itemCache.managedItems.isEmpty else {
            diagLog.debug("Skipping trigger evaluation until the first non-empty item cache")
            return
        }

        let liveIDs = Set(triggers.map(\.id))
        lastAppliedReveal = lastAppliedReveal.filter { liveIDs.contains($0.key) }
        lastAppliedItemIdentifiers = lastAppliedItemIdentifiers.filter { liveIDs.contains($0.key) }
        pendingMoveReveal = pendingMoveReveal.filter { liveIDs.contains($0.key) }
        pendingMoveItemIdentifiers = pendingMoveItemIdentifiers.filter { liveIDs.contains($0.key) }
        runtimeStatuses = runtimeStatuses.filter { liveIDs.contains($0.key) }
        for (id, task) in pendingApplyTasks where !liveIDs.contains(id) {
            task.cancel()
            pendingApplyTasks[id] = nil
            pendingApplyActions[id] = nil
        }

        let presentItems = appState.itemManager.itemCache.managedItems
        let presentIdentifiers = Set(presentItems.map(\.tag.tagIdentifier))
        let presentIdentifierBases = Dictionary(
            presentItems.map { ($0.tag.tagIdentifier, $0.tag.stableIdentifierBase) },
            uniquingKeysWith: { first, _ in first }
        )
        let now = Date()
        let plan = priorityPlan(
            for: state,
            presentIdentifiers: presentIdentifiers,
            presentIdentifierBases: presentIdentifierBases,
            now: now
        )
        // Keep the durable layout separate from sections temporarily owned by
        // trigger actions. This includes both reveal and hide actions, and
        // naturally handles partial multi-item ownership.
        let triggerControlledIdentifiers = Set(plan.actions.values.flatMap(\.identifiers))
        // Editor ownership is a separate question from which items currently
        // carry an action, and it has a single writer. An overridden trigger
        // emits no action but still owns its target, so deriving ownership
        // from `plan.actions` here would contradict
        // `refreshControlledIdentifiers` and make the badge flicker depending
        // on which writer ran last.
        refreshControlledIdentifiers()
        appState.itemManager.setTriggerControlledItemIdentifiers(triggerControlledIdentifiers)

        for trigger in triggers where trigger.isEnabled {
            guard !trigger.allItemIdentifiers.isEmpty else { continue }
            guard isAvailable(trigger) else {
                clearApplyState(for: trigger.id)
                setRuntimeStatus(.inactive, for: trigger.id)
                continue
            }

            guard let action = plan.actions[trigger.id] else {
                clearApplyState(for: trigger.id)
                if let names = plan.overriddenBy[trigger.id] {
                    setRuntimeStatus(.overridden(by: names), for: trigger.id)
                } else if plan.unavailableTriggerIDs.contains(trigger.id) {
                    setRuntimeStatus(.unavailable, for: trigger.id)
                } else {
                    setRuntimeStatus(.idle, for: trigger.id)
                }
                continue
            }

            if appliedActionMatches(action, for: trigger.id),
               actionMatchesCurrentPlacement(action, for: trigger, appState: appState)
            {
                pendingApplyTasks[trigger.id]?.cancel()
                pendingApplyTasks[trigger.id] = nil
                pendingApplyActions[trigger.id] = nil
                setRuntimeStatus(action.reveal ? .active : .idle, for: trigger.id)
                continue
            }

            if pendingActionMatches(action, for: trigger.id) {
                pendingApplyTasks[trigger.id]?.cancel()
                pendingApplyTasks[trigger.id] = nil
                pendingApplyActions[trigger.id] = nil
                setRuntimeStatus(.moving, for: trigger.id)
                continue
            }

            if action.identifiers.isEmpty {
                setRuntimeStatus(.unavailable, for: trigger.id)
                continue
            }

            if force {
                if shouldDebounceForcedApply(trigger) {
                    scheduleDebouncedApply(for: trigger.id, action: action)
                } else {
                    pendingApplyTasks[trigger.id]?.cancel()
                    pendingApplyTasks[trigger.id] = nil
                    pendingApplyActions[trigger.id] = nil
                    apply(trigger, action: action)
                }
            } else {
                scheduleDebouncedApply(for: trigger.id, action: action)
            }
        }
    }

    /// Schedules a debounced apply, re-checking the live state when the
    /// debounce elapses so a decision that flipped back is never acted on.
    /// The settle interval is per-condition (long for battery thresholds,
    /// short for discrete sources) so app/network/focus triggers stay
    /// responsive.
    func scheduleDebouncedApply(for triggerID: UUID, action: TriggerPriorityAction) {
        if pendingApplyTasks[triggerID] != nil,
           pendingApplyActions[triggerID] == action
        {
            setRuntimeStatus(.settling, for: triggerID)
            return
        }
        let replacedPendingApply = pendingApplyTasks[triggerID] != nil
        pendingApplyTasks[triggerID]?.cancel()
        pendingApplyTasks[triggerID] = nil
        pendingApplyActions[triggerID] = nil
        guard let queuedTrigger = triggers.first(where: { $0.id == triggerID }) else { return }

        let settle = settleInterval(for: queuedTrigger)
        setRuntimeStatus(.settling, for: triggerID)
        let scheduledAt = Date()
        let replaceText = replacedPendingApply ? "replaced pending; " : ""
        diagLog.debug(
            "Trigger \(queuedTrigger.displayName) \(replaceText)queued pending apply for \(formattedDuration(settle))"
        )
        pendingApplyActions[triggerID] = action
        pendingApplyTasks[triggerID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self else { return }
            self.pendingApplyTasks[triggerID] = nil
            self.pendingApplyActions[triggerID] = nil

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
            let presentItems = self.appState?.itemManager.itemCache.managedItems ?? []
            let presentIdentifiers = Set(presentItems.map(\.tag.tagIdentifier))
            let presentIdentifierBases = Dictionary(
                presentItems.map { ($0.tag.tagIdentifier, $0.tag.stableIdentifierBase) },
                uniquingKeysWith: { first, _ in first }
            )
            let plan = self.priorityPlan(
                for: self.evaluationState,
                presentIdentifiers: presentIdentifiers,
                presentIdentifierBases: presentIdentifierBases
            )
            let triggerControlledIdentifiers = Set(plan.actions.values.flatMap(\.identifiers))
            self.refreshControlledIdentifiers()
            self.appState?.itemManager.setTriggerControlledItemIdentifiers(triggerControlledIdentifiers)
            guard let action = plan.actions[triggerID] else {
                self.clearApplyState(for: triggerID)
                if let names = plan.overriddenBy[triggerID] {
                    self.setRuntimeStatus(.overridden(by: names), for: triggerID)
                    self.diagLog.debug(
                        "Trigger \(trigger.displayName) pending apply expired after "
                            + "\(self.formattedElapsed(since: scheduledAt)); overridden by \(names.joined(separator: ", "))"
                    )
                } else {
                    self.setRuntimeStatus(plan.unavailableTriggerIDs.contains(triggerID) ? .unavailable : .idle, for: triggerID)
                }
                self.diagLog.debug(
                    "Trigger \(trigger.displayName) pending apply expired after "
                        + "\(self.formattedElapsed(since: scheduledAt)); no priority action remains"
                )
                return
            }
            guard !(self.appliedActionMatches(action, for: triggerID)
                && self.appState.map { self.actionMatchesCurrentPlacement(action, for: trigger, appState: $0) } == true)
            else {
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
    func apply(_ trigger: MenuBarItemTrigger, action: TriggerPriorityAction) {
        guard let appState else { return }
        let presentIDs = Set(appState.itemManager.itemCache.managedItems.map(\.tag.tagIdentifier))
        let targets = action.identifiers.filter(presentIDs.contains)
        guard !targets.isEmpty else {
            setRuntimeStatus(.unavailable, for: trigger.id)
            return
        }

        pendingMoveReveal[trigger.id] = action.reveal
        pendingMoveItemIdentifiers[trigger.id] = Set(targets)
        setRuntimeStatus(.moving, for: trigger.id)

        let section = action.reveal ? trigger.revealSection : trigger.hideSection
        diagLog.debug("Trigger \(trigger.displayName) reveal=\(action.reveal); moving \(targets.count) item(s) to \(section.logString)")
        enqueueMoves(for: trigger, action: TriggerPriorityAction(reveal: action.reveal, identifiers: targets), to: section)
    }

    /// Returns whether a queued move still matches the current trigger config
    /// and current system state.
    func queuedMoveIsCurrent(for queuedTrigger: MenuBarItemTrigger, action queuedAction: TriggerPriorityAction) -> Bool {
        guard
            let current = triggers.first(where: { $0.id == queuedTrigger.id }),
            current == queuedTrigger,
            current.isEnabled,
            isAvailable(current)
        else {
            return false
        }

        let presentItems = appState?.itemManager.itemCache.managedItems ?? []
        let presentIDs = Set(presentItems.map(\.tag.tagIdentifier))
        let presentIdentifierBases = Dictionary(
            presentItems.map { ($0.tag.tagIdentifier, $0.tag.stableIdentifierBase) },
            uniquingKeysWith: { first, _ in first }
        )
        let plan = priorityPlan(
            for: evaluationState,
            presentIdentifiers: presentIDs,
            presentIdentifierBases: presentIdentifierBases
        )
        guard let currentAction = plan.actions[current.id] else { return false }
        return currentAction.reveal == queuedAction.reveal && currentAction.identifierSet == queuedAction.identifierSet
    }

    func moveOptions(for trigger: MenuBarItemTrigger) -> MenuBarItemManager.MoveOptions {
        let isFrontmostDriven = trigger.allConditions.contains { $0.kind == .frontmostApp }
        if isFrontmostDriven {
            return .init(
                requiredInputPause: .seconds(1),
                inputPauseTimeout: .seconds(3),
                watchdogTimeout: .seconds(2),
                maxMoveAttempts: 3,
                hideCursorAcrossAttempts: false
            )
        }
        return .init(
            requiredInputPause: .milliseconds(50),
            inputPauseTimeout: nil,
            watchdogTimeout: nil,
            maxMoveAttempts: 8,
            hideCursorAcrossAttempts: true
        )
    }

    /// Appends a batch of moves to the serial move chain so only one move
    /// runs at a time, app-wide, regardless of how many triggers fire. Each
    /// queued batch revalidates immediately before moving, because frontmost
    /// app changes can enqueue opposite moves while an earlier synthetic drag
    /// is still waiting behind the chain.
    func enqueueMoves(
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
            var options = moveOptions(for: trigger)
            options.shouldProceed = { [weak self] in
                self?.queuedMoveIsCurrent(for: trigger, action: action) == true
            }
            var movedAnyItem = false
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
                // Revalidate both here and inside every move attempt. The
                // outer check avoids entering the engine for stale work; the
                // callback stops work that becomes stale while it is waiting.
                guard self.queuedMoveIsCurrent(for: trigger, action: action) else {
                    self.clearPendingMove(for: trigger.id)
                    self.refreshRuntimeStatus(for: trigger.id)
                    return
                }
                let result = await itemManager.moveItem(
                    withTagIdentifier: identifier,
                    toSection: section,
                    options: options
                )
                guard self.queuedMoveIsCurrent(for: trigger, action: action) else {
                    self.diagLog.debug(
                        "Stopping superseded trigger move for \(trigger.displayName) after "
                            + "\(self.formattedElapsed(since: itemMoveStartedAt))"
                    )
                    if self.pendingActionMatches(action, for: trigger.id) {
                        self.clearPendingMove(for: trigger.id)
                    }
                    self.refreshRuntimeStatus(for: trigger.id)
                    return
                }
                switch result {
                case .moved:
                    movedAnyItem = true
                    self.diagLog.debug(
                        "Trigger \(trigger.displayName) move for \(identifier) finished with \(result) in "
                            + "\(self.formattedElapsed(since: itemMoveStartedAt))"
                    )
                    continue
                case .alreadyInSection:
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
            self.notifyRevealIfNeeded(
                for: trigger,
                action: action,
                movedAnyItem: movedAnyItem
            )
            self.finishPendingMove(for: trigger, action: action, applied: true, retry: false)
        }
    }

    /// Posts a reveal notification only after a physical move has completed.
    /// An already-visible item, a deferred move, or a failed move is not a
    /// reveal transition and must not tell the user that it was moved.
    func notifyRevealIfNeeded(
        for trigger: MenuBarItemTrigger,
        action: TriggerPriorityAction,
        movedAnyItem: Bool
    ) {
        guard action.reveal,
              movedAnyItem,
              trigger.notifyOnReveal,
              lastAppliedReveal[trigger.id] != true,
              let appState
        else { return }

        let itemName = trigger.itemDisplayName.isEmpty ? "an item" : trigger.itemDisplayName
        appState.userNotificationManager.requestAuthorization()
        appState.userNotificationManager.addRequest(
            with: .triggerFired,
            title: trigger.displayName,
            body: "Revealed \(itemName)."
        )
    }

    func finishPendingMove(
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

    /// Returns whether every target in an applied action is physically in the
    /// section the trigger currently requests. The Boolean/identifier memo is
    /// only a record of a past move; it is not proof that a user, macOS, or a
    /// different layout operation has not moved the icon since then.
    func actionMatchesCurrentPlacement(
        _ action: TriggerPriorityAction,
        for trigger: MenuBarItemTrigger,
        appState: AppState
    ) -> Bool {
        let requestedSection = action.reveal ? trigger.revealSection : trigger.hideSection
        let effectiveSection: MenuBarSection.Name? = switch requestedSection {
        case .visible, .hidden:
            requestedSection
        case .alwaysHidden:
            if !appState.settings.advanced.enableAlwaysHiddenSection {
                // moveItem intentionally falls back to Hidden while this
                // section is disabled. The Advanced-settings subscription
                // forces a re-evaluation when it becomes available.
                .hidden
            } else if appState.menuBarManager.controlItem(withName: .alwaysHidden)?.window != nil {
                .alwaysHidden
            } else {
                // The section is configured but its control item has not
                // appeared yet. Keep retrying instead of memoizing the
                // temporary Hidden fallback as the requested destination.
                nil
            }
        }

        guard let effectiveSection else { return false }
        let identifiersInSection = Set(
            appState.itemManager.itemCache[effectiveSection].map(\.tag.tagIdentifier)
        )
        return action.identifierSet.isSubset(of: identifiersInSection)
    }

    /// Runs every distinct script referenced by an enabled script-result
    /// condition (when the feature is on), updating cached outcomes and
    /// re-evaluating when any result changes.
    func runScriptsIfNeeded() {
        guard featureFlags.isEnabled(.scriptResult) else { return }
        if isRunningScripts {
            scriptsNeedRefresh = true
            return
        }
        scriptsNeedRefresh = false

        // Collect distinct, non-empty script paths in use by enabled triggers.
        var expectedOutputsByPath = [String: Set<String>]()
        for trigger in triggers where trigger.isEnabled {
            for condition in trigger.allConditions {
                if case let .scriptResult(path, expectedOutput) = condition {
                    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        expectedOutputsByPath[trimmed, default: []].insert(expectedOutput)
                    }
                }
            }
        }
        let paths = Set(expectedOutputsByPath.keys)

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

            var changed = removedAny
            for path in paths {
                let outcome = await TriggerScriptRunner.run(
                    path: path,
                    expectedOutputs: expectedOutputsByPath[path] ?? []
                )
                let resolved = outcome ?? ScriptOutcome(exitCode: -1, output: "")
                if self.scriptOutcomes[path] != resolved {
                    self.scriptOutcomes[path] = resolved
                    changed = true
                }
            }

            self.isRunningScripts = false
            if self.scriptsNeedRefresh {
                self.scriptsNeedRefresh = false
                self.runScriptsIfNeeded()
                return
            }
            if changed {
                self.evaluate(for: self.evaluationState, force: false)
            }
        }
    }

    /// Tells the image cache whether any enabled trigger needs blink
    /// detection running, so it is not tied to the reveal setting alone.
    func updateAttentionDetectionDemand() {
        guard let appState else { return }
        let required = featureFlags.isEnabled(.attentionSeeking) && triggers.contains { trigger in
            trigger.isEnabled && trigger.allConditions.contains { condition in
                if case let .itemSeekingAttention(id) = condition {
                    return !id.isEmpty
                }
                return false
            }
        }
        guard appState.imageCache.isAttentionDetectionRequired != required else { return }
        appState.imageCache.isAttentionDetectionRequired = required
    }

    func refreshImageHashesIfNeeded() {
        guard featureFlags.isEnabled(.imageComparison) else { return }
        if isRefreshingImages {
            imagesNeedRefresh = true
            return
        }
        imagesNeedRefresh = false

        var ids = Set<String>()
        for trigger in triggers where trigger.isEnabled {
            for condition in trigger.allConditions {
                if case let .imageChanged(itemIdentifier, _, _, _, _) = condition, !itemIdentifier.isEmpty {
                    ids.insert(itemIdentifier)
                }
            }
        }

        let removed = Set(imageHashes.keys).subtracting(ids)
        let removedExact = Set(exactImageHashes.keys).subtracting(ids)
        let removedAny = !removed.isEmpty || !removedExact.isEmpty
        for id in removed {
            imageHashes[id] = nil
        }
        for id in removedExact {
            exactImageHashes[id] = nil
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

            var changed = removedAny
            for id in ids {
                guard let fingerprints = await self.currentImageFingerprints(forItemIdentifier: id) else {
                    if self.imageHashes[id] != nil || self.exactImageHashes[id] != nil {
                        self.imageHashes[id] = nil
                        self.exactImageHashes[id] = nil
                        changed = true
                    }
                    continue
                }
                if self.imageHashes[id] != fingerprints.perceptual
                    || self.exactImageHashes[id] != fingerprints.exact
                {
                    self.imageHashes[id] = fingerprints.perceptual
                    self.exactImageHashes[id] = fingerprints.exact
                    changed = true
                }
            }
            self.isRefreshingImages = false
            if self.imagesNeedRefresh {
                self.imagesNeedRefresh = false
                self.refreshImageHashesIfNeeded()
                return
            }
            if changed {
                self.evaluate(for: self.evaluationState, force: false)
            }
        }
    }

    /// Captures the watched item's window and returns both comparison hashes.
    private func currentImageFingerprints(
        forItemIdentifier id: String
    ) async -> (perceptual: UInt64, exact: UInt64)? {
        guard
            let image = await currentImage(forItemIdentifier: id),
            let perceptual = ImageHashing.averageHash(image),
            let exact = ImageHashing.exactHash(image)
        else {
            return nil
        }
        return (perceptual, exact)
    }

    /// Captures the watched item's current window image.
    private func currentImage(forItemIdentifier id: String) async -> CGImage? {
        guard
            let appState,
            let item = appState.itemManager.itemCache.managedItems.first(where: { $0.tag.tagIdentifier == id })
        else {
            return nil
        }

        return await ScreenCapture.captureWindowAsync(with: item.windowID)
            ?? ScreenCapture.captureWindow(with: item.windowID)
    }

    /// Captures both the runtime hash and a compact settings preview.
    func captureImageReference(forItemIdentifier id: String) async -> ImageComparisonReference? {
        guard
            let image = await currentImage(forItemIdentifier: id),
            let perceptualHash = ImageHashing.averageHash(image),
            let exactHash = ImageHashing.exactHash(image)
        else {
            return nil
        }
        let imageData = NSBitmapImageRep(cgImage: image).representation(
            using: .png,
            properties: [:]
        )
        return ImageComparisonReference(
            perceptualHash: perceptualHash,
            exactHash: exactHash,
            imageData: imageData
        )
    }
}
