//
//  MenuBarItemTriggersManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Collections
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
@Observable
final class MenuBarItemTriggersManager {
    /// Whether mutations should be written to the app's shared defaults.
    /// Tests disable this so fixture triggers can never replace the user's
    /// real automation rules.
    private let persistenceEnabled: Bool

    /// The user's configured triggers.
    var triggers: [MenuBarItemTrigger] {
        didSet {
            refreshControlledIdentifiers()
            guard !suppressPersist else { return }
            if persistenceEnabled {
                persist()
            }
            // Preserve applied state for surviving triggers. The next
            // evaluation compares the complete action (decision + targets),
            // so a meaningful edit still re-applies, while a name or
            // unrelated-trigger edit cannot manufacture a new reveal
            // transition or duplicate notification.
            let liveIDs = Set(triggers.map(\.id))
            lastAppliedReveal = lastAppliedReveal.filter { liveIDs.contains($0.key) }
            lastAppliedItemIdentifiers = lastAppliedItemIdentifiers.filter { liveIDs.contains($0.key) }
            pendingMoveReveal = pendingMoveReveal.filter { liveIDs.contains($0.key) }
            pendingMoveItemIdentifiers = pendingMoveItemIdentifiers.filter { liveIDs.contains($0.key) }
            runtimeStatuses = runtimeStatuses.filter { liveIDs.contains($0.key) }
            let oldTriggersByID = Dictionary(
                oldValue.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let changedIDs = Set(triggers.compactMap { trigger in
                oldTriggersByID[trigger.id] == trigger ? nil : trigger.id
            })
            for (id, task) in pendingApplyTasks where !liveIDs.contains(id) || changedIDs.contains(id) {
                task.cancel()
                pendingApplyTasks[id] = nil
                pendingApplyActions[id] = nil
            }
            runScriptsIfNeeded()
            refreshImageHashesIfNeeded()
            updateAttentionDetectionDemand()
            scheduleEvaluation()
        }
    }

    /// Runtime apply/move status for each trigger, surfaced in the settings UI.
    private(set) var runtimeStatuses = [UUID: MenuBarItemTriggerRuntimeStatus]()

    /// Exact live identifiers currently owned by enabled, available triggers.
    ///
    /// A stored property, deliberately: the layout editor's item views read
    /// it per item on every redraw and observe it for changes, and only a
    /// stored `@Observable` property both stays O(1) to read and registers a
    /// dependency on every access. (A lazily memoized computed property does
    /// neither reliably — a warm cache read touches no observable state.)
    private(set) var controlledIdentifiers = Set<String>()

    /// Per-source feature flags, also surfaced in the Developer pane.
    let featureFlags = TriggerFeatureFlagsManager()

    /// The shared app state.
    @ObservationIgnored
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

    /// The exact decision/targets each settle task is waiting to apply. An
    /// unrelated SystemState publication must not restart an identical wait.
    private var pendingApplyActions = [UUID: TriggerPriorityAction]()

    /// Fallback settle when a trigger has no condition-specific interval.
    private let fallbackSettleInterval: Duration = .seconds(1)

    /// True while loading from defaults; suppresses writeback.
    private var suppressPersist = false

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Observation of the item cache, replacing the Combine `$itemCache`
    /// subscription this used before `MenuBarItemManager` became @Observable.
    @ObservationIgnored
    private var itemCacheObservationTask: Task<Void, Never>?

    /// Observation of the Always-Hidden capability flag.
    @ObservationIgnored
    private var alwaysHiddenObservationTask: Task<Void, Never>?

    /// Debounced forced-evaluation task, restarted on each edit.
    private var debouncedEvaluationTask: Task<Void, Never>?

    /// Cached results of script-result conditions, keyed by script path,
    /// injected into the system state at evaluation time.
    private var scriptOutcomes = [String: ScriptOutcome]()

    /// Guards against overlapping script-run passes.
    private var isRunningScripts = false
    private var scriptsNeedRefresh = false

    /// Cached perceptual hashes of watched items for image-comparison
    /// conditions, keyed by tag identifier, injected into the system state.
    private var imageHashes = [String: UInt64]()

    /// Guards against overlapping image-capture passes.
    private var isRefreshingImages = false
    private var imagesNeedRefresh = false

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
            let dedupedIdentifiers = Array(OrderedSet(identifiers))
            if var action = actions[triggerID], action.reveal == reveal {
                action.identifiers = Array(OrderedSet(action.identifiers + dedupedIdentifiers))
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
        state.itemsSeekingAttention = itemsSeekingAttention
        return state
    }

    init(persistenceEnabled: Bool? = nil) {
        // Thaw's unit tests are hosted inside the app and therefore otherwise
        // share its production UserDefaults domain. Default to an isolated,
        // empty manager whenever XCTest is loaded, including managers created
        // indirectly by AppSettings before an individual test begins.
        let persistenceEnabled = persistenceEnabled ?? (NSClassFromString("XCTestCase") == nil)
        self.persistenceEnabled = persistenceEnabled
        suppressPersist = true
        triggers = persistenceEnabled ? Self.load() : []
        suppressPersist = false
        refreshControlledIdentifiers()
    }

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
        pendingApplyActions[id] = nil
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
            pendingApplyActions[id] = nil
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

    /// Whether all of the trigger's conditions are currently available
    /// (each condition's feature flag is enabled, or it is an
    /// always-available power condition).
    private func isAvailable(_ trigger: MenuBarItemTrigger) -> Bool {
        trigger.allConditions.allSatisfy { condition in
            guard let feature = condition.kind.requiredFeature else { return true }
            return featureFlags.isEnabled(feature)
        }
    }

    /// Recomputes ``controlledIdentifiers`` from the current triggers
    /// and feature flags. Called from `triggers.didSet`, the feature-flag
    /// change handler, the initializer (property observers don't run for an
    /// init assignment), and every evaluation.
    ///
    /// The sole writer of ``controlledIdentifiers``, deliberately. Ownership
    /// means "an enabled, available trigger targets this item" — the same
    /// question ``controllingTrigger(forIdentifier:)`` answers, so the badge,
    /// the tooltip and this predicate cannot disagree. It is *not* the same
    /// as "this item currently carries a plan action": an overridden trigger
    /// emits no action yet still owns its target.
    func refreshControlledIdentifiers() {
        let presentItems = appState?.itemManager.itemCache.managedItems ?? []
        let presentIdentifiers = Set(presentItems.map(\.tag.tagIdentifier))
        let presentIdentifierBases = Dictionary(
            presentItems.map { ($0.tag.tagIdentifier, $0.tag.stableIdentifierBase) },
            uniquingKeysWith: { first, _ in first }
        )
        var identifiers = Set<String>()
        for trigger in triggers where trigger.isEnabled && isAvailable(trigger) {
            for target in trigger.allTargetItems where !target.identifier.isEmpty {
                if let resolved = Self.resolvedPresentIdentifier(
                    for: target.identifier,
                    capturedBaseIdentifier: target.baseIdentifier,
                    presentIdentifiers: presentIdentifiers,
                    presentIdentifierBases: presentIdentifierBases
                ) {
                    identifiers.insert(resolved)
                }
            }
        }
        if identifiers != controlledIdentifiers {
            controlledIdentifiers = identifiers
        }
    }

    /// Whether any enabled trigger owns the given item's placement.
    ///
    /// A plain set-membership test is enough because the resolution already
    /// happened when the set was built: ``refreshControlledIdentifiers``
    /// puts every target through `resolvedPresentIdentifier`, so a legacy
    /// target stored with a `:N` instance suffix and no captured base is
    /// already recorded as the live identifier. Keeping this O(1) matters —
    /// the layout editor calls it per item on every redraw.
    func isControlledByTrigger(identifier: String) -> Bool {
        !identifier.isEmpty && controlledIdentifiers.contains(identifier)
    }

    /// Base-only compatibility query used by model-level diagnostics/tests.
    /// Item views must use the exact-identifier overload above because a base
    /// cannot distinguish same-title siblings.
    func isControlledByTrigger(baseIdentifier: String) -> Bool {
        controllingTrigger(forBaseIdentifier: baseIdentifier) != nil
    }

    /// The enabled trigger that currently owns the given item's placement,
    /// or `nil` when no trigger targets it.
    ///
    /// An enabled trigger claims its targets as soon as it is configured, not
    /// only while its condition is met (see
    /// `MenuBarItemManager.setTriggerControlledItemIdentifiers`). For as long
    /// as it holds an item, that item's section is the trigger's to decide and
    /// the saved layout is neither consulted for it nor updated from it — so
    /// the layout editor must not present the item as freely placeable.
    ///
    /// Returns the first match in priority order, which is the trigger the
    /// priority plan resolves in favour of.
    func controllingTrigger(forIdentifier identifier: String) -> MenuBarItemTrigger? {
        guard !identifier.isEmpty else { return nil }
        let presentItems = appState?.itemManager.itemCache.managedItems ?? []
        let presentIdentifiers = Set(presentItems.map(\.tag.tagIdentifier))
        let presentIdentifierBases = Dictionary(
            presentItems.map { ($0.tag.tagIdentifier, $0.tag.stableIdentifierBase) },
            uniquingKeysWith: { first, _ in first }
        )
        return triggers.first { trigger in
            guard trigger.isEnabled, isAvailable(trigger) else { return false }
            return trigger.allTargetItems.contains { target in
                guard !target.identifier.isEmpty else { return false }
                return Self.resolvedPresentIdentifier(
                    for: target.identifier,
                    capturedBaseIdentifier: target.baseIdentifier,
                    presentIdentifiers: presentIdentifiers,
                    presentIdentifierBases: presentIdentifierBases
                ) == identifier
            }
        }
    }

    /// Base-only compatibility query. Do not use for a concrete live item.
    func controllingTrigger(forBaseIdentifier baseIdentifier: String) -> MenuBarItemTrigger? {
        guard !baseIdentifier.isEmpty else { return nil }
        let knownBases: Set<String> = [baseIdentifier]
        return triggers.first { trigger in
            guard trigger.isEnabled, isAvailable(trigger) else { return false }
            return trigger.allTargetItems.contains { target in
                target.identifier == baseIdentifier
                    || target.baseIdentifier == baseIdentifier
                    || MenuBarItemTag.resolvedBaseIdentifier(
                        for: target.identifier,
                        knownBaseIdentifiers: knownBases
                    ) == baseIdentifier
            }
        }
    }

    func priorityPlan(
        for state: SystemState,
        presentIdentifiers: Set<String>,
        presentIdentifierBases: [String: String] = [:],
        now: Date = Date()
    ) -> TriggerPriorityPlan {
        var plan = TriggerPriorityPlan()
        var metOwnerByIdentifier = [String: MenuBarItemTrigger]()
        var fallbackCandidates = [(trigger: MenuBarItemTrigger, identifiers: [String])]()

        for trigger in triggers where trigger.isEnabled {
            guard !trigger.allItemIdentifiers.isEmpty, isAvailable(trigger) else { continue }

            var presentTargets = [String]()
            for target in trigger.allTargetItems where !target.identifier.isEmpty {
                guard let resolvedIdentifier = Self.resolvedPresentIdentifier(
                    for: target.identifier,
                    capturedBaseIdentifier: target.baseIdentifier,
                    presentIdentifiers: presentIdentifiers,
                    presentIdentifierBases: presentIdentifierBases
                ), !presentTargets.contains(resolvedIdentifier)
                else { continue }
                presentTargets.append(resolvedIdentifier)
            }
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

    static nonisolated func resolvedPresentIdentifier(
        for configuredIdentifier: String,
        capturedBaseIdentifier: String?,
        presentIdentifiers: Set<String>,
        presentIdentifierBases: [String: String]
    ) -> String? {
        if presentIdentifiers.contains(configuredIdentifier) {
            return configuredIdentifier
        }
        guard let capturedBaseIdentifier else {
            return nil
        }
        let candidates = presentIdentifierBases.compactMap { identifier, base in
            base == capturedBaseIdentifier ? identifier : nil
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// Schedules a debounced apply, re-checking the live state when the
    /// debounce elapses so a decision that flipped back is never acted on.
    /// The settle interval is per-condition (long for battery thresholds,
    /// short for discrete sources) so app/network/focus triggers stay
    /// responsive.
    private func scheduleDebouncedApply(for triggerID: UUID, action: TriggerPriorityAction) {
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
    private func apply(_ trigger: MenuBarItemTrigger, action: TriggerPriorityAction) {
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
    private func queuedMoveIsCurrent(for queuedTrigger: MenuBarItemTrigger, action queuedAction: TriggerPriorityAction) -> Bool {
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

    private func moveOptions(for trigger: MenuBarItemTrigger) -> (
        requiredInputPause: Duration,
        inputPauseTimeout: Duration?,
        watchdogTimeout: Duration?,
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
                    requiredInputPause: options.requiredInputPause,
                    inputPauseTimeout: options.inputPauseTimeout,
                    watchdogTimeout: options.watchdogTimeout,
                    maxMoveAttempts: options.maxMoveAttempts,
                    hideCursorAcrossAttempts: options.hideCursorAcrossAttempts,
                    shouldProceed: { [weak self] in
                        self?.queuedMoveIsCurrent(for: trigger, action: action) == true
                    }
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
    private func notifyRevealIfNeeded(
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

    private func settleInterval(for trigger: MenuBarItemTrigger) -> Duration {
        if let override = trigger.settleSecondsOverride {
            return .seconds(max(0, override))
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

    /// Returns whether every target in an applied action is physically in the
    /// section the trigger currently requests. The Boolean/identifier memo is
    /// only a record of a past move; it is not proof that a user, macOS, or a
    /// different layout operation has not moved the icon since then.
    private func actionMatchesCurrentPlacement(
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
        pendingApplyActions[triggerID] = nil
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

    // MARK: - Image comparison

    /// Captures the current perceptual hash for every watched item used by an
    /// enabled image-comparison condition (when the feature is on), updating
    /// the cache and re-evaluating when any hash changes.
    /// Identifiers of items an attention condition currently reports as
    /// blinking, read straight from the image cache's detector rather than
    /// re-derived here.
    private var itemsSeekingAttention: Set<String> {
        guard featureFlags.isEnabled(.attentionSeeking), let appState else { return [] }
        return Set(appState.imageCache.tagsSeekingAttention.map(\.tagIdentifier))
    }

    /// Tells the image cache whether any enabled trigger needs blink
    /// detection running, so it is not tied to the reveal setting alone.
    private func updateAttentionDetectionDemand() {
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

    private func refreshImageHashesIfNeeded() {
        guard featureFlags.isEnabled(.imageComparison) else { return }
        if isRefreshingImages {
            imagesNeedRefresh = true
            return
        }
        imagesNeedRefresh = false

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

    /// Wrapper that decodes its element if possible, otherwise yields `nil`
    /// instead of failing the whole array decode.
    private struct FailableTrigger: Decodable {
        let value: MenuBarItemTrigger?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            value = try? container.decode(MenuBarItemTrigger.self)
        }
    }

    private static func load() -> [MenuBarItemTrigger] {
        guard let data = Defaults.data(forKey: .menuBarItemTriggers) else {
            return []
        }
        let decoder = JSONDecoder()
        // Healthy path: strict decode of the whole array.
        if let triggers = try? decoder.decode([MenuBarItemTrigger].self, from: data) {
            return repairAndPersistLegacyIdentifiers(in: triggers)
        }
        // A strict decode failed. Recover per element so a single corrupt or
        // forward-incompatible trigger doesn't discard every other trigger —
        // the next mutation would otherwise persist the empty array and make
        // the loss permanent.
        guard let lenient = try? decoder.decode([FailableTrigger].self, from: data) else {
            DiagLog(category: "MenuBarItemTriggers").error(
                "Failed to decode menu bar item triggers; leaving persisted data untouched"
            )
            return []
        }
        let recovered = lenient.compactMap(\.value)
        let dropped = lenient.count - recovered.count
        if dropped > 0 {
            DiagLog(category: "MenuBarItemTriggers").error(
                "Dropped \(dropped) undecodable menu bar item trigger(s); recovered \(recovered.count)"
            )
        }
        return repairAndPersistLegacyIdentifiers(in: recovered)
    }

    /// Repairs persisted trigger targets from before stable base identities
    /// were saved alongside their concrete identifiers.
    ///
    /// The old `battery-item` test fixture is first restored to the real
    /// Control Center Battery identifier. Any legacy first-instance target
    /// whose title does not end in a numeric component can then safely use its
    /// full identifier as its stable namespace/title base. We intentionally
    /// leave identifiers ending in a number alone: that number may be part of
    /// the item's title rather than an instance suffix.
    static func repairingLegacyTestFixtureIdentifiers(
        in triggers: [MenuBarItemTrigger]
    ) -> [MenuBarItemTrigger] {
        let legacyBatteryIdentifier = "battery-item"
        let batteryIdentifier = MenuBarItemTag(
            namespace: .controlCenter,
            title: "Battery"
        ).tagIdentifier

        func repairedTarget(_ target: TriggerTargetItem) -> TriggerTargetItem {
            var repaired = target
            if repaired.identifier == legacyBatteryIdentifier {
                repaired.identifier = batteryIdentifier
                if repaired.displayName.isEmpty || repaired.displayName == legacyBatteryIdentifier {
                    repaired.displayName = "Battery"
                }
            }
            if repaired.baseIdentifier == nil,
               let baseIdentifier = legacyStableBaseIdentifier(for: repaired.identifier)
            {
                repaired.baseIdentifier = baseIdentifier
            }
            return repaired
        }

        return triggers.map { trigger in
            var repaired = trigger
            let primary = repairedTarget(TriggerTargetItem(
                identifier: repaired.itemIdentifier,
                displayName: repaired.itemDisplayName,
                baseIdentifier: repaired.itemBaseIdentifier
            ))
            repaired.itemIdentifier = primary.identifier
            repaired.itemDisplayName = primary.displayName
            repaired.itemBaseIdentifier = primary.baseIdentifier
            repaired.additionalItems = repaired.additionalItems.map(repairedTarget)
            return repaired
        }
    }

    /// The old tag format omits `:0` for the first instance. When an
    /// identifier has no trailing number, it is therefore already its full
    /// namespace/title base. A trailing number remains ambiguous and must be
    /// resolved only from live tag data later.
    private static func legacyStableBaseIdentifier(for identifier: String) -> String? {
        guard
            let namespaceEnd = identifier.firstIndex(of: ":"),
            namespaceEnd < identifier.index(before: identifier.endIndex),
            identifier.index(after: namespaceEnd) < identifier.endIndex,
            let suffixStart = identifier.lastIndex(of: ":")
        else {
            return nil
        }

        let finalComponent = identifier[identifier.index(after: suffixStart)...]
        return Int(finalComponent) == nil ? identifier : nil
    }

    private static func repairAndPersistLegacyIdentifiers(
        in triggers: [MenuBarItemTrigger]
    ) -> [MenuBarItemTrigger] {
        let repaired = repairingLegacyTestFixtureIdentifiers(in: triggers)
        guard repaired != triggers else { return triggers }

        if let data = try? JSONEncoder().encode(repaired) {
            Defaults.set(data, forKey: .menuBarItemTriggers)
            DiagLog(category: "MenuBarItemTriggers").notice(
                "Repaired legacy trigger target identifiers"
            )
        }
        return repaired
    }
}
