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
    var runtimeStatuses = [UUID: MenuBarItemTriggerRuntimeStatus]()

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
    weak var appState: AppState?

    /// Monitors the aggregated system state.
    let systemMonitor = SystemStateMonitor()

    /// The reveal decision currently reflected in each target item's
    /// placement, used to skip redundant moves.
    var lastAppliedReveal = [UUID: Bool]()

    /// Target identifiers included in the most recently applied move.
    var lastAppliedItemIdentifiers = [UUID: Set<String>]()

    /// Reveal decisions with an in-flight move queued. These are not yet
    /// reflected in the menu bar, but suppress duplicate queueing while the
    /// move chain catches up.
    var pendingMoveReveal = [UUID: Bool]()

    /// Target identifiers included in a queued or in-flight move.
    var pendingMoveItemIdentifiers = [UUID: Set<String>]()

    /// Per-trigger debounced apply tasks. A flipped decision only moves its
    /// item after the new state has held for the condition's settle interval.
    var pendingApplyTasks = [UUID: Task<Void, Never>]()

    /// The exact decision/targets each settle task is waiting to apply. An
    /// unrelated SystemState publication must not restart an identical wait.
    var pendingApplyActions = [UUID: TriggerPriorityAction]()

    /// Fallback settle when a trigger has no condition-specific interval.
    private let fallbackSettleInterval: Duration = .seconds(1)

    /// True while loading from defaults; suppresses writeback.
    private var suppressPersist = false

    @ObservationIgnored
    var cancellables = Set<AnyCancellable>()

    /// Observation of the item cache, replacing the Combine `$itemCache`
    /// subscription this used before `MenuBarItemManager` became @Observable.
    @ObservationIgnored
    var itemCacheObservationTask: Task<Void, Never>?

    /// Observation of the Always-Hidden capability flag.
    @ObservationIgnored
    var alwaysHiddenObservationTask: Task<Void, Never>?

    /// Debounced forced-evaluation task, restarted on each edit.
    private var debouncedEvaluationTask: Task<Void, Never>?

    /// Cached results of script-result conditions, keyed by script path,
    /// injected into the system state at evaluation time.
    var scriptOutcomes = [String: ScriptOutcome]()

    /// Guards against overlapping script-run passes.
    var isRunningScripts = false
    var scriptsNeedRefresh = false

    /// Cached perceptual hashes of watched items for image-comparison
    /// conditions, keyed by tag identifier, injected into the system state.
    var imageHashes = [String: UInt64]()

    /// Exact pixel hashes captured in the same pass as ``imageHashes``.
    var exactImageHashes = [String: UInt64]()

    /// Guards against overlapping image-capture passes.
    var isRefreshingImages = false
    var imagesNeedRefresh = false

    /// Serializes all trigger-driven item moves. Each batch awaits the
    /// previous one so synthetic-drag moves never overlap — overlapping
    /// moves desync the move engine's cursor hide/show and can strand items.
    /// Starts as an already-completed no-op task: an empty body is the
    /// chain's "nothing is running yet" sentinel, and every batch awaits
    /// it before beginning.
    var moveChain = Task<Void, Never> { /* intentionally empty */ }

    let diagLog = DiagLog(category: "MenuBarItemTriggers")

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
    var evaluationState: SystemState {
        var state = systemMonitor.state
        state.scriptOutcomes = scriptOutcomes
        state.imageHashes = imageHashes
        state.exactImageHashes = exactImageHashes
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
    func scheduleEvaluation(after delay: Duration = .milliseconds(300)) {
        debouncedEvaluationTask?.cancel()
        debouncedEvaluationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.evaluate(for: self.evaluationState, force: true)
        }
    }

    /// Whether all of the trigger's conditions are currently available
    /// (each condition's feature flag is enabled, or it is an
    /// always-available power condition).
    func isAvailable(_ trigger: MenuBarItemTrigger) -> Bool {
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

    private func effectiveState(for trigger: MenuBarItemTrigger, base state: SystemState) -> SystemState {
        guard trigger.allConditions.contains(where: { $0.kind == .frontmostApp }) else {
            return state
        }

        var state = state
        state.frontmostAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return state
    }

    func shouldDebounceForcedApply(_ trigger: MenuBarItemTrigger) -> Bool {
        trigger.allConditions.contains { $0.kind == .frontmostApp }
    }

    func settleInterval(for trigger: MenuBarItemTrigger) -> Duration {
        if let override = trigger.settleSecondsOverride {
            return .seconds(max(0, override))
        }
        // Use the most conservative (longest) settle across all conditions so
        // a jittery source (e.g. battery) still absorbs flapping.
        return trigger.allConditions.map(\.kind.settleInterval).max() ?? fallbackSettleInterval
    }

    func formattedDuration(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        return formattedSeconds(seconds)
    }

    func formattedElapsed(since start: Date) -> String {
        formattedSeconds(Date().timeIntervalSince(start))
    }

    private func formattedSeconds(_ seconds: TimeInterval) -> String {
        if seconds >= 10 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.3fs", seconds)
    }

    func appliedActionMatches(_ action: TriggerPriorityAction, for triggerID: UUID) -> Bool {
        lastAppliedReveal[triggerID] == action.reveal &&
            lastAppliedItemIdentifiers[triggerID] == action.identifierSet
    }

    func pendingActionMatches(_ action: TriggerPriorityAction, for triggerID: UUID) -> Bool {
        pendingMoveReveal[triggerID] == action.reveal &&
            pendingMoveItemIdentifiers[triggerID] == action.identifierSet
    }

    func clearPendingMove(for triggerID: UUID) {
        pendingMoveReveal[triggerID] = nil
        pendingMoveItemIdentifiers[triggerID] = nil
    }

    func clearApplyState(for triggerID: UUID) {
        pendingApplyTasks[triggerID]?.cancel()
        pendingApplyTasks[triggerID] = nil
        pendingApplyActions[triggerID] = nil
        clearPendingMove(for: triggerID)
        lastAppliedReveal[triggerID] = nil
        lastAppliedItemIdentifiers[triggerID] = nil
    }

    func setRuntimeStatus(_ status: MenuBarItemTriggerRuntimeStatus, for triggerID: UUID) {
        guard runtimeStatuses[triggerID] != status else { return }
        runtimeStatuses[triggerID] = status
    }

    func refreshRuntimeStatus(for triggerID: UUID) {
        guard let trigger = triggers.first(where: { $0.id == triggerID }) else {
            runtimeStatuses[triggerID] = nil
            return
        }
        setRuntimeStatus(runtimeStatus(for: trigger), for: triggerID)
    }

    // MARK: - Scripts

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
