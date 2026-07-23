//
//  MenuBarSectionController.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa
import MenuBarModel
import PlatformRuntimeKit

/// The subset of ``RuntimeSessionController`` that ``MenuBarSectionController`` calls into.
/// Exists so tests can substitute a fake and characterize the orchestration in
/// ``MenuBarSectionController`` without touching the real private visibility-restriction
/// assertion.
@MainActor
protocol RuntimeSessionControllering: AnyObject {
    var isHidingAvailable: Bool { get }
    var isHolding: Bool { get }
    @discardableResult
    func apply(sectionAssignment: [String: MenuBarSection.Name], allItems: [MenuBarItem]) -> Bool
    func pulse(sectionAssignment: [String: MenuBarSection.Name], allItems: [MenuBarItem]) -> Bool
    func markExternallyTornDown()
    @discardableResult
    func refreshAvailability() -> Bool
}

extension RuntimeSessionController: RuntimeSessionControllering {}

/// The subset of ``RuntimeModuleController`` that ``MenuBarSectionController`` calls
/// into.
@MainActor
protocol RuntimeModuleControlling: AnyObject {
    @discardableResult
    func apply(hiddenMenuExtraTitles titles: Set<String>) -> Bool
}

extension RuntimeModuleController: RuntimeModuleControlling {}

/// The common shape of ``RuntimeWindowController`` and ``AXItemHider``: both hide
/// items surgically by PID/window and report which PIDs they actually
/// handled, so ``MenuBarSectionController`` can strip them from the next pass. CGS
/// runs first (handles pre-27 macOS where per-item windows exist); AX runs
/// second and catches PIDs CGS could not (gated out on macOS 27 by plan 012,
/// since `AXHidden` isn't settable on hosted menu-bar items there).
@MainActor
protocol RuntimeWindowControlling: AnyObject {
    @discardableResult
    func apply(hiddenPIDs: Set<pid_t>, allItems: [MenuBarItem]) -> Set<pid_t>
    func restoreAll()
}

extension AXItemHider: RuntimeWindowControlling {}

extension RuntimeWindowController: RuntimeWindowControlling {
    @discardableResult
    func apply(hiddenPIDs: Set<pid_t>, allItems _: [MenuBarItem]) -> Set<pid_t> {
        apply(hiddenPIDs: hiddenPIDs)
    }
}

/// The subset of ``RuntimePreferenceStore`` that ``MenuBarSectionController`` calls
/// into.
@MainActor
protocol RuntimePreferenceProviding: AnyObject {
    var hasHiddenItems: Bool { get }
    func readPositions() -> [String: Int]
    func writePositions(_ dict: [String: Int])
    func restoreAll()
    @discardableResult
    func hideItems(_ items: [MenuBarItem]) -> Set<String>
    @discardableResult
    func showItems(_ items: [MenuBarItem], allItems: [MenuBarItem]) -> Set<String>
    @discardableResult
    func lockVisiblePositions(visibleItemKeys: Set<String>, allItems: [MenuBarItem]) -> Set<String>
}

extension RuntimePreferenceStore: RuntimePreferenceProviding {}

extension RuntimePreferenceProviding {
    /// Removes stale Thaw control-item keys from `TrailingItemPreferredPositions`.
    ///
    /// Implemented here (not required on the protocol) so Thaw builds against
    /// published `prk-bin` where ``RuntimePreferenceStore/pruneOrphanedControlItemKeys(currentOwners:)``
    /// is not yet part of the public module interface. Uses only
    /// ``readPositions()`` / ``writePositions(_:)``.
    @discardableResult
    func pruneOrphanedControlItemKeys(currentOwners: Set<String>) -> [String] {
        let positions = readPositions()
        let orphans = positions.keys.filter { key in
            guard let parsed = parseControlItemStatusKey(key),
                  parsed.autosave.hasPrefix(ControlItemIdentifier.autosavePrefix)
            else {
                return false
            }
            return !currentOwners.contains(parsed.owner)
        }
        guard !orphans.isEmpty else { return [] }
        var updated = positions
        for key in orphans {
            updated.removeValue(forKey: key)
        }
        writePositions(updated)
        return orphans
    }
}

/// Splits a `status:<owner>::<autosave>` preference key into its components.
private func parseControlItemStatusKey(_ key: String) -> (owner: String, autosave: String)? {
    let prefix = "status:"
    guard key.hasPrefix(prefix) else { return nil }
    let body = key.dropFirst(prefix.count)
    guard let separator = body.range(of: "::") else {
        return (owner: "", autosave: String(body))
    }
    return (
        owner: String(body[body.startIndex ..< separator.lowerBound]),
        autosave: String(body[separator.upperBound...])
    )
}

/// The subset of ``PositionHideBackend`` used by the app orchestration.
@MainActor
protocol PositionHideBackending: AnyObject {
    var hasManagedItems: Bool { get }
    var isInDesiredState: Bool { get }
    @discardableResult
    func apply(
        sectionAssignment: [String: MenuBarSection.Name],
        allItems: [MenuBarItem],
        visibleOrder: [MenuBarItem]
    ) -> PositionHideBackend.ApplyResult
    @discardableResult
    func revealAll() -> Bool
    @discardableResult
    func reassert() -> Bool
}

extension PositionHideBackend: PositionHideBackending {}

/// macOS 27 section-based hiding, the authority behind the restored
/// drag-between-sections layout UI.
///
/// macOS 27 removed every legacy mechanism for moving a status item off-screen, so
/// the classic Visible / Hidden / Always-Hidden model is reconstructed here on
/// top of a single source of truth that this object owns:
///
/// - **Section assignment** (``sectionAssignment``): which section each item
///   belongs to, keyed by ``MenuBarItem/uniqueIdentifier`` and persisted. This
///   is what the layout bars render and what drags mutate.
/// - **Temporary reveal** (``revealedSection``): the Hidden / Always-Hidden
///   section currently shown from the Thaw icon or hotkeys. This only changes
///   the live assertion allowlist; persisted assignments stay untouched.
///
/// Third-party status items can be delegated to ``PositionHideBackend``, which
/// moves them to stable off-screen preference bands without re-compositing the
/// bar. System items and unresolved app items remain on
/// ``RuntimeSessionController`` as the reliable assertion fallback.
///
/// Created only on macOS 27+ (see ``MenuBarManager``), so everything it owns is
/// implicitly gated to that OS — macOS 26 keeps its native section machinery.
@MainActor
final class MenuBarSectionController: ObservableObject {
    /// Shared UserDefaults key for the persisted per-section item order
    /// (`[sectionRawValue: [uniqueIdentifier]]`). Uses the same key as
    /// `MenuBarItemManager.savedSectionOrder` so both subsystems read from
    /// and write to a single source of truth — no separate assignment or
    /// order keys needed. On macOS 27 this replaces both the old
    /// `Thaw.simpleSectionAssignment` and `Thaw.simpleSectionOrder` keys.
    private static let orderKey = "MenuBarItemManager.savedSectionOrder"

    /// Legacy UserDefaults key from the binary switch-list era. Read once at
    /// first launch to migrate hidden items into the new assignment map.
    private static let legacyHiddenKey = "Thaw.simpleHiddenItemIdentifiers"

    /// Legacy per-item assignment key from early macOS 27 preview builds.
    private static let oldAssignmentKey = "Thaw.simpleSectionAssignment"

    /// Legacy per-section order key from early macOS 27 preview builds.
    private static let oldOrderKey = "Thaw.simpleSectionOrder"

    weak var appState: AppState?
    let diagLog = DiagLog(category: "MenuBarSectionController")

    /// Section each item is assigned to, keyed by ``MenuBarItem/uniqueIdentifier``.
    /// Entries equal to `.visible` are omitted (the default), so the map only
    /// holds the hidden / always-hidden items. Published so the settings UI and
    /// layout bars reflect changes.
    @Published private(set) var sectionAssignment: [String: MenuBarSection.Name]

    /// Visible-by-authoring items temporarily concealed because the active menu
    /// bar cannot fit them. This is deliberately not persisted: overflow is an
    /// environmental presentation decision, not a layout edit.
    @Published private(set) var overflowHiddenIdentifiers: Set<String> = []

    /// User-chosen left-to-right order of items within each section, set by
    /// layout-bar drags and persisted. The Visible section renders from fresh
    /// AX geometry on macOS 27 so stale saved order cannot drift from the real
    /// menu bar.
    @Published private(set) var sectionItemOrder: [MenuBarSection.Name: [String]]

    /// The currently revealed hidden section, if any. `.hidden` reveals only
    /// Hidden items; `.alwaysHidden` reveals both Hidden and Always-Hidden items.
    @Published private(set) var revealedSection: MenuBarSection.Name?

    /// Whether at least one configured hiding adapter is available. Position
    /// hiding provides third-party coverage even when the private assertion is
    /// absent; the assertion remains required for system/unresolved items.
    @Published private(set) var isHidingAvailable: Bool

    /// Set once the launch-time unavailability warning has been logged, so a
    /// later activation recheck doesn't re-log it every time the app becomes
    /// active.
    private var hasLoggedUnavailableAtLaunch = false

    private var didBecomeActiveObserver: NSObjectProtocol?

    /// Item identifiers temporarily forced visible for a single-item reveal.
    /// Unlike ``revealedSection``, this exposes just the touched item (used by
    /// the Thaw Bar click path on macOS 27) instead of its whole section, so a
    /// click never flashes every hidden icon into the menu bar.
    private var temporarilyRevealedIDs: Set<String> = []
    private var temporaryRevealConcealTasks = [String: Task<Void, Never>]()

    /// The backend that performs the hiding (the private visibility-restriction
    /// assertion).
    private let backend: RuntimeSessionControllering

    /// Whether the assertion is intentionally suspended so the system Clock can
    /// open Notification Center. Recovery and periodic refreshes must treat this
    /// as healthy until the activation bridge restores the current assignment.
    private(set) var isClockActivationBridgeActive = false
    private var clockAssertionRestoreTask: Task<Void, Never>?
    private var clockAssertionRestoreToken: UUID?

    /// Governs Apple Control Center modules (AirDrop / Focus / User / Now Playing
    /// / WiFi / Bluetooth) that the assessment-mode allowlist cannot hide. Items
    /// it owns are hidden via their Control Center preference and kept out of the
    /// backend input.
    private let ccModuleManager: RuntimeModuleControlling

    /// Off-screen CGS window hider. When the experimental window
    /// hiding flag is on, third-party items are hidden by moving their windows
    /// off-screen via CGS instead of the assessment-mode assertion, so hiding one
    /// item no longer reflows the bar and ghosts dynamic neighbors like iStat.
    private let cgsWindowHider: RuntimeWindowControlling

    /// AX-based item hider. On macOS 27 per-item CG windows don't exist, so the
    /// CGS hider cannot operate. This hider sets `AXHidden` on each item's AX
    /// element instead — hiding items
    /// surgically without whole-bar reflow.
    ///
    /// Note: AXHidden is not settable on macOS 27 menu-bar items; this hider is
    /// kept for diagnostics but is effectively a no-op there.
    private let axItemHider: RuntimeWindowControlling

    /// The two surgical passes, in the fixed order `applyExperimentalWindowHiding`
    /// runs them: CGS first, then AX. Both conform to `RuntimeWindowControlling`, but
    /// the orchestration below still calls them by name rather than looping
    /// over this array, because the AX pass carries an extra macOS-version
    /// gate (plan 012) that isn't part of the shared protocol. Exposed so
    /// tests can assert the ordering without duplicating that gating logic.
    var surgicalHiders: [RuntimeWindowControlling] {
        [cgsWindowHider, axItemHider]
    }

    /// Position lock for visible items. On macOS 27 the assessment-mode
    /// assertion re-composites the whole bar, ghosting dynamic neighbors (iStat).
    /// Writing visible items' current positions to `TrailingItemPreferredPositions`
    /// before the assertion fires tells MenuBarAgent to anchor them in place
    /// during reflow, preventing the ghosting.
    private let positionStore: RuntimePreferenceProviding

    /// Primary, flicker-free hiding mechanism for third-party status items.
    /// System modules and items without a resolvable `status:` preference key
    /// remain on the assertion fallback.
    private let positionHideBackend: PositionHideBackending
    private var positionHandledItemIdentifiers = Set<String>()
    private var positionAssertionExcludedItemIdentifiers = Set<String>()

    private var timer: Timer?
    private var boundaryReconciliationTask: Task<Void, Never>?
    var hasPendingRevealOrderSynchronization: Bool {
        boundaryReconciliationTask != nil
    }

