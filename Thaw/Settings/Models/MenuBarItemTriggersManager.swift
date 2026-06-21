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
            runScriptsIfNeeded()
            refreshImageHashesIfNeeded()
            scheduleEvaluation()
        }
    }

    /// Per-source feature flags, also surfaced in the Developer pane.
    let featureFlags = TriggerFeatureFlagsManager()

    /// The shared app state.
    private weak var appState: AppState?

    /// Monitors the aggregated system state.
    let systemMonitor = SystemStateMonitor()

    /// The reveal decision currently reflected in each target item's
    /// placement, used to skip redundant moves.
    private var lastAppliedReveal = [UUID: Bool]()

    /// Per-trigger debounced apply tasks. A flipped decision only moves its
    /// item after the new state has held for ``flipDebounce``.
    private var pendingApplyTasks = [UUID: Task<Void, Never>]()

    /// How long a flipped decision must hold before the item is moved.
    private let flipDebounce: Duration = .seconds(6)

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

    /// Whether the trigger's target item is currently placed in its reveal
    /// section (i.e. the trigger last revealed it).
    func isCurrentlyRevealed(_ trigger: MenuBarItemTrigger) -> Bool {
        lastAppliedReveal[trigger.id] == true
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
        pendingApplyTasks[id]?.cancel()
        pendingApplyTasks[id] = nil
    }

    /// Removes the triggers at the given offsets.
    func remove(atOffsets offsets: IndexSet) {
        let removedIDs = offsets.compactMap { triggers.indices.contains($0) ? triggers[$0].id : nil }
        triggers.remove(atOffsets: offsets)
        for id in removedIDs {
            lastAppliedReveal[id] = nil
            pendingApplyTasks[id]?.cancel()
            pendingApplyTasks[id] = nil
        }
    }

    /// Replaces the trigger sharing the given id, if present.
    func update(_ trigger: MenuBarItemTrigger) {
        guard let index = triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        triggers[index] = trigger
    }

    // MARK: - Evaluation

    /// Schedules a debounced forced evaluation against the current state.
    private func scheduleEvaluation() {
        debouncedEvaluationTask?.cancel()
        debouncedEvaluationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
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
        for (id, task) in pendingApplyTasks where !liveIDs.contains(id) {
            task.cancel()
            pendingApplyTasks[id] = nil
        }

        let presentIdentifiers = Set(appState.itemManager.itemCache.managedItems.map(\.tag.tagIdentifier))

        let now = Date()
        for trigger in triggers where trigger.isEnabled {
            guard !trigger.allItemIdentifiers.isEmpty else { continue }
            guard isAvailable(trigger) else { continue }

            // Skip without recording when none of the target items are present
            // yet (e.g. their app hasn't launched), so the trigger re-applies
            // once an item appears rather than getting stuck as "applied".
            guard trigger.allItemIdentifiers.contains(where: presentIdentifiers.contains) else { continue }

            let triggerState = effectiveState(for: trigger, base: state)
            let reveal = trigger.shouldReveal(state: triggerState, now: now)

            if lastAppliedReveal[trigger.id] == reveal {
                pendingApplyTasks[trigger.id]?.cancel()
                pendingApplyTasks[trigger.id] = nil
                continue
            }

            if force {
                if shouldDebounceForcedApply(trigger) {
                    scheduleDebouncedApply(for: trigger.id)
                } else {
                    pendingApplyTasks[trigger.id]?.cancel()
                    pendingApplyTasks[trigger.id] = nil
                    apply(trigger, reveal: reveal)
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

    /// Schedules a debounced apply, re-checking the live state when the
    /// debounce elapses so a decision that flipped back is never acted on.
    /// The settle interval is per-condition (long for battery thresholds,
    /// short for discrete sources) so app/network/focus triggers stay
    /// responsive.
    private func scheduleDebouncedApply(for triggerID: UUID) {
        guard pendingApplyTasks[triggerID] == nil else { return }
        // Use the most conservative (longest) settle across all conditions so
        // a jittery source (e.g. battery) still absorbs flapping.
        let settle: Duration = {
            guard let trigger = triggers.first(where: { $0.id == triggerID }) else { return flipDebounce }
            if let override = trigger.settleSecondsOverride, override > 0 {
                return .seconds(override)
            }
            return trigger.allConditions.map(\.kind.settleInterval).max() ?? flipDebounce
        }()
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
                return
            }
            let state = self.effectiveState(for: trigger, base: self.evaluationState)
            let reveal = trigger.shouldReveal(state: state)
            guard self.lastAppliedReveal[triggerID] != reveal else { return }
            self.apply(trigger, reveal: reveal)
        }
    }

    /// Records the reveal decision as applied and moves the target item.
    ///
    /// Does nothing (and does not record the decision) when the target item
    /// isn't currently present, so the trigger re-applies once it appears.
    private func apply(_ trigger: MenuBarItemTrigger, reveal: Bool) {
        guard let appState else { return }
        let presentIDs = Set(appState.itemManager.itemCache.managedItems.map(\.tag.tagIdentifier))
        let targets = trigger.allItemIdentifiers.filter(presentIDs.contains)
        guard !targets.isEmpty else { return }

        let wasRevealed = lastAppliedReveal[trigger.id] == true
        lastAppliedReveal[trigger.id] = reveal

        // Notify on the transition into the revealed state.
        if reveal, !wasRevealed, trigger.notifyOnReveal {
            let itemName = trigger.itemDisplayName.isEmpty ? "an item" : trigger.itemDisplayName
            appState.userNotificationManager.requestAuthorization()
            appState.userNotificationManager.addRequest(
                with: .triggerFired,
                title: trigger.displayName,
                body: "Revealed \(itemName)."
            )
        }

        let section = reveal ? trigger.revealSection : trigger.hideSection
        diagLog.debug("Trigger \(trigger.displayName) reveal=\(reveal); moving \(targets.count) item(s) to \(section.logString)")
        enqueueMoves(for: trigger, reveal: reveal, identifiers: targets, to: section)
    }

    /// Returns whether a queued move still matches the current trigger config
    /// and current system state.
    private func queuedMoveIsCurrent(for queuedTrigger: MenuBarItemTrigger, reveal queuedReveal: Bool) -> Bool {
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
        let state = effectiveState(for: current, base: evaluationState)
        return current.shouldReveal(state: state) == queuedReveal
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
        reveal: Bool,
        identifiers: [String],
        to section: MenuBarSection.Name
    ) {
        let previous = moveChain
        moveChain = Task { @MainActor [weak self] in
            _ = await previous.value
            guard let self, let itemManager = self.appState?.itemManager else { return }
            guard self.queuedMoveIsCurrent(for: trigger, reveal: reveal) else {
                self.diagLog.debug("Skipping stale trigger move for \(trigger.displayName)")
                return
            }
            let options = self.moveOptions(for: trigger)
            for identifier in identifiers {
                guard self.queuedMoveIsCurrent(for: trigger, reveal: reveal) else {
                    self.diagLog.debug("Stopping stale trigger move batch for \(trigger.displayName)")
                    return
                }
                await itemManager.moveItem(
                    withTagIdentifier: identifier,
                    toSection: section,
                    requiredInputPause: options.requiredInputPause,
                    inputPauseTimeout: options.inputPauseTimeout,
                    watchdogTimeout: options.watchdogTimeout,
                    maxMoveAttempts: options.maxMoveAttempts,
                    hideCursorAcrossAttempts: options.hideCursorAcrossAttempts,
                    shouldProceed: { [weak self] in
                        self?.queuedMoveIsCurrent(for: trigger, reveal: reveal) ?? false
                    }
                )
            }
        }
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