    private var lastRefreshSignature: String?
    private var nativeOverflowProbeTask: Task<Void, Never>?
    private var nativeOverflowState = NativeOverflowStateReducer()
    private var pendingNativeOverflowRebalance = false
    private var latestNativeOverflowBounds = [CGDirectDisplayID: [CGRect]]()

    /// Displays where MenuBarAgent has stably reported its native overflow
    /// control. This is presentation state only; authored section assignment
    /// and physical reorderability remain independent.
    @Published private(set) var nativeOverflowDisplayIDs = Set<CGDirectDisplayID>()

    /// Watches `MenuBarAgent`'s preferences for external `TrailingItemPreferredPositions`
    /// changes (macOS 27 only). See ``handleExternalPositionsChange(_:)``.
    private var prefsWatcher: MenuBarAgentPreferencesWatcher?

    /// Observes DND/Assessment-Mode state changes so a torn-down concealment
    /// assertion is re-applied (macOS 27 only). See ``handleAssessmentStateChange()``.
    private var assessmentStateMonitor: AssessmentStateMonitor?

    /// Settle-gates all environment-driven assertion recovery. The driver owns
    /// AppKit notification sources; PlatformRuntimeKit owns recovery policy.
    private var recoveryDriver: MenuBarRecoveryDriver?

    convenience init(appState: AppState) {
        let positionStore = RuntimePreferenceStore()
        self.init(
            appState: appState,
            backend: RuntimeSessionController(),
            ccModuleManager: RuntimeModuleController(),
            cgsWindowHider: RuntimeWindowController(),
            axItemHider: AXItemHider(),
            positionStore: positionStore,
            positionHideBackend: PositionHideBackend(store: positionStore)
        )
    }

    /// Designated initializer. Production code always goes through
    /// ``init(appState:)`` above, which supplies the real collaborators; this
    /// entry point exists so tests can substitute fakes for the five
    /// collaborators and characterize ``MenuBarSectionController``'s instance lifecycle
    /// without touching the private visibility-restriction assertion, Control
    /// Center, CGS, AX, or `TrailingItemPreferredPositions`.
    init(
        appState: AppState?,
        backend: RuntimeSessionControllering,
        ccModuleManager: RuntimeModuleControlling,
        cgsWindowHider: RuntimeWindowControlling,
        axItemHider: RuntimeWindowControlling,
        positionStore: RuntimePreferenceProviding,
        positionHideBackend: PositionHideBackending
    ) {
        self.appState = appState
        let order = Self.loadOrder()
        self.sectionItemOrder = order
        self.sectionAssignment = Self.assignmentFromOrder(
            order,
            alwaysHiddenEnabled: appState?.settings.advanced.isAlwaysHiddenSectionEnabled ?? true
        )
        self.backend = backend
        self.ccModuleManager = ccModuleManager
        self.cgsWindowHider = cgsWindowHider
        self.axItemHider = axItemHider
        self.positionStore = positionStore
        self.positionHideBackend = positionHideBackend
        self.isHidingAvailable = backend.isHidingAvailable || (appState?.settings.advanced.enablePositionHiding ?? false)
        Bridging.logSystemMenuBarWindows()
        diagLog.info("hiding backends: position=\(appState?.settings.advanced.enablePositionHiding ?? false), assertion=\(backend.isHidingAvailable); \(sectionAssignment.count) assigned item(s)")
        logUnavailabilityAtLaunchIfNeeded()

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHidingAvailability()
            }
        }

        configureRecoveryDriver()
        startRuntimeStateObservers()
    }

    isolated deinit {
        timer?.invalidate()
        boundaryReconciliationTask?.cancel()
        nativeOverflowProbeTask?.cancel()
        for task in temporaryRevealConcealTasks.values {
            task.cancel()
        }
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
        prefsWatcher?.stop()
        assessmentStateMonitor?.stop()
        recoveryDriver?.stop()
        clockAssertionRestoreTask?.cancel()
    }

    /// Starts the macOS 27 runtime-state observers: the `MenuBarAgent`
    /// preferences watcher (external order drift) and the DND/Assessment-Mode
    /// state monitor (torn-down concealment assertion). No-op on earlier
    /// systems, where neither the position store nor the assertion exists.
    private func startRuntimeStateObservers() {
        guard appState != nil, #available(macOS 27, *) else { return }

        pruneOrphanedControlItemKeys()

        let watcher = MenuBarAgentPreferencesWatcher(
            readPositions: { [weak self] in self?.positionStore.readPositions() ?? [:] },
            onExternalChange: { [weak self] positions in
                self?.handleExternalPositionsChange(positions)
            }
        )
        watcher.start()
        prefsWatcher = watcher

        let monitor = AssessmentStateMonitor { [weak self] in
            self?.handleAssessmentStateChange()
        }
        monitor.start()
        assessmentStateMonitor = monitor
    }

    /// Suppresses the next `TrailingItemPreferredPositions` file events as
    /// Thaw-authored. Call after structural preferred-position writes so the
    /// prefs watcher does not treat our own reorder as an external change.
    func notePreferredPositionsSelfWrite() {
        prefsWatcher?.noteSelfWrite()
    }

    /// Drops control-item preferred-position keys left in the shared
    /// `TrailingItemPreferredPositions` dictionary by earlier builds and retired
    /// host agents. Only keys owned by an identity other than this running build
    /// are removed, so the live control keys are preserved; this trims the
    /// dictionary MenuBarAgent renormalises and prevents key resolution from ever
    /// matching a stale variant. macOS 27 only — gated by the sole caller
    /// (``startRuntimeStateObservers``), and inert on macOS 26 regardless.
    private func pruneOrphanedControlItemKeys() {
        let owners = Set(
            [
                Bundle.main.bundleIdentifier,
                Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
                Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
                ProcessInfo.processInfo.processName,
            ].compactMap(\.self)
        )
        let pruned = positionStore.pruneOrphanedControlItemKeys(currentOwners: owners)
        if !pruned.isEmpty {
            notePreferredPositionsSelfWrite()
            diagLog.info("pruned \(pruned.count) orphaned control-item position key(s)")
        }
    }

    /// Handles an external change to `TrailingItemPreferredPositions` — one Thaw
    /// did not make itself (`MenuBarAgent` reflow, another manager, `defaults`,
    /// MDM). Re-asserts Thaw's concealment state so a system-driven reflow cannot
    /// leave hidden items on screen.
    ///
    /// This intentionally does **not** auto-drive position reordering. The item
    /// manager's cache / `applySavedLayout` pipeline already owns persisted-order
    /// recovery, including user-drag detection, move cooldowns, assertion settle
    /// windows, and failed-move backoff. Dispatching a second reconcile here would
    /// bypass those guards and can turn MenuBarAgent's own preference rewrites into
    /// a synthetic-drag loop. This observer only schedules settle-gated
    /// concealment recovery; the next cache pass remains the single authority
    /// for order recovery.
    private func handleExternalPositionsChange(_ positions: [String: Int]) {
        // MenuBarAgent renormalizes the entire `TrailingItemPreferredPositions`
        // dictionary during its own reflows, so the watcher fires on churn in
        // keys Thaw does not manage (148-key rewrites). If every concealment
        // authority is still healthy — hidden items still off-screen, assertion
        // still held — there is nothing to recover, and reacting would rewrite
        // the store, which MenuBarAgent normalizes again, sustaining the
        // "reordering that never stops" loop. Only recover on a genuine breach.
        guard !areConcealmentAuthoritiesHealthy else {
            diagLog.debug("external order change is benign (concealment healthy); skipping recovery")
            return
        }
        diagLog.notice("external MenuBarAgent order change (\(positions.count) key(s)); scheduling settled recovery")
        recoveryDriver?.recover(trigger: .externalPositions)
    }

    /// Handles a DND/Assessment-Mode state change. The system may have torn down
    /// or superseded Thaw's concealment assertion; re-check availability and
    /// re-apply the desired concealment so hidden items do not silently reappear.
    private func handleAssessmentStateChange() {
        refreshHidingAvailability()
        recoveryDriver?.recover(trigger: .assessmentState)
    }

    private func configureRecoveryDriver() {
        guard appState != nil, #available(macOS 27, *) else { return }
        recoveryDriver = MenuBarRecoveryDriver(
            environment: .init(
                snapshot: { [weak self] in
                    self?.recoverySnapshot() ?? .init(
                        itemSignature: 0,
                        isControlledHidden: false,
                        screenCount: NSScreen.screens.count
                    )
                },
                desiredHidden: { [weak self] in
                    self?.hasDesiredConcealment ?? false
                },
                isAssertionAlive: { [weak self] in
                    self?.areConcealmentAuthoritiesHealthy ?? false
                },
                repulseAssertion: { [weak self] in
                    self?.repulseRestrictionForRecovery() ?? false
                },
                relockPositions: { [weak self] in
                    self?.relockVisiblePositionsForRecovery() ?? false
                },
                doubleToggle: { [weak self] in
                    self?.doubleToggleRestrictionForRecovery() ?? false
                },
                markTornDown: { [weak self] in
                    guard let self,
                          !self.isClockActivationBridgeActive,
                          self.hasDesiredAssertionRestriction,
                          !self.backend.isHolding
                    else { return }
                    self.backend.markExternallyTornDown()
                }
            )
        )
    }

    private var hasDesiredConcealment: Bool {
        (hasDesiredAssertionRestriction && !isClockActivationBridgeActive) || positionHideBackend.hasManagedItems
    }

    private var hasDesiredAssertionRestriction: Bool {
        assertionAssignmentInput().values.contains {
            $0 == .hidden || $0 == .alwaysHidden
        }
    }

    private var areConcealmentAuthoritiesHealthy: Bool {
        let assertionHealthy = isClockActivationBridgeActive || !hasDesiredAssertionRestriction || backend.isHolding
        let positionHealthy = !positionHideBackend.hasManagedItems || positionHideBackend.isInDesiredState
        return assertionHealthy && positionHealthy
    }

    /// Builds a cheap recovery snapshot from the most recent normal AX cache
    /// pass. The settle probe samples this every 100 ms, so it must never start
    /// another AX enumeration of its own — doing so recreates the main-thread
    /// recache storm that makes menu-bar clicks stop registering.
    private func recoverySnapshot() -> RuntimeRecoveryCoordinator.Snapshot {
        guard let appState else {
            return .init(
                itemSignature: 0,
                isControlledHidden: false,
                screenCount: NSScreen.screens.count
            )
        }
        let items = appState.itemManager.lastOnScreenMenuBarItems.0
        let assertionIdentifiers = isClockActivationBridgeActive ? Set<String>() : Set(
            assertionAssignmentInput().keys.filter {
                !RuntimeModuleController.isGovernable(itemIdentifier: $0)
            }
        )
        let controlledIdentifiers = assertionIdentifiers.union(positionHandledItemIdentifiers)
        return Self.makeRecoverySnapshot(
            items: items,
            controlledIdentifiers: controlledIdentifiers,
            screenCount: NSScreen.screens.count
        )
    }

    static func makeRecoverySnapshot(
        items: [MenuBarItem],
        controlledIdentifiers: Set<String>,
        screenCount: Int
    ) -> RuntimeRecoveryCoordinator.Snapshot {
        var hasher = Hasher()
        for item in items.sorted(by: { lhs, rhs in
            if lhs.windowID != rhs.windowID {
                return lhs.windowID < rhs.windowID
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }) {
            hasher.combine(item.windowID)
            hasher.combine(item.bounds.minX.rounded())
        }

        let hasVisibleControlledItem = items.contains { item in
            item.isOnScreen && controlledIdentifiers.contains(item.uniqueIdentifier)
        }

        return .init(
            itemSignature: hasher.finalize(),
            isControlledHidden: !controlledIdentifiers.isEmpty && !hasVisibleControlledItem,
            screenCount: screenCount
        )
    }

    /// Rung 1: rebuilds the current restriction without first exposing the
    /// concealed items.
    private func repulseRestrictionForRecovery() -> Bool {
        if positionHideBackend.hasManagedItems,
           !positionHideBackend.isInDesiredState
        {
            let didChange = positionHideBackend.reassert()
            if didChange {
                prefsWatcher?.noteSelfWrite()
            }
            return didChange
        }

        return repulseAssertionForRecovery()
    }

    private func repulseAssertionForRecovery() -> Bool {
        guard !isClockActivationBridgeActive,
              let appState,
              hasDesiredAssertionRestriction
        else { return false }
        let assignment = assertionAssignmentInput()
        let didChange = backend.pulse(
            sectionAssignment: assignment,
            allItems: appState.itemManager.itemCache.managedItems
        )
        noteRecoveryRestrictionChange(didChange)
        return didChange
    }

    /// Rung 2: re-locks the current visible-item position keys. This is kept
    /// separate from `refresh()` so recovery does not replay the full hiding
    /// pipeline while MenuBarAgent is settling.
    private func relockVisiblePositionsForRecovery() -> Bool {
        guard let appState else { return false }
        if appState.settings.advanced.enablePositionHiding {
            if positionHideBackend.hasManagedItems,
               !positionHideBackend.isInDesiredState
            {
                let didChange = positionHideBackend.reassert()
                if didChange {
                    prefsWatcher?.noteSelfWrite()
                }
                return didChange
            }
            return repulseAssertionForRecovery()
        }
        let allItems = appState.itemManager.itemCache.managedItems
        let effectiveAssignment = effectiveAssignmentExcludingTemporarilyRevealed()
        let positionsBefore = positionStore.readPositions()
        let existingKeys = Array(positionsBefore.keys)
        let visibleItemKeys = Set(allItems.compactMap { item -> String? in
            guard (effectiveAssignment[item.uniqueIdentifier] ?? .visible) == .visible else {
                return nil
            }
            return RuntimePreferenceKeys.resolveKey(
                for: item,
                existingKeys: existingKeys,
                positions: positionsBefore,
                liveItems: allItems
            ) ?? RuntimePreferenceKeys.naiveKey(for: item)
        })

        positionStore.lockVisiblePositions(
            visibleItemKeys: visibleItemKeys,
            allItems: allItems
        )
        let didChange = positionStore.readPositions() != positionsBefore
        if didChange {
            prefsWatcher?.noteSelfWrite()
        }
        return didChange
    }

    /// Rung 3: forces a full restriction rebuild. If the items are already
    /// visible, skip the reveal half to avoid an unnecessary visible toggle.
    private func doubleToggleRestrictionForRecovery() -> Bool {
        guard !isClockActivationBridgeActive, let appState else { return false }
        let assignment = assertionAssignmentInput()
        guard assignment.values.contains(where: { $0 == .hidden || $0 == .alwaysHidden }) else {
            return false
        }
        let allItems = appState.itemManager.itemCache.managedItems

        assessmentStateMonitor?.noteSelfChange()
        var didChange = false
        if recoverySnapshot().isControlledHidden {
            didChange = backend.apply(sectionAssignment: [:], allItems: allItems)
        }
        didChange = backend.pulse(
            sectionAssignment: assignment,
            allItems: allItems
        ) || didChange
        noteRecoveryRestrictionChange(didChange)
        return didChange
    }

    private func noteRecoveryRestrictionChange(_ didChange: Bool) {
        guard didChange, let appState else { return }
        appState.itemManager.noteRestrictionChange()
        restoreVisibleControlItemAfterRestrictionChange()
    }

    /// Re-checks whether the private assertion API is available and updates
    /// ``isHidingAvailable``. Called on init and again on
    /// `NSApplication.didBecomeActiveNotification`, since an OS update could
    /// land (or, in principle, be reverted) while the app keeps running.
    func refreshHidingAvailability() {
        let available = backend.refreshAvailability() || (appState?.settings.advanced.enablePositionHiding ?? false)
        guard available != isHidingAvailable else { return }
        isHidingAvailable = available
        diagLog.info("hiding availability changed: \(available ? "available" : "unavailable")")
    }

    /// Logs a one-time diagnostic error at launch when hiding is unavailable on
    /// macOS 27+. Subsequent activation rechecks update ``isHidingAvailable``
    /// silently (see ``refreshHidingAvailability()``) without repeating this.
    private func logUnavailabilityAtLaunchIfNeeded() {
        guard MenuBarBackendProvider.current.usesAssertionHiding,
              !isHidingAvailable,
              !hasLoggedUnavailableAtLaunch
        else { return }
        hasLoggedUnavailableAtLaunch = true
        diagLog.error("Assessment Mode hiding is unavailable on this macOS build; reordering still works, hiding does not")
    }

    /// Derives the section assignment map from a section-order dict.
    /// Items listed in any non-visible section key are assigned to that section;
    /// everything else defaults to `.visible` (absence from the map).
    static func assignmentFromOrder(
        _ order: [MenuBarSection.Name: [String]],
        alwaysHiddenEnabled: Bool = true
    ) -> [String: MenuBarSection.Name] {
        var map = [String: MenuBarSection.Name]()
        for (section, identifiers) in order where section != .visible {
            let effectiveSection: MenuBarSection.Name = if section == .alwaysHidden, !alwaysHiddenEnabled {
                .hidden
            } else {
                section
            }
            for identifier in identifiers {
                map[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] = effectiveSection
            }
        }
        return sanitizedSectionAssignment(map)
    }

    private var alwaysHiddenSectionEnabled: Bool {
        appState?.settings.advanced.isAlwaysHiddenSectionEnabled ?? true
    }

    private func rebuildSectionAssignmentFromOrder() {
        sectionAssignment = Self.assignmentFromOrder(
            sectionItemOrder,
            alwaysHiddenEnabled: alwaysHiddenSectionEnabled
        )
    }

    /// Effective assignment before reveal adjustments. Authored assignments
    /// win; automatic overflow only layers Hidden onto authored-visible items.
    private var assignmentIncludingAutomaticOverflow: [String: MenuBarSection.Name] {
        var assignment = sectionAssignment
        for identifier in overflowHiddenIdentifiers where assignment[identifier] == nil {
            assignment[identifier] = .hidden
        }
        return assignment
    }

    /// Drops assignments that can never be valid hidden-section entries.
    static func sanitizedSectionAssignment(
        _ assignment: [String: MenuBarSection.Name]
    ) -> [String: MenuBarSection.Name] {
        assignment.filter { identifier, section in
            section != .visible &&
                !isControlItemAssignmentIdentifier(identifier) &&
                !isOwnAppAssignmentIdentifier(identifier) &&
                !isHidingUnsupportedAssignmentIdentifier(identifier) &&
                !MenuBarItemTag.isMenuBarAgentForcedVisibleIdentifier(identifier)
        }
    }

    /// Whether the identifier belongs to a denylisted app whose hiding is not yet
    /// supported. These items can be reordered but must never be assigned to a
    /// hidden section — the assertion cannot reliably hide them and volatile
    /// titles create stale-assignment leaks. Such items are simply never placed
    /// in the hidden-assignment list.
    /// Invalid-assignment cleanup preserves missing live items because a hidden
    /// item may be absent from AX while concealed or while its app is not running.
    static func invalidAssignmentIdentifiers(
        sectionAssignment: [String: MenuBarSection.Name],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool
    ) -> Set<String> {
        let assignedControlItemIDs = Set(
            sectionAssignment.keys.filter(Self.isControlItemAssignmentIdentifier)
        )
        let assignedOwnAppIDs = Set(
            sectionAssignment.keys.filter(Self.isOwnAppAssignmentIdentifier)
        )
        let protectedAssignedIDs = Set(
            liveItems
                .filter {
                    let identifier = MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier)
                    guard let assignedSection = sectionAssignment[identifier] else {
                        return false
                    }
                    return Self.isProtectedAssignmentItem(
                        $0,
                        experimentalSystemItemHiding: experimentalSystemItemHiding
                    )
                        || !Self.canAssign(
                            $0,
                            to: assignedSection,
                            experimentalSystemItemHiding: experimentalSystemItemHiding
                        )
                }
                .map { MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier) }
        )

        return assignedControlItemIDs
            .union(assignedOwnAppIDs)
            .union(protectedAssignedIDs)
    }

    private static func isHidingUnsupportedAssignmentIdentifier(_ identifier: String) -> Bool {
        MenuBarItemTag.hidingUnsupportedBundleIDs.contains { bundleID in
            identifier.hasPrefix("\(bundleID):")
        }
    }

    static func canAssign(
        _ item: MenuBarItem,
        to section: MenuBarSection.Name,
        experimentalSystemItemHiding: Bool
    ) -> Bool {
        section == .visible
            || item.canBeHidden(experimentalSystemItemHiding: experimentalSystemItemHiding)
    }

    static func isProtectedAssignmentItem(
        _ item: MenuBarItem,
        experimentalSystemItemHiding: Bool
    ) -> Bool {
        item.isControlItem ||
            isOwnAppItem(item) ||
            (item.tag.isLayoutAnchoredSystemItem && !experimentalSystemItemHiding)
    }

    /// Whether an item should be hidden by the CGS off-screen hider rather than
    /// the assessment-mode assertion when experimental window hiding is on. Scoped
    /// to ordinary third-party app items: Apple/system items (`com.apple.*`) stay
    /// on the assertion / Control Center / Spotlight paths, and Thaw's own items
    /// and control items are never hidden.
    static func isCGSWindowHideable(_ item: MenuBarItem) -> Bool {
        guard !item.isControlItem, !isOwnAppItem(item) else { return false }
        if case let .string(bundleID) = item.tag.namespace {
            return !bundleID.hasPrefix("com.apple.")
        }
        return false
    }

    private static func isOwnAppAssignmentIdentifier(_ identifier: String) -> Bool {
        Constants.isThawOwnedAssignmentIdentifier(identifier)
    }

    private static func isControlItemAssignmentIdentifier(_ identifier: String) -> Bool {
        if identifier.contains(".Spacer.") {
            return true
        }

        let controlTitles = Set(ControlItem.Identifier.allCases.map(\.rawValue))
        if controlTitles.contains(identifier) {
            return true
        }

        let thawControlIdentifiers = Set(
            ControlItem.Identifier.allCases.map { "\(MenuBarItemTag.Namespace.thaw):\($0.rawValue)" }
        )
        return thawControlIdentifiers.contains(identifier)
    }

    /// Merges shared, legacy order, and legacy assignment dictionaries into a
    /// single section-order map. Pure helper used by ``loadOrder(defaults:)`` and tests.
    static func mergeMigratedSectionOrder(
        sharedOrder: [String: [String]]?,
        legacyOrder: [String: [String]]?,
        legacyAssignment: [String: String]?
    ) -> [MenuBarSection.Name: [String]] {
        var map = [MenuBarSection.Name: [String]]()
        if let sharedOrder {
            for (raw, ids) in sharedOrder {
                if let section = MenuBarSection.Name(rawValue: raw) {
                    map[section] = MenuBarItemTag.canonicalPersistentIdentifiers(ids)
                }
            }
        }

        if let legacyOrder {
            for (raw, ids) in legacyOrder {
                guard let section = MenuBarSection.Name(rawValue: raw) else { continue }
                var sectionIDs = map[section] ?? []
                for identifier in ids.map(MenuBarItemTag.canonicalPersistentIdentifier)
                    where !sectionIDs.contains(identifier)
                {
                    sectionIDs.append(identifier)
                }
                if !sectionIDs.isEmpty {
                    map[section] = sectionIDs
                }
            }
        }

        if let legacyAssignment {
            for (identifier, sectionRaw) in legacyAssignment {
                guard let section = MenuBarSection.Name(rawValue: sectionRaw),
                      section != .visible
                else { continue }
                let canonical = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
                if map[section]?.contains(canonical) != true {
                    map[section, default: []].append(canonical)
                }
            }
        }

        return map
    }

    /// Loads the persisted per-section item order, migrating from the old
    /// `Thaw.simpleSectionAssignment` / `Thaw.simpleSectionOrder` keys on
    /// first run, and from the even-older binary switch-list key.
    static func loadOrder(defaults: UserDefaults = .standard) -> [MenuBarSection.Name: [String]] {
        let sharedOrder = defaults.dictionary(forKey: orderKey) as? [String: [String]]
        let legacyOrder = defaults.dictionary(forKey: oldOrderKey) as? [String: [String]]
        let legacyAssignment = defaults.dictionary(forKey: oldAssignmentKey) as? [String: String]
        let hadLegacyData = legacyOrder != nil || legacyAssignment != nil

        var map = mergeMigratedSectionOrder(
            sharedOrder: sharedOrder,
            legacyOrder: legacyOrder,
            legacyAssignment: legacyAssignment
        )

        if hadLegacyData {
            let raw = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
            defaults.set(raw, forKey: orderKey)
            defaults.removeObject(forKey: oldAssignmentKey)
            defaults.removeObject(forKey: oldOrderKey)
        }

        // One-time migration from the even-older binary switch-list key.
        if map.isEmpty,
           let legacy = defaults.stringArray(forKey: legacyHiddenKey),
           !legacy.isEmpty
        {
            map[.hidden] = MenuBarItemTag.canonicalPersistentIdentifiers(legacy)
            defaults.removeObject(forKey: legacyHiddenKey)
        }

        return map
    }

    private func persistOrder() {
        sectionItemOrder = sectionItemOrder.mapValues(MenuBarItemTag.canonicalPersistentIdentifiers)
        let raw = Dictionary(uniqueKeysWithValues: sectionItemOrder.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(raw, forKey: Self.orderKey)
    }

    /// Returns the temporary reveal target for a section control.
    ///
    /// The Visible control item is the user-facing Thaw icon; like Ice on macOS
    /// 26, clicking it reveals the Hidden section.
    static func revealTarget(for section: MenuBarSection.Name) -> MenuBarSection.Name? {
        switch section {
        case .visible, .hidden:
            return .hidden
        case .alwaysHidden:
            return .alwaysHidden
        }
    }

    /// Whether the section should currently be considered hidden by the UI.
    static func isSectionHidden(
        _ section: MenuBarSection.Name,
        revealedSection: MenuBarSection.Name?
    ) -> Bool {
        switch section {
        case .visible, .hidden:
            return revealedSection != .hidden && revealedSection != .alwaysHidden
        case .alwaysHidden:
            return revealedSection != .alwaysHidden
        }
    }

    /// Assignment map to use for the live assertion while a section is revealed.
    static func effectiveSectionAssignment(
        _ assignment: [String: MenuBarSection.Name],
        revealing revealedSection: MenuBarSection.Name?
    ) -> [String: MenuBarSection.Name] {
        let sanitized = sanitizedSectionAssignment(assignment)
        guard let revealedSection else {
            return sanitized
        }

        return sanitized.filter { _, section in
            switch revealedSection {
            case .visible, .hidden:
                return section == .alwaysHidden
            case .alwaysHidden:
                return false
            }
        }
    }

    static func effectiveSectionAssignment(
        _ assignment: [String: MenuBarSection.Name],
        revealing revealedSection: MenuBarSection.Name?,
        temporarilyRevealedIDs: Set<String>
    ) -> [String: MenuBarSection.Name] {
        var effective = effectiveSectionAssignment(assignment, revealing: revealedSection)
        for identifier in temporarilyRevealedIDs {
            effective.removeValue(forKey: identifier)
        }
        return effective
    }

    /// Temporarily reveals a hidden section in the real menu bar.
    ///
    /// - Parameter reconcileBoundary: When `true`, also repairs legacy persisted
    ///   assignments one item at a time. Normal reveals leave this disabled.
    /// - Parameter synchronizeOrder: When `true`, schedules one cancellable,
    ///   batch preferred-position restore after the reveal has settled. Capture
    ///   prewarming disables this because it is not a user-visible reveal.
    func show(
        _ section: MenuBarSection.Name,
        reconcileBoundary: Bool = false,
        synchronizeOrder: Bool = true
    ) {
        if !reconcileBoundary, !synchronizeOrder {
            boundaryReconciliationTask?.cancel()
            boundaryReconciliationTask = nil
        }
        guard let target = Self.revealTarget(for: section), revealedSection != target else {
            return
        }

        // Pin the items that are already visible before releasing the
        // assertion. Otherwise MenuBarAgent may shift Thaw's own status item
        // during reveal, moving it out from under the pointer before the user's
        // second click can rehide the section. The delayed batch restore below
        // then only has to place the newly revealed items around this stable
        // visible segment.
        if #available(macOS 27, *),
           !MenuBarBackendProvider.current.supportsLegacySectionHiding
        {
            appState?.itemManager.prepareMacOS27RevealedOrder()
            if appState?.settings.advanced.enablePositionHiding == false {
                _ = relockVisiblePositionsForRecovery()
            }
        }
        revealedSection = target
        diagLog.info("show(\(target.rawValue)); temporarily revealing assigned item(s)")
        // Restriction apply must stay synchronous with the reveal flag. Deferring
        // it let a rapid follow-up click hide (and cancel the pending refresh)
        // before items ever appeared — clicks registered, nothing showed.
        refresh()

        guard reconcileBoundary || synchronizeOrder else { return }

        // The normal path performs one atomic preferred-position permutation.
        // The slower per-item migration path remains explicit and separate.
        boundaryReconciliationTask?.cancel()
        boundaryReconciliationTask = Task { @MainActor [weak self, weak appState] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self,
                  let appState,
                  !Task.isCancelled,
                  self.revealedSection == target
            else {
                return
            }
            if reconcileBoundary {
                await appState.itemManager.reconcileMacOS27SectionBoundaries(
                    revealing: target
                )
            } else {
                await appState.itemManager.synchronizeMacOS27RevealedOrder(
                    revealing: target
                )
            }
            if !Task.isCancelled, self.revealedSection == target {
                self.boundaryReconciliationTask = nil
            }
        }
    }

    /// Re-applies the persisted assignment, concealing temporary reveals.
    func hideRevealedSections() {
        guard revealedSection != nil else {
            return
        }
        boundaryReconciliationTask?.cancel()
        boundaryReconciliationTask = nil
        let previous = revealedSection
        revealedSection = nil
        lastRefreshSignature = nil
        diagLog.info("hideRevealedSections(previous=\(previous?.rawValue ?? "none"))")
        refresh()
    }

    /// Temporarily forces a single item visible (its owning bundle is dropped
    /// from the concealment assertion) without revealing the rest of its
    /// section. Used by the Thaw Bar click path so only the touched icon
    /// appears in the menu bar.
    func revealItemTemporarily(_ identifier: String) {
        let didInsert = temporarilyRevealedIDs.insert(identifier).inserted
        temporaryRevealConcealTasks[identifier]?.cancel()
        temporaryRevealConcealTasks[identifier] = nil
        diagLog.info("revealItemTemporarily(\(identifier)); single-item reveal")
        if didInsert {
            refresh()
        }
    }

    /// Re-conceals an item previously revealed via ``revealItemTemporarily``.
    func concealTemporarilyRevealedItem(_ identifier: String) {
        temporaryRevealConcealTasks[identifier]?.cancel()
        temporaryRevealConcealTasks[identifier] = nil
        guard temporarilyRevealedIDs.remove(identifier) != nil else { return }
        diagLog.info("concealTemporarilyRevealedItem(\(identifier))")
        refresh()
    }

    /// Conceals a single-item reveal after the configured temporary-show delay.
    /// Time spent with a menu open does not count toward the delay.
    func scheduleTemporaryItemConceal(_ identifier: String) {
        temporaryRevealConcealTasks[identifier]?.cancel()
        let interval = appState?.settings.general.tempShowInterval ?? Defaults.DefaultValue.tempShowInterval
        guard interval > 0 else {
            concealTemporarilyRevealedItem(identifier)
            return
        }
        temporaryRevealConcealTasks[identifier] = Task { @MainActor [weak self] in
            guard let self else { return }
            var eligibleSince = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let isMenuOpen = await self.appState?.itemManager.isAnyMenuBarItemMenuOpen() ?? false
                if isMenuOpen {
                    eligibleSince = Date()
                    continue
                }
                if Date().timeIntervalSince(eligibleSince) >= interval {
                    break
                }
            }
            guard !Task.isCancelled else { return }
            self.temporaryRevealConcealTasks[identifier] = nil
            self.concealTemporarilyRevealedItem(identifier)
        }
    }

    /// Toggles the temporary reveal state for a section.
    func toggle(_ section: MenuBarSection.Name) {
        if Self.isSectionHidden(section, revealedSection: revealedSection) {
            show(section)
        } else {
            hideRevealedSections()
        }
    }

    /// Whether the section is currently concealed by the live assertion.
    func isSectionHidden(_ section: MenuBarSection.Name) -> Bool {
        Self.isSectionHidden(section, revealedSection: revealedSection)
    }

    /// Records the user's left-to-right order for a section (from a layout-bar
    /// drag) and persists it. The caller is expected to trigger a recache so the
    /// layout bars re-render in the new order.
    func setSectionOrder(_ identifiers: [String], for section: MenuBarSection.Name) {
        let identifiers = MenuBarItemTag.canonicalPersistentIdentifiers(identifiers)
        sectionItemOrder[section] = identifiers
        persistOrder()
        appState?.itemManager.mirrorMacOS27SectionOrder(identifiers, for: section)
        diagLog.info("setSectionOrder(\(section.rawValue)); \(identifiers.count) item(s)")
    }

    /// Records a section order from live layout items, dropping structural
    /// control items and fixed system anchors before persistence. The movable
    /// visible Thaw control remains part of visible order.
    func setSectionOrder(from items: [MenuBarItem], for section: MenuBarSection.Name) {
        let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
        setSectionOrder(
            Self.persistableOrderIdentifiers(
                from: items,
                in: section,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ),
            for: section
        )
    }

    /// Returns the identifiers Thaw is allowed to persist for a section order.
    static func persistableOrderIdentifiers(
        from items: [MenuBarItem],
        in section: MenuBarSection.Name
    ) -> [String] {
        persistableOrderIdentifiers(
            from: items,
            in: section,
            experimentalSystemItemHiding: false
        )
    }

    static func persistableOrderIdentifiers(
        from items: [MenuBarItem],
        in section: MenuBarSection.Name,
        experimentalSystemItemHiding: Bool
    ) -> [String] {
        items.compactMap { item in
            if section == .visible,
               item.tag.title == ControlItem.Identifier.visible.rawValue,
               item.tag.namespace == .thaw
            {
                return item.uniqueIdentifier
            }
            guard !item.isControlItem,
                  item.isMovable(experimentalSystemItemHiding: experimentalSystemItemHiding),
                  !isOwnAppItem(item)
            else {
                return nil
            }
            return item.uniqueIdentifier
        }
    }

    /// Reorders `items` for the requested section.
    ///
    /// On macOS 27, the visible layout must mirror fresh AX geometry instead of
    /// persisted order. Persisted visible order can be stale after a failed
    /// physical move, which makes the layout UI drift away from the real menu
    /// bar. Hidden-style sections still use the user's recorded order because
    /// those items may not have meaningful live positions.
    func ordered(_ items: [MenuBarItem], in section: MenuBarSection.Name) -> [MenuBarItem] {
        let order = sectionItemOrder[section] ?? []
        return Self.orderedItems(items, in: section, using: order)
    }

    static func orderedItems(
        _ items: [MenuBarItem],
        in section: MenuBarSection.Name,
        using order: [String]
    ) -> [MenuBarItem] {
        if section == .visible {
            return liveVisualOrder(items)
        }

        let ranked: [MenuBarItem]
        if order.isEmpty {
            ranked = items
        } else {
            let canonicalOrder = MenuBarItemTag.canonicalPersistentIdentifiers(order)
            let rank = Dictionary(canonicalOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            ranked = items.enumerated().sorted { lhs, rhs in
                let lr = rank[lhs.element.uniqueIdentifier] ?? (canonicalOrder.count + lhs.offset)
                let rr = rank[rhs.element.uniqueIdentifier] ?? (canonicalOrder.count + rhs.offset)
                return lr < rr
            }.map(\.element)
        }

        return Self.anchoredSystemItemsTrail(in: ranked)
    }

    /// Orders visible items for overflow decisions using the layout editor's
    /// recorded intent rather than transient MenuBarAgent geometry.
    ///
    /// A freshly revealed item can briefly appear at the application-menu edge.
    /// Sorting only by that live frame makes overflow immediately eject the item
    /// the user just moved to Visible. Recorded items follow `order`; genuinely
    /// new items that are not recorded retain their live relative order at the end.
    static func overflowOrderedVisibleItems(
        _ items: [MenuBarItem],
        using order: [String]
    ) -> [MenuBarItem] {
        let liveOrder = liveVisualOrder(items)
        let canonicalOrder = MenuBarItemTag.canonicalPersistentIdentifiers(order)
        guard !canonicalOrder.isEmpty else { return liveOrder }

        let rank = Dictionary(
            canonicalOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return liveOrder.enumerated().sorted { lhs, rhs in
            let lhsRank = rank[MenuBarItemTag.canonicalPersistentIdentifier(lhs.element.uniqueIdentifier)]
            let rhsRank = rank[MenuBarItemTag.canonicalPersistentIdentifier(rhs.element.uniqueIdentifier)]
            switch (lhsRank, rhsRank) {
            case let (lhsRank?, rhsRank?):
                return lhsRank < rhsRank
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static func liveVisualOrder(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { lhs, rhs in
            if lhs.bounds.midX == rhs.bounds.midX {
                if lhs.bounds.minX == rhs.bounds.minX {
                    return lhs.uniqueIdentifier < rhs.uniqueIdentifier
                }
                return lhs.bounds.minX < rhs.bounds.minX
            }
            return lhs.bounds.midX < rhs.bounds.midX
        }
    }

    /// Moves anchored system items (Clock, Siri, Control Center) to the
    /// trailing end of the array, sorted by their canonical rank. Non-anchored
    /// items keep their existing relative order. This mirrors the sort
    /// ``LayoutBarPaddingView.anchoredSystemItemsTrail`` applies during
    /// drag-drop persistence, so the live cache and the layout UI always agree
    /// on where pinned system extras sit — even when the persisted order was
    /// authored by a profile import or cold-start migration that did not
    /// strip or sort anchored identifiers.
    static func anchoredSystemItemsTrail(in items: [MenuBarItem]) -> [MenuBarItem] {
        let trailingAnchors = items.filter(\.tag.isLayoutAnchoredSystemItem).sorted { lhs, rhs in
            let lhsRank = MenuBarItemTag.anchoredSystemItemRank(lhs.tag)
            let rhsRank = MenuBarItemTag.anchoredSystemItemRank(rhs.tag)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        return items.filter { !$0.tag.isLayoutAnchoredSystemItem } + trailingAnchors
    }

    static func isProtectedAssignmentItem(_ item: MenuBarItem) -> Bool {
        isProtectedAssignmentItem(item, experimentalSystemItemHiding: false)
    }

    private static func isOwnAppItem(_ item: MenuBarItem) -> Bool {
        item.tag.namespace == .thaw ||
            Constants.isThawOwnedBundleIdentifier(item.sourceApplication?.bundleIdentifier) ||
            Constants.isThawOwnedBundleIdentifier(item.owningApplication?.bundleIdentifier) ||
            isOwnAppAssignmentIdentifier(item.uniqueIdentifier)
    }

    /// Starts the periodic refresh that keeps the backend in sync with the live
    /// item set (e.g. re-applying the allowlist when apps appear or quit).
    func start() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.scheduleNativeOverflowProbe()
                self?.drainNativeOverflowRebalanceIfPossible()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
        scheduleNativeOverflowProbe()
    }

    func isNativeOverflowActive(on displayID: CGDirectDisplayID) -> Bool {
        nativeOverflowDisplayIDs.contains(displayID)
    }

    func nativeOverflowControlBounds(on displayID: CGDirectDisplayID) -> [CGRect] {
        guard isNativeOverflowActive(on: displayID) else { return [] }
        return latestNativeOverflowBounds[displayID] ?? []
    }

    /// The two native-overflow gates derived from the current temporary
    /// presentation state.
    ///
    /// `probeGate` excludes Ice Bar: native overflow forces Ice Bar via
    /// `MenuBarManager.shouldUseIceBar`, so gating the probe on Ice Bar being
    /// open made overflow observation freeze the moment it opened Ice Bar —
    /// the probe result that could clear `nativeOverflowDisplayIDs` (and let
    /// Ice Bar's fallback end) could never run again. `drainGate` keeps Ice
    /// Bar included: rewriting item assignments while Ice Bar is showing
    /// would fight its temporary reveal, so rebalancing still waits. See
    /// AGENTS.md macOS 27 hiding invariants: Hidden vs Always Hidden reveal
    /// semantics are distinct, and the same distinction applies here between
    /// Ice Bar's temporary reveal and the overflow signal it is derived from.
    private var temporaryPresentationGates: (probeGate: Bool, drainGate: Bool) {
        Self.nativeOverflowTemporaryPresentationGates(
            hasRevealedSection: revealedSection != nil,
            hasTemporarilyRevealedIDs: !temporarilyRevealedIDs.isEmpty,
            isClockActivationBridgeActive: isClockActivationBridgeActive,
            isIceBarShowing: appState?.menuBarManager.iceBarPanel.currentSection != nil,
            isMenuBarHiddenBySystem: appState?.menuBarManager.isMenuBarHiddenBySystem == true,
            shouldDeferMacOS27MenuBarMutation: appState?.menuBarManager.shouldDeferMacOS27MenuBarMutation == true
        )
    }

    /// Gates native-overflow *rebalancing* (moving items). Ice Bar is
    /// included: see `temporaryPresentationGates`.
    private var isPerformingTemporaryPresentation: Bool {
        temporaryPresentationGates.drainGate
    }

    /// Gates native-overflow *probing* (AX observation). Ice Bar is
    /// deliberately excluded: see `temporaryPresentationGates`.
    private var isPerformingTemporaryPresentationExcludingIceBar: Bool {
        temporaryPresentationGates.probeGate
    }

    /// Pure helper behind `temporaryPresentationGates`, split out so the
    /// probe-vs-drain distinction is unit-testable without a live
    /// `MenuBarManager`/`IceBarPanel`.
    static func nativeOverflowTemporaryPresentationGates(
        hasRevealedSection: Bool,
        hasTemporarilyRevealedIDs: Bool,
        isClockActivationBridgeActive: Bool,
        isIceBarShowing: Bool,
        isMenuBarHiddenBySystem: Bool,
        shouldDeferMacOS27MenuBarMutation: Bool
    ) -> (probeGate: Bool, drainGate: Bool) {
        let probeGate = hasRevealedSection
            || hasTemporarilyRevealedIDs
            || isClockActivationBridgeActive
            || isMenuBarHiddenBySystem
            || shouldDeferMacOS27MenuBarMutation
        return (probeGate: probeGate, drainGate: probeGate || isIceBarShowing)
    }

    private func scheduleNativeOverflowProbe() {
        guard #available(macOS 27, *),
              let displayID = (NSScreen.screenWithActiveMenuBar ?? NSScreen.main)?.displayID
        else {
            return
        }

        pruneStaleNativeOverflowDisplayIDs(activeDisplayID: displayID)

        guard nativeOverflowProbeTask == nil,
              !isPerformingTemporaryPresentationExcludingIceBar
        else {
            return
        }

        nativeOverflowProbeTask = Task { [weak self] in
            let observation = await Task.detached(priority: .utility) {
                MenuBarItemAXProvider.nativeOverflowObservation(on: displayID)
            }.value
            guard let self, !Task.isCancelled else { return }
            nativeOverflowProbeTask = nil
            if case let .present(bounds) = observation {
                latestNativeOverflowBounds[displayID] = bounds
            }
            guard let isActive = nativeOverflowState.consume(observation, on: displayID) else {
                return
            }

            if isActive {
                nativeOverflowDisplayIDs.insert(displayID)
            } else {
                nativeOverflowDisplayIDs.remove(displayID)
                latestNativeOverflowBounds.removeValue(forKey: displayID)
            }
            diagLog.info("native overflow on display \(displayID) is now \(isActive ? "present" : "absent")")
            appState?.menuBarManager.updateControlItemStates()
            pendingNativeOverflowRebalance = true
            drainNativeOverflowRebalanceIfPossible()
        }
    }

    /// Removes tracked overflow state for displays that are no longer the
    /// active menu-bar display or are no longer connected.
    ///
    /// The probe above only ever samples `displayID`, so a display that was
    /// once overflowing but has since lost menu-bar focus (or been
    /// disconnected) would otherwise never be re-sampled and would keep
    /// forcing Ice Bar via `shouldUseIceBar(for:)` forever. Pruning instead
    /// of continuously AX-walking every display keeps the 1-second timer
    /// tick cheap: only the active display gets probed, every other tracked
    /// ID is assumed absent until it becomes active again and earns a fresh
    /// probe.
    private func pruneStaleNativeOverflowDisplayIDs(activeDisplayID: CGDirectDisplayID) {
        guard !nativeOverflowDisplayIDs.isEmpty else { return }
        let connectedDisplayIDs = Set(NSScreen.screens.map(\.displayID))
        let staleDisplayIDs = Self.staleNativeOverflowDisplayIDs(
            tracked: nativeOverflowDisplayIDs,
            activeDisplayID: activeDisplayID,
            connectedDisplayIDs: connectedDisplayIDs
        )
        guard !staleDisplayIDs.isEmpty else { return }

        for staleDisplayID in staleDisplayIDs {
            nativeOverflowDisplayIDs.remove(staleDisplayID)
            latestNativeOverflowBounds.removeValue(forKey: staleDisplayID)
            nativeOverflowState.forget(staleDisplayID)
        }
        diagLog.info(
            "cleared stale native overflow state for \(staleDisplayIDs.count) display(s) no longer active/connected"
        )
        appState?.menuBarManager.updateControlItemStates()
    }

    /// Pure helper behind `pruneStaleNativeOverflowDisplayIDs`, split out so
    /// it is unit-testable without a live `NSScreen` set or timer.
    static func staleNativeOverflowDisplayIDs(
        tracked: Set<CGDirectDisplayID>,
        activeDisplayID: CGDirectDisplayID,
        connectedDisplayIDs: Set<CGDirectDisplayID>
    ) -> Set<CGDirectDisplayID> {
        tracked.filter { $0 != activeDisplayID || !connectedDisplayIDs.contains($0) }
    }

    private func drainNativeOverflowRebalanceIfPossible() {
        guard pendingNativeOverflowRebalance,
              !isPerformingTemporaryPresentation,
              let itemManager = appState?.itemManager
        else {
            return
        }
        pendingNativeOverflowRebalance = false
        itemManager.scheduleMacOS27OverflowRebalance(force: true)
    }

    /// The section the item with the given identifier is assigned to.
    func section(for identifier: String) -> MenuBarSection.Name {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        if authoredSection(for: identifier) == .visible,
           overflowHiddenIdentifiers.contains(identifier)
        {
            return .hidden
        }
        return authoredSection(for: identifier)
    }

    /// The section explicitly authored by the user or active profile, excluding
    /// temporary automatic-overflow concealment.
    func authoredSection(for identifier: String) -> MenuBarSection.Name {
        sectionAssignment[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] ?? .visible
    }

    /// Replaces the exact set of authored-visible items concealed by automatic
    /// overflow. Passing an empty set restores every overflowed item to its
    /// authored section without disturbing explicit Hidden assignments.
    @discardableResult
    func setOverflowHiddenIdentifiers(_ identifiers: Set<String>) -> Bool {
        let canonical = Set(
            MenuBarItemTag.canonicalPersistentIdentifiers(Array(identifiers))
                .filter { authoredSection(for: $0) == .visible }
        )
        guard canonical != overflowHiddenIdentifiers else { return false }
        overflowHiddenIdentifiers = canonical
        diagLog.info("automatic overflow now conceals \(canonical.count) item(s)")
        refresh()
        return true
    }

    /// Captures live items before automatic overflow conceals them, then applies
    /// the exact overflow set. The snapshots keep those items available for a
    /// later wider-space rebalance even when concealment removes them from AX.
    @discardableResult
    func setOverflowHiddenItems(_ items: [MenuBarItem]) -> Bool {
        for item in items where authoredSection(for: item.uniqueIdentifier) == .visible {
            snapshots[MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)] = item
        }
        return setOverflowHiddenIdentifiers(Set(items.map(\.uniqueIdentifier)))
    }

    /// The section for a live item. System anchors and any item Thaw can't
    /// conceal are always visible even if stale defaults say otherwise.
    /// When experimental system-item hiding is on, layout-anchored items
    /// (Clock, Control Center, Siri) follow their assignment like any other
    /// hideable item.
    func section(for item: MenuBarItem) -> MenuBarSection.Name {
        let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
        let policy = item.sectionManagementPolicy(
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
        if policy.isForcedVisible || Self.isOwnAppItem(item) {
            return .visible
        }
        return section(for: item.uniqueIdentifier)
    }

    /// Assigns the item to a section. Dropping it back into `.visible` removes
    /// the entry (the default). Persists and re-applies the restriction.
    func setSection(_ section: MenuBarSection.Name, identifier: String) {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        overflowHiddenIdentifiers.remove(identifier)
        guard !Self.isControlItemAssignmentIdentifier(identifier),
              !Self.isOwnAppAssignmentIdentifier(identifier)
        else {
            if sectionAssignment[identifier] != nil {
                removeFromOrder(identifier: identifier)
                rebuildSectionAssignmentFromOrder()
                persistOrder()
                refresh()
            }
            diagLog.warning("ignored protected section assignment for \(identifier)")
            return
        }

        // A layout-bar drop into Always Hidden is an explicit user choice. On
        // macOS 27 the section's divider is normally collapsed to two points,
        // so leaving its reveal gestures disabled would successfully conceal
        // the item while giving the user no practical way to bring it back.
        // Establish the section and its non-destructive Option-click reveal
        // path before persisting the first assignment.
        if section == .alwaysHidden,
           let advanced = appState?.settings.advanced
        {
            if !advanced.enableAlwaysHiddenSection {
                advanced.enableAlwaysHiddenSection = true
                diagLog.info("enabled always-hidden section after layout assignment")
            }
            if !advanced.useOptionClickToShowAlwaysHiddenSection {
                advanced.useOptionClickToShowAlwaysHiddenSection = true
                diagLog.info("enabled Option-click always-hidden reveal after layout assignment")
            }
        }

        // Move the identifier to its new section in the order dict so assignment
        // and order stay consistent in a single write (no separate assignment key).
        removeFromOrder(identifier: identifier)
        if section != .visible {
            sectionItemOrder[section, default: []].append(identifier)
        }
        rebuildSectionAssignmentFromOrder()
        persistOrder()
        diagLog.info("setSection(\(section.rawValue)) \(identifier); \(sectionAssignment.count) assigned item(s)")
        refresh()
    }

    /// Removes an identifier from every section in `sectionItemOrder`.
    private func removeFromOrder(identifier: String) {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        for section in MenuBarSection.Name.allCases {
            guard var identifiers = sectionItemOrder[section] else { continue }
            identifiers.removeAll { $0 == identifier }
            if identifiers.isEmpty {
                sectionItemOrder.removeValue(forKey: section)
            } else {
                sectionItemOrder[section] = identifiers
            }
        }
    }

    /// Assigns several items to `section` in one write (single persist + refresh).
    /// Used by macOS 27 overflow rebalance so Spawner floods do not pay N
    /// restriction pulses.
    func setSection(_ section: MenuBarSection.Name, items: [MenuBarItem]) {
        guard !items.isEmpty else { return }

        if section == .alwaysHidden,
           let advanced = appState?.settings.advanced
        {
            if !advanced.enableAlwaysHiddenSection {
                advanced.enableAlwaysHiddenSection = true
            }
            if !advanced.useOptionClickToShowAlwaysHiddenSection {
                advanced.useOptionClickToShowAlwaysHiddenSection = true
            }
        }

        let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
        var moved = [String]()
        for item in items {
            let cannotHideHere = !Self.canAssign(
                item,
                to: section,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
            if Self.isProtectedAssignmentItem(
                item,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) || cannotHideHere {
                continue
            }
            let identifier = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
            overflowHiddenIdentifiers.remove(identifier)
            removeFromOrder(identifier: identifier)
            if section != .visible {
                sectionItemOrder[section, default: []].append(identifier)
            }
            moved.append(identifier)
        }
        guard !moved.isEmpty else { return }
        rebuildSectionAssignmentFromOrder()
        persistOrder()
        diagLog.info(
            "setSection(\(section.rawValue)) batch \(moved.count) item(s); \(sectionAssignment.count) assigned"
        )
        refresh()
    }

    /// Assigns a live item to a section, rejecting items that can never be
    /// safely concealed on macOS 27. Use this overload when a caller has the
    /// `MenuBarItem`; it can identify Thaw-owned generic `Item-0` entries even
    /// when their persisted identifier is not the stable control-item title.
    func setSection(_ section: MenuBarSection.Name, item: MenuBarItem) {
        // Reject control/anchored/own items, and any item that can't be hidden
        // being dropped into a non-visible section (Apple system modules on
        // macOS 27): they stay visible. Dropping one back to .visible is always
        // allowed so an existing stale assignment can be cleared.
        let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
        let cannotHideHere = !Self.canAssign(
            item,
            to: section,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
        guard !Self.isProtectedAssignmentItem(
            item,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ), !cannotHideHere else {
            if sectionAssignment[item.uniqueIdentifier] != nil {
                removeFromOrder(identifier: item.uniqueIdentifier)
                rebuildSectionAssignmentFromOrder()
                persistOrder()
                refresh()
            }
            diagLog.warning("ignored section assignment for protected/non-hideable item \(item.uniqueIdentifier)")
            return
        }
        // Retain the exact live item before setSection(identifier:) refreshes
        // the restriction. The refresh can conceal the owning app immediately,
        // removing this item from AX and itemCache before refresh() gets another
        // chance to snapshot it.
        snapshots = Self.updatedSnapshots(
            snapshots,
            afterAssigning: item,
            to: section
        )
        setSection(section, identifier: item.uniqueIdentifier)
    }

    /// Replaces the entire section assignment wholesale (used by Reset Layout).
    /// `.visible` entries are dropped (the default), then the restriction is
    /// persisted and re-applied.
    func resetAssignment(to assignment: [String: MenuBarSection.Name]) {
        overflowHiddenIdentifiers.removeAll()
        let sanitized = Self.sanitizedSectionAssignment(assignment)
        // Rebuild order from the new assignment, preserving relative order for
        // items that remain in the same section.
        var newOrder = [MenuBarSection.Name: [String]]()
        for section in MenuBarSection.Name.allCases where section != .visible {
            let oldOrder = sectionItemOrder[section] ?? []
            let newIDs = Set(sanitized.filter { $0.value == section }.map(\.key))
            var ordered = oldOrder.filter { newIDs.contains($0) }
            let orderedSet = Set(ordered)
            for id in newIDs where !orderedSet.contains(id) {
                ordered.append(id)
            }
            if !ordered.isEmpty {
                newOrder[section] = ordered
            }
        }
        sectionItemOrder = newOrder
        rebuildSectionAssignmentFromOrder()
        persistOrder()
        diagLog.info("resetAssignment; \(sectionAssignment.count) assigned item(s)")
        refresh()
    }

    /// Applies a profile or saved-layout spec on macOS 27. Section membership
    /// is written through the assignment model; intra-section order is persisted
    /// per section. Visible entries are omitted from the assignment map.
    ///
    /// Items from denylisted apps that cannot be reliably hidden (see
    /// ``MenuBarItemTag/hidingUnsupportedBundleIDs``) are filtered out of hidden
    /// assignments and forced to their existing section (visible), excluding
    /// them from the hidden-order list entirely.
    func applyProfileLayout(
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) {
        overflowHiddenIdentifiers.removeAll()
        var assignment = Self.assignment(
            from: itemSectionMap,
            itemOrder: itemOrder
        )
        // Filter out identifiers from denylisted hiding-unsupported apps. They
        // can be reordered but must never be assigned to a hidden section, even
        // when a profile import or layout export tries to do so.
        assignment = assignment.filter { identifier, _ in
            !MenuBarItemTag.hidingUnsupportedBundleIDs.contains { bundleID in
                identifier.hasPrefix("\(bundleID):")
            }
        }
        // Build order from the profile's section layout; derive assignment from
        // that — no separate assignment write needed.
        var newOrder = [MenuBarSection.Name: [String]]()
        for (sectionKey, identifiers) in itemOrder {
            guard let section = MenuBarSection.Name(rawValue: sectionKey) else { continue }
            let filtered = MenuBarItemTag.canonicalPersistentIdentifiers(
                identifiers.filter(Self.isPersistableProfileOrderIdentifier)
            )
            if !filtered.isEmpty {
                newOrder[section] = filtered
            }
        }
        // Seed any assigned-but-not-yet-ordered items into their section lists.
        let sanitized = Self.sanitizedSectionAssignment(assignment)
        for (identifier, section) in sanitized where section != .visible {
            if newOrder[section]?.contains(identifier) != true {
                newOrder[section, default: []].append(identifier)
            }
        }
        sectionItemOrder = newOrder
        rebuildSectionAssignmentFromOrder()
        persistOrder()
        diagLog.info(
            "applyProfileLayout; \(sectionAssignment.count) assigned item(s), order sections=\(sectionItemOrder.keys.map(\.rawValue))"
        )
        refresh()
    }

    /// Builds a non-visible section assignment from profile layout fields.
    static func assignment(
        from itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) -> [String: MenuBarSection.Name] {
        var assignment = [String: MenuBarSection.Name]()
        for (identifier, sectionKey) in itemSectionMap {
            guard let section = MenuBarSection.Name(rawValue: sectionKey),
                  section != .visible,
                  isPersistableProfileOrderIdentifier(identifier)
            else {
                continue
            }
            assignment[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] = section
        }

        if assignment.isEmpty {
            for (sectionKey, identifiers) in itemOrder {
                guard let section = MenuBarSection.Name(rawValue: sectionKey),
                      section != .visible
                else {
                    continue
                }
                for identifier in identifiers where isPersistableProfileOrderIdentifier(identifier) {
                    assignment[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] = section
                }
            }
        }

        return assignment
    }

    private static func isPersistableProfileOrderIdentifier(_ identifier: String) -> Bool {
        !isControlItemAssignmentIdentifier(identifier) &&
            !isOwnAppAssignmentIdentifier(identifier)
    }

    /// Last-known snapshots of assigned items, captured while they were still
    /// enumerable. A concealed item has no window and drops out of the AX
    /// enumeration, so the layout bars resurrect it from its snapshot (see the
    /// macOS 27 re-bucketing in `MenuBarItemManager`). Keyed by
    /// ``MenuBarItem/uniqueIdentifier``.
    private var snapshots: [String: MenuBarItem] = [:]

    /// Applies the snapshot side of a live-item section assignment. This is a
    /// separate transition so the assign-before-conceal ordering stays covered
    /// without invoking the system visibility assertion in tests.
    static func updatedSnapshots(
        _ existing: [String: MenuBarItem],
        afterAssigning item: MenuBarItem,
        to section: MenuBarSection.Name
    ) -> [String: MenuBarItem] {
        var updated = existing
        if section == .visible {
            updated.removeValue(forKey: item.uniqueIdentifier)
        } else {
            updated[item.uniqueIdentifier] = item
        }
        return updated
    }

    /// The retained snapshot for an assigned item, if one was captured this
    /// session (while the item was still visible).
    func snapshot(for identifier: String) -> MenuBarItem? {
        snapshots[MenuBarItemTag.canonicalPersistentIdentifier(identifier)]
    }

    /// Tags of every assigned item that has a retained snapshot. The image cache
    /// preserves these so a concealed item that briefly drops out of the live
    /// item cache (between conceal and the snapshot re-add) doesn't lose its
    /// last-good icon to the stale-entry cleanup, leaving a blank Hidden slot.
    var assignedSnapshotTags: Set<MenuBarItemTag> {
        Set(assignmentIncludingAutomaticOverflow.keys.compactMap { snapshots[$0]?.tag })
    }

    /// The item-set component of ``refreshSignature(allItems:experimentalSystemItemHiding:experimentalWindowHiding:)``.
    ///
    /// Items we conceal via the assessment-mode assertion drop out of the live
    /// `allItems` cache as a *side effect of our own hiding*. Counting their
    /// raw presence would flip the signature every time a concealed item
    /// oscillates in and out of the cache, defeating the `lastRefreshSignature`
    /// dedup in ``refresh(forceRestrictionPulse:)`` and re-applying the
    /// assertion on nearly every 1 Hz tick. That whole-bar re-composite is the
    /// 2-3s "items flicker then vanish" loop reported when Always Hidden holds
    /// third-party items and position hiding is off (the default).
    ///
    /// Concealed identifiers are folded in as a stable constant (by canonical
    /// identity) and stripped from the live contribution, so their cache
    /// membership can no longer perturb the signature. Genuinely external
    /// changes — a non-concealed item appearing or disappearing — still move
    /// the signature and re-arm the refresh.
    static func refreshSignatureItemComponent(
        liveItemIdentifiers: [String],
        concealedCanonicalIdentifiers: Set<String>
    ) -> String {
        let liveContribution = liveItemIdentifiers.filter { identifier in
            !concealedCanonicalIdentifiers.contains(
                MenuBarItemTag.canonicalPersistentIdentifier(identifier)
            )
        }
        return (liveContribution + concealedCanonicalIdentifiers)
            .sorted()
            .joined(separator: ",")
    }

    func refreshSignature(
        allItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        experimentalWindowHiding: Bool
    ) -> String {
        let concealedCanonicalIdentifiers = Set(effectiveAssignmentExcludingTemporarilyRevealed().keys)
        let itemComponent = Self.refreshSignatureItemComponent(
            liveItemIdentifiers: allItems.map(\.uniqueIdentifier),
            concealedCanonicalIdentifiers: concealedCanonicalIdentifiers
        )
        return [
            "assignment=\(sectionAssignment.map { "\($0.key)=\($0.value.rawValue)" }.sorted().joined(separator: ","))",
            "overflow=\(overflowHiddenIdentifiers.sorted().joined(separator: ","))",
            "revealed=\(revealedSection?.rawValue ?? "none")",
            "temporary=\(temporarilyRevealedIDs.sorted().joined(separator: ","))",
            "items=\(itemComponent)",
            "system=\(experimentalSystemItemHiding)",
            "window=\(experimentalWindowHiding)",
        ].joined(separator: "|")
    }

    /// Re-applies the current assignment against the live item cache, and
    /// refreshes the retained snapshots.
    func refresh(forceRestrictionPulse: Bool = false) {
        guard let appState else { return }
        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        let allItems = appState.itemManager.itemCache.managedItems
        // The assessment assertion collateral-hides Focus and Now Playing while
        // it conceals any third-party app. Route third-party hiding through
        // preferred positions whenever either module is live, even when the
        // optional position backend setting is off.
        let preservesPositionManagedSystemModules = allItems.contains {
            $0.tag.isPositionManageableMenuBarAgentItem
        } || sectionAssignment.keys.contains(where: MenuBarItemTag.isPositionManageableMenuBarAgentIdentifier)
        let experimentalWindowHiding = appState.settings.advanced.enablePositionHiding || preservesPositionManagedSystemModules
        let invalidAssignmentIDs = Self.invalidAssignmentIdentifiers(
            sectionAssignment: sectionAssignment,
            liveItems: allItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
        if !invalidAssignmentIDs.isEmpty {
            for identifier in invalidAssignmentIDs {
                removeFromOrder(identifier: identifier)
            }
            rebuildSectionAssignmentFromOrder()
            persistOrder()
            diagLog.info("removed \(invalidAssignmentIDs.count) stale/invalid assignment(s)")
        }

        let signature = refreshSignature(
            allItems: allItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            experimentalWindowHiding: experimentalWindowHiding
        )

        // Low-frequency safety pass for apps that rewrite their own preferred
        // position about once per second (notably iStat). Only re-park items
        // when a hidden item has actually escaped the off-screen band; running
        // reassert unconditionally on every 1 Hz tick writes on every benign
        // MenuBarAgent renormalization, sustaining a write → reflow → write
        // loop that visibly jitters visible items. The preference watcher
        // remains the faster event-driven path for genuine external changes.
        if experimentalWindowHiding,
           positionHideBackend.hasManagedItems,
           !positionHideBackend.isInDesiredState,
           positionHideBackend.reassert()
        {
            prefsWatcher?.noteSelfWrite()
        }
        // A forced pulse must still run when the assignment signature is
        // unchanged: system-item allowlist changes only re-composite after an
        // assertion teardown (see RuntimeSessionController.pulse), which is
        // exactly what Reset-to-Hidden needs for Clock/Control Center/Siri.
        if !forceRestrictionPulse {
            guard signature != lastRefreshSignature else { return }
        }
        lastRefreshSignature = signature

        // Snapshot every assigned item while it's still live, so it can keep
        // appearing in the layout bars after it's concealed. Drop snapshots for
        // items that are no longer assigned.
        let assignmentIncludingOverflow = assignmentIncludingAutomaticOverflow
        for item in allItems where assignmentIncludingOverflow[item.uniqueIdentifier] != nil {
            snapshots[item.uniqueIdentifier] = item
        }
        snapshots = snapshots.filter { assignmentIncludingOverflow[$0.key] != nil }
        let effectiveAssignment = effectiveAssignmentExcludingTemporarilyRevealed()

        // Apple Control Center modules cannot be hidden by the assessment-mode
        // allowlist (proven 2026-06-18); route them to their Control Center
        // preference instead, and strip them from the backend input.
        //
        // CC modules follow the *persisted* assignment, NOT the reveal-adjusted
        // `effectiveAssignment`: changing a CC pref restarts Control Center
        // (~1-2s blank of the whole CC area). Driving that off temporary reveals
        // made every Thaw-icon click restart Control Center and rapid clicks
        // thrashed it to empty. So a temporary reveal leaves CC modules as-is —
        // they show/hide only on a real assignment change (drag to/from Hidden).
        var ccHiddenTitles = Set<String>()
        for (identifier, section) in assignmentIncludingOverflow where section != .visible {
            // Focus and Now Playing use preferred positions, not the Control
            // Center preference: restarting the host to apply that preference
            // cannot overcome assessment-mode collateral hiding.
            guard !MenuBarItemTag.isPositionManageableMenuBarAgentIdentifier(identifier) else {
                continue
            }
            if let title = RuntimeModuleController.governableMenuExtraTitle(forItemIdentifier: identifier) {
                ccHiddenTitles.insert(title)
            }
        }
        ccModuleManager.apply(hiddenMenuExtraTitles: ccHiddenTitles)

        // Strip CC modules from the backend input regardless of
        // reveal state (they are handled by their dedicated managers above).
        var backendAssignment = backendAssignmentInput()

        // When selected, move third-party status items to off-screen preference
        // bands. Resolved items are stripped from `backendAssignment`, leaving
        // the assertion responsible only for system and unresolved items. The
        // older plist → CGS → AX → position-lock experiment remains isolated in
        // `applyExperimentalWindowHiding`; its load-bearing pass order is not
        // reused or altered by this independent position backend.
        applyPositionHiding(
            enabled: appState.settings.advanced.enablePositionHiding,
            effectiveAssignment: effectiveAssignment,
            allItems: allItems,
            backendAssignment: &backendAssignment
        )

        // The Clock activation bridge intentionally releases the assertion
        // while Notification Center is open. Keep processing non-assertion
        // authorities above, but do not let the 1 Hz refresh or an assignment
        // update immediately recreate the restriction underneath the panel.
        guard !isClockActivationBridgeActive else {
            diagLog.debug("skipping assertion apply during Clock activation bridge")
            return
        }

        logRestrictionProbeSnapshot(reason: "before-apply", items: allItems)
        let hasConcealedItems = backendAssignment.values.contains {
            $0 == .hidden || $0 == .alwaysHidden
        }
        assessmentStateMonitor?.noteSelfChange()
        let didChangeRestriction = if forceRestrictionPulse, hasConcealedItems {
            backend.pulse(
                sectionAssignment: backendAssignment,
                allItems: allItems
            )
        } else {
            backend.apply(
                sectionAssignment: backendAssignment,
                allItems: allItems
            )
        }
        if didChangeRestriction {
            appState.itemManager.noteRestrictionChange()
            restoreVisibleControlItemAfterRestrictionChange()
            diagLog.info("restriction changed; restored visible control item state")
            runPostRestrictionSceneProbes()
            if positionHideBackend.reassert() {
                prefsWatcher?.noteSelfWrite()
                diagLog.info("re-applied third-party position weights after system assertion reflow")
            }
            // Experimental overflow prevention: push hidden items' position
            // weights to extreme values so the native macOS 27 menu bar
            // overflow (notched displays) collapses them before visible items.
            applyExperimentalOverflowPreventionIfEnabled(allItems: allItems)
            // Post-assertion safety net: verify denylisted hiding-unsupported
            // items are still visible after the restriction reflow. Runs async
            // so the main thread isn't blocked by a fresh AX walk on every refresh.
            let expectedUnsupportedBundleIDs = Set(
                allItems.compactMap { item in
                    item.tag.isHidingUnsupported ? item.tag.namespace.description : nil
                }
            )
            Task { @MainActor [weak self, expectedUnsupportedBundleIDs] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.verifyHidingUnsupportedItemsVisiblePostAssertion(
                    expectedBundleIDs: expectedUnsupportedBundleIDs
                )
            }
        }
    }

    /// Re-enumerates from AX after the assertion fires and tears down the
    /// restriction if any denylisted hiding-unsupported item has become
    /// invisible. Uses a fresh AX snapshot — the pre-assertion `allItems`
    /// cache has stale `isOnScreen` values.
    struct HidingUnsupportedVisibilityFailures {
        let invisibleItems: [MenuBarItem]
        let absentBundleIDs: Set<String>

        var isEmpty: Bool {
            invisibleItems.isEmpty && absentBundleIDs.isEmpty
        }
    }

    static func hidingUnsupportedVisibilityFailures(
        items: [MenuBarItem],
        bundleIDs: Set<String>
    ) -> HidingUnsupportedVisibilityFailures {
        let unsupportedItems = items.filter { item in
            bundleIDs.contains(item.tag.namespace.description)
        }
        let presentBundleIDs = Set(unsupportedItems.map(\.tag.namespace.description))
        return HidingUnsupportedVisibilityFailures(
            invisibleItems: unsupportedItems.filter { !$0.isOnScreen },
            absentBundleIDs: bundleIDs.subtracting(presentBundleIDs)
        )
    }

    private func verifyHidingUnsupportedItemsVisiblePostAssertion(expectedBundleIDs: Set<String>) {
        guard #available(macOS 27, *),
              RuntimeSessionController.isAvailable,
              !expectedBundleIDs.isEmpty
        else { return }

        let freshItems = MenuBarItemAXProvider.menuBarItems(option: [])
        let failures = Self.hidingUnsupportedVisibilityFailures(
            items: freshItems,
            bundleIDs: expectedBundleIDs
        )
        guard !failures.isEmpty else { return }

        diagLog.error(
            "Post-assertion guard: \(failures.invisibleItems.count) denylisted hiding-unsupported item(s) " +
                "invisible, \(failures.absentBundleIDs.count) bundle(s) absent — " +
                "tearing down restriction. Invisible: " +
                failures.invisibleItems.map { "\($0.uniqueIdentifier) onScreen=\($0.isOnScreen)" }.joined(separator: ", ") +
                ". Absent: \(failures.absentBundleIDs.sorted().joined(separator: ", "))"
        )
        resetBackendRestriction()
    }

    private func resetBackendRestriction() {
        backend.markExternallyTornDown()
        backend.apply(sectionAssignment: [:], allItems: [])
    }

    /// Whether a click on the system Clock needs the macOS 27 assertion bridge.
    /// Position-only concealment does not suppress Notification Center and must
    /// not incur an unnecessary reveal/reflow.
    var shouldBridgeClockActivation: Bool {
        guard #available(macOS 27, *) else { return false }
        return !isClockActivationBridgeActive
            && hasDesiredAssertionRestriction
            && backend.isHolding
    }

    /// Temporarily releases the visibility restriction so Clock can open
    /// Notification Center. Position-hidden items and Control Center preference
    /// state remain untouched.
    @discardableResult
    func beginClockActivationBridge() -> Bool {
        guard shouldBridgeClockActivation, let appState else { return false }

        clockAssertionRestoreTask?.cancel()
        clockAssertionRestoreTask = nil
        clockAssertionRestoreToken = nil
        isClockActivationBridgeActive = true
        assessmentStateMonitor?.noteSelfChange()
        let didChange = backend.apply(
            sectionAssignment: [:],
            allItems: appState.itemManager.itemCache.managedItems
        )
        guard didChange || !backend.isHolding else {
            isClockActivationBridgeActive = false
            return false
        }

        diagLog.info("temporarily released assertion for Clock activation")
        return true
    }

    /// Restores the latest assertion assignment after Notification Center
    /// closes. A pulse bypasses the anti-flap window that would otherwise reject
    /// a quick restore to the configuration held before the temporary release.
    func endClockActivationBridge() {
        guard isClockActivationBridgeActive else { return }
        isClockActivationBridgeActive = false
        guard let appState, hasDesiredAssertionRestriction else { return }

        assessmentStateMonitor?.noteSelfChange()
        let didChange = backend.pulse(
            sectionAssignment: assertionAssignmentInput(),
            allItems: appState.itemManager.itemCache.managedItems
        )
        noteRecoveryRestrictionChange(didChange)
        scheduleClockAssertionRestoreVerification()
        diagLog.info("restored assertion after Clock activation")
    }

    private func scheduleClockAssertionRestoreVerification() {
        clockAssertionRestoreTask?.cancel()
        let token = UUID()
        clockAssertionRestoreToken = token
        clockAssertionRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if clockAssertionRestoreToken == token {
                    clockAssertionRestoreTask = nil
                    clockAssertionRestoreToken = nil
                }
            }

            for _ in 0 ..< 8 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled,
                      !isClockActivationBridgeActive,
                      hasDesiredAssertionRestriction
                else { return }

                if backend.isHolding {
                    continue
                }

                lastRefreshSignature = nil
                refresh(forceRestrictionPulse: true)
            }

            if !backend.isHolding {
                diagLog.error("Clock activation bridge could not restore assertion after bounded retries")
            }
        }
    }

    /// Pushes hidden items' position weights to extreme values
    /// (50000+) in `TrailingItemPreferredPositions` so the native macOS 27 menu
    /// bar overflow on notched displays collapses them before visible items.
    /// Items moved back to visible get their weights restored.
    private func applyExperimentalOverflowPreventionIfEnabled(allItems: [MenuBarItem]) {
        guard let appState else { return }
        guard appState.settings.advanced.enableExperimentalOverflowPrevention else { return }
        guard !appState.menuBarManager.shouldDeferMacOS27MenuBarMutation else {
            diagLog.debug("Skipping experimental overflow prevention: native menu bar unavailable/transitioning")
            return
        }

        var positions = positionStore.readPositions()
        let existingKeys = Array(positions.keys)
        var changed = false
        let maxElevated = positions.values.filter { $0 >= 50000 }.max()
        var overflowBase = maxElevated.map { $0 + 10 } ?? 50000

        for (identifier, section) in assignmentIncludingAutomaticOverflow where section != .visible {
            guard let item = allItems.first(where: { $0.uniqueIdentifier == identifier }) ??
                snapshots[identifier]
            else { continue }

            guard let key = RuntimePreferenceKeys.resolveKey(
                for: item,
                existingKeys: existingKeys,
                positions: positions,
                liveItems: allItems
            ) else { continue }

            let currentWeight = positions[key] ?? overflowBase
            if currentWeight < 50000 {
                positions[key] = overflowBase
                overflowBase += 10
                changed = true
            }
        }

        guard changed else { return }
        positionStore.writePositions(positions)
        prefsWatcher?.noteSelfWrite()
        diagLog.info("overflowPrevention: elevated \(overflowBase - 50000) hidden-item weight(s)")
    }

    /// Re-applies the current assertion allowlist without changing assignment.
    /// Used after reflow collateral leaves allowed bundles invisible at on-band
    /// AX coordinates (synthetic drags cannot recover those).
    @discardableResult
    func pulseRestrictionAfterReflow(liveItems: [MenuBarItem]) -> Bool {
        guard !isClockActivationBridgeActive,
              RuntimeSessionController.isAvailable
        else { return false }
        let assignment = assertionAssignmentInput()
        guard assignment.values.contains(where: { $0 == .hidden || $0 == .alwaysHidden }) else {
            return false
        }

        logRestrictionProbeSnapshot(reason: "before-pulse", items: liveItems)
        let didPulse = backend.pulse(
            sectionAssignment: assignment,
            allItems: liveItems
        )
        if didPulse {
            restoreVisibleControlItemAfterRestrictionChange()
            diagLog.info("restriction pulsed after reflow; restored visible control item state")
        }
        return didPulse
    }

    private func backendAssignmentInput() -> [String: MenuBarSection.Name] {
        var backendAssignment = effectiveAssignmentExcludingTemporarilyRevealed()
        for identifier in backendAssignment.keys
            where RuntimeModuleController.isGovernable(itemIdentifier: identifier)
        {
            backendAssignment.removeValue(forKey: identifier)
        }
        return backendAssignment
    }

    private func assertionAssignmentInput() -> [String: MenuBarSection.Name] {
        var assignment = backendAssignmentInput()
        for identifier in positionAssertionExcludedItemIdentifiers {
            assignment.removeValue(forKey: identifier)
        }
        return assignment
    }

    /// Drives third-party hiding through off-screen position weights. Every
    /// third-party assignment is removed from the assertion input so that
    /// position mode never causes a whole-bar re-composite. Items without a
    /// resolvable `status:` key remain visible.
    func applyPositionHiding(
        enabled: Bool,
        effectiveAssignment: [String: MenuBarSection.Name],
        allItems: [MenuBarItem],
        backendAssignment: inout [String: MenuBarSection.Name]
    ) {
        guard enabled else {
            positionHandledItemIdentifiers.removeAll()
            positionAssertionExcludedItemIdentifiers.removeAll()
            if positionHideBackend.revealAll() {
                prefsWatcher?.noteSelfWrite()
            }
            return
        }

        var items = allItems
        let liveIdentifiers = Set(allItems.map(\.uniqueIdentifier))
        items.append(contentsOf: snapshots.values.filter {
            !liveIdentifiers.contains($0.uniqueIdentifier)
        })
        let visibleOrder = Self.liveVisualOrder(
            items.filter { (effectiveAssignment[$0.uniqueIdentifier] ?? .visible) == .visible }
        )
        let result = positionHideBackend.apply(
            sectionAssignment: effectiveAssignment,
            allItems: items,
            visibleOrder: visibleOrder
        )
        positionHandledItemIdentifiers = result.handledItemIdentifiers
        // Remove EVERY third-party item from the assertion input — not just the
        // ones that resolved to a `status:` key. If an unresolved hidden item
        // stayed in the assertion input, the concealed set would flip on every
        // reveal/re-hide of that item, re-applying the assertion and forcing a
        // whole-bar re-composite (the 2-3s "menu bar disappears then comes back"
        // flicker). With position hiding on, the assertion manages system items
        // only; an unresolved third-party item stays visible instead.
        positionAssertionExcludedItemIdentifiers = result.thirdPartyItemIdentifiers
        for identifier in positionAssertionExcludedItemIdentifiers {
            backendAssignment.removeValue(forKey: identifier)
        }
        if result.didWrite {
            prefsWatcher?.noteSelfWrite()
        }
    }

    /// Assignment applied to hiding backends after removing single-item reveals.
    private func effectiveAssignmentExcludingTemporarilyRevealed() -> [String: MenuBarSection.Name] {
        Self.effectiveSectionAssignment(
            assignmentIncludingAutomaticOverflow,
            revealing: revealedSection,
            temporarilyRevealedIDs: temporarilyRevealedIDs
        )
    }

    /// Experimental surgical hide: when `enabled`, hide third-party items via
    /// per-key plist manipulation instead of the assessment-mode assertion,
    /// which re-composites the whole bar and can disrupt dynamic neighbors
    /// like iStat Menus. Note that on macOS 27 removing keys from
    /// `TrailingItemPreferredPositions` alone does not hide items — the
    /// assertion remains the primary visibility mechanism.
    ///
    /// The passes run in order:
    /// 1. Plist hide/show — remove keys for newly-hidden items, restore keys
    ///    for items returned to visible. Denylisted hiding-unsupported items
    ///    are silently skipped.
    /// 2. CGS window move (legacy, no-op on macOS 27).
    /// 3. AX element hide (legacy, no-op on macOS 27).
    /// 4. Position lock — preserve visible items' existing weights, clean up
    ///    ghost keys from dynamic-title apps.
    /// Not private: exposed so tests can drive the orchestration directly
    /// (with fake surgical hiders) without constructing a full `AppState`.
    func applyExperimentalWindowHiding(
        enabled: Bool,
        effectiveAssignment: [String: MenuBarSection.Name],
        allItems: [MenuBarItem],
        backendAssignment: inout [String: MenuBarSection.Name]
    ) {
        let positionsBeforeMutation = positionStore.readPositions()

        // Build the ordered list of surgical hiders to run on this OS version.
        // CGS runs on all versions; AX runs only on macOS < 27 (per plan 012).
        let surgicalHidersToRun: [RuntimeWindowControlling] = {
            var hiders = surgicalHiders
            if #available(macOS 27, *) {
                // AXItemHider is gated out on macOS 27+; drop it from the pipeline.
                hiders = hiders.filter { !($0 is AXItemHider) }
            }
            return hiders
        }()

        guard enabled else {
            positionStore.restoreAll()
            if positionStore.readPositions() != positionsBeforeMutation {
                prefsWatcher?.noteSelfWrite()
            }
            // Call apply with empty PIDs on each surgical hider so any
            // previously-hidden windows/elements get restored.
            for hider in surgicalHidersToRun {
                hider.apply(hiddenPIDs: [], allItems: allItems)
            }
            return
        }

        // Resolve every item to the TrailingItemPreferredPositions key it is
        // actually stored under, once, against a single snapshot taken before
        // the plist pass mutates the dictionary. Dynamic-title apps (iStat
        // Menus) register under a stable internal identifier, so the naive
        // status:<bundle>::<title> key never matches what hideItems/showItems
        // and the position lock operate on — comparing the naive key would
        // leave those items in BOTH the plist-handled set and the assertion
        // input, double-handling them and forcing a whole-bar reflow.
        let positionsSnapshot = positionStore.readPositions()
        let snapshotKeys = Array(positionsSnapshot.keys)
        func resolvedPlistKey(for item: MenuBarItem) -> String {
            RuntimePreferenceKeys.resolveKey(
                for: item,
                existingKeys: snapshotKeys,
                positions: positionsSnapshot,
                liveItems: allItems
            ) ?? RuntimePreferenceKeys.naiveKey(for: item)
        }

        // ── 1. Plist-based hide/show (experimental) ──
        var toHide = [MenuBarItem]()
        var toShow = [MenuBarItem]()
        for item in allItems where Self.isCGSWindowHideable(item) {
            let section = effectiveAssignment[item.uniqueIdentifier] ?? .visible
            if section != .visible {
                toHide.append(item)
            } else if positionStore.hasHiddenItems {
                toShow.append(item)
            }
        }

        var plistHandledKeys = Set<String>()
        if !toHide.isEmpty {
            plistHandledKeys = positionStore.hideItems(toHide)
        }
        if !toShow.isEmpty {
            plistHandledKeys.formUnion(positionStore.showItems(toShow, allItems: allItems))
        }
        if positionStore.readPositions() != positionsBeforeMutation {
            prefsWatcher?.noteSelfWrite()
        }

        // Strip plist-handled items from the assertion input.
        if !plistHandledKeys.isEmpty {
            for item in allItems where Self.isCGSWindowHideable(item) {
                guard (effectiveAssignment[item.uniqueIdentifier] ?? .visible) != .visible else { continue }
                if plistHandledKeys.contains(resolvedPlistKey(for: item)) {
                    backendAssignment.removeValue(forKey: item.uniqueIdentifier)
                }
            }
        }

        // ── 2–3. Surgical passes (CGS → AX) via ordered pipeline ──
        // Collect PIDs of items assigned to a hidden section that are eligible
        // for surgical hiding and not already handled by the plist pass.
        var remainingPIDs = Set<pid_t>()
        for item in allItems where Self.isCGSWindowHideable(item) {
            let section = effectiveAssignment[item.uniqueIdentifier] ?? .visible
            guard section != .visible else { continue }
            if plistHandledKeys.contains(resolvedPlistKey(for: item)) {
                continue
            }
            let pid = item.sourcePID ?? item.ownerPID
            if #available(macOS 27, *) {
                guard item.sourcePID != nil else { continue }
            }
            remainingPIDs.insert(pid)
        }

        // Iterate surgical hiders in order (CGS first, then AX on macOS < 27).
        // Each hider receives the PIDs not yet handled; its handled PIDs are
        // stripped from the backend assignment so the assessment-mode assertion
        // leaves those items alone.
        for hider in surgicalHidersToRun {
            guard !remainingPIDs.isEmpty else { break }
            let handledPIDs = hider.apply(hiddenPIDs: remainingPIDs, allItems: allItems)
            stripSurgicallyHandledPIDs(
                handledPIDs,
                effectiveAssignment: effectiveAssignment,
                allItems: allItems,
                backendAssignment: &backendAssignment
            )
            remainingPIDs.subtract(handledPIDs)
        }

        // ── 4. Position lock — preserve visible items' weights ──
        let visibleItemKeys = Set(
            allItems
                .filter { (effectiveAssignment[$0.uniqueIdentifier] ?? .visible) == .visible }
                .map { resolvedPlistKey(for: $0) }
        )
        let positionsBeforeLock = positionStore.readPositions()
        positionStore.lockVisiblePositions(visibleItemKeys: visibleItemKeys, allItems: allItems)
        if positionStore.readPositions() != positionsBeforeLock {
            prefsWatcher?.noteSelfWrite()
        }
    }

    /// Removes from `backendAssignment` every CGS/AX-hideable item whose owning
    /// PID was handled by a surgical hider, so the assertion allowlist no longer
    /// tries to conceal it (which would re-composite the whole bar). A no-op
    /// when `handledPIDs` is empty.
    private func stripSurgicallyHandledPIDs(
        _ handledPIDs: Set<pid_t>,
        effectiveAssignment: [String: MenuBarSection.Name],
        allItems: [MenuBarItem],
        backendAssignment: inout [String: MenuBarSection.Name]
    ) {
        guard !handledPIDs.isEmpty else { return }
        for item in allItems where Self.isCGSWindowHideable(item) {
            let section = effectiveAssignment[item.uniqueIdentifier] ?? .visible
            guard section != .visible else { continue }
            if handledPIDs.contains(item.sourcePID ?? item.ownerPID) {
                backendAssignment.removeValue(forKey: item.uniqueIdentifier)
            }
        }
    }

    private func restoreVisibleControlItemAfterRestrictionChange() {
        appState?.menuBarManager
            .controlItem(withName: .visible)?
            .restoreVisibleIconAfterRestrictionChange()

        Task { @MainActor [weak appState] in
            try? await Task.sleep(for: .milliseconds(250))
            appState?.menuBarManager
                .controlItem(withName: .visible)?
                .restoreVisibleIconAfterRestrictionChange()
        }
    }
}

extension MenuBarSectionController: HidingStateProviding {}
