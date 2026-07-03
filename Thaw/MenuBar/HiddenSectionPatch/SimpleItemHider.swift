//
//  SimpleItemHider.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import AXSwift
import Cocoa

/// The subset of ``AssessmentModeBackend`` that ``SimpleItemHider`` calls into.
/// Exists so tests can substitute a fake and characterize the orchestration in
/// ``SimpleItemHider`` without touching the real private visibility-restriction
/// assertion.
@MainActor
protocol AssessmentModeBackending: AnyObject {
    var isHidingAvailable: Bool { get }
    @discardableResult
    func apply(sectionAssignment: [String: MenuBarSection.Name], allItems: [MenuBarItem]) -> Bool
    func pulse(sectionAssignment: [String: MenuBarSection.Name], allItems: [MenuBarItem]) -> Bool
    func markExternallyTornDown()
    @discardableResult
    func refreshAvailability() -> Bool
}

extension AssessmentModeBackend: AssessmentModeBackending {}

/// The subset of ``ControlCenterModuleManager`` that ``SimpleItemHider`` calls
/// into.
@MainActor
protocol ControlCenterModuleManaging: AnyObject {
    @discardableResult
    func apply(hiddenMenuExtraTitles titles: Set<String>) -> Bool
}

extension ControlCenterModuleManager: ControlCenterModuleManaging {}

/// The common shape of ``CGSWindowHider`` and ``AXItemHider``: both hide
/// items surgically by PID/window and report which PIDs they actually
/// handled, so ``SimpleItemHider`` can strip them from the next pass. CGS
/// runs first (handles pre-27 macOS where per-item windows exist); AX runs
/// second and catches PIDs CGS could not (gated out on macOS 27 by plan 012,
/// since `AXHidden` isn't settable on hosted menu-bar items there).
@MainActor
protocol SurgicalItemHider: AnyObject {
    @discardableResult
    func apply(hiddenPIDs: Set<pid_t>, allItems: [MenuBarItem]) -> Set<pid_t>
    func restoreAll()
}

extension AXItemHider: SurgicalItemHider {}

extension CGSWindowHider: SurgicalItemHider {
    @discardableResult
    func apply(hiddenPIDs: Set<pid_t>, allItems _: [MenuBarItem]) -> Set<pid_t> {
        apply(hiddenPIDs: hiddenPIDs)
    }
}

/// The subset of ``TrailingItemPositionStore`` that ``SimpleItemHider`` calls
/// into.
@MainActor
protocol TrailingItemPositioning: AnyObject {
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

extension TrailingItemPositionStore: TrailingItemPositioning {}

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
/// The actual hiding is delegated to ``AssessmentModeBackend``: the private
/// visibility-restriction assertion that genuinely removes the icons and reflows
/// the bar. Its allowlist is recomputed from the assignment map. When the private
/// API is unavailable the backend is inert (nothing is hidden) and there is no
/// cosmetic overlay fallback.
///
/// Created only on macOS 27+ (see `MenuBarManager`), so everything it owns is
/// implicitly gated to that OS — macOS 26 keeps its native section machinery.
@MainActor
final class SimpleItemHider: ObservableObject {
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

    private weak var appState: AppState?
    private let diagLog = DiagLog(category: "SimpleItemHider")

    /// Section each item is assigned to, keyed by ``MenuBarItem/uniqueIdentifier``.
    /// Entries equal to `.visible` are omitted (the default), so the map only
    /// holds the hidden / always-hidden items. Published so the settings UI and
    /// layout bars reflect changes.
    @Published private(set) var sectionAssignment: [String: MenuBarSection.Name]

    /// User-chosen left-to-right order of items within each section, set by
    /// layout-bar drags and persisted. The Visible section renders from fresh
    /// AX geometry on macOS 27 so stale saved order cannot drift from the real
    /// menu bar.
    @Published private(set) var sectionItemOrder: [MenuBarSection.Name: [String]]

    /// The currently revealed hidden section, if any. `.hidden` reveals only
    /// Hidden items; `.alwaysHidden` reveals both Hidden and Always-Hidden items.
    @Published private(set) var revealedSection: MenuBarSection.Name?

    /// Mirrors ``AssessmentModeBackend/isHidingAvailable``: whether the private
    /// Assessment Mode assertion API is present on this system. `false` means
    /// reordering still works but hiding is inert — surfaced as a settings
    /// warning. Re-checked on ``NSApplication/didBecomeActiveNotification``
    /// because an OS update could land while the app is running.
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
    private let backend: AssessmentModeBackending

    /// Governs Apple Control Center modules (AirDrop / Focus / User / Now Playing
    /// / WiFi / Bluetooth) that the assessment-mode allowlist cannot hide. Items
    /// it owns are hidden via their Control Center preference and kept out of the
    /// backend input.
    private let ccModuleManager: ControlCenterModuleManaging

    /// Off-screen CGS window hider. When the experimental window
    /// hiding flag is on, third-party items are hidden by moving their windows
    /// off-screen via CGS instead of the assessment-mode assertion, so hiding one
    /// item no longer reflows the bar and ghosts dynamic neighbors like iStat.
    private let cgsWindowHider: SurgicalItemHider

    /// AX-based item hider. On macOS 27 per-item CG windows don't exist, so the
    /// CGS hider cannot operate. This hider sets `AXHidden` on each item's AX
    /// element instead — hiding items
    /// surgically without whole-bar reflow.
    ///
    /// Note: AXHidden is not settable on macOS 27 menu-bar items; this hider is
    /// kept for diagnostics but is effectively a no-op there.
    private let axItemHider: SurgicalItemHider

    /// The two surgical passes, in the fixed order `applyExperimentalWindowHiding`
    /// runs them: CGS first, then AX. Both conform to `SurgicalItemHider`, but
    /// the orchestration below still calls them by name rather than looping
    /// over this array, because the AX pass carries an extra macOS-version
    /// gate (plan 012) that isn't part of the shared protocol. Exposed so
    /// tests can assert the ordering without duplicating that gating logic.
    var surgicalHiders: [SurgicalItemHider] {
        [cgsWindowHider, axItemHider]
    }

    /// Position lock for visible items. On macOS 27 the assessment-mode
    /// assertion re-composites the whole bar, ghosting dynamic neighbors (iStat).
    /// Writing visible items' current positions to `TrailingItemPreferredPositions`
    /// before the assertion fires tells MenuBarAgent to anchor them in place
    /// during reflow, preventing the ghosting.
    private let positionStore: TrailingItemPositioning

    private var timer: Timer?
    private var boundaryReconciliationTask: Task<Void, Never>?
    private var lastRefreshSignature: String?

    convenience init(appState: AppState) {
        self.init(
            appState: appState,
            backend: AssessmentModeBackend(),
            ccModuleManager: ControlCenterModuleManager(),
            cgsWindowHider: CGSWindowHider(),
            axItemHider: AXItemHider(),
            positionStore: TrailingItemPositionStore()
        )
    }

    /// Designated initializer. Production code always goes through
    /// ``init(appState:)`` above, which supplies the real collaborators; this
    /// entry point exists so tests can substitute fakes for the five
    /// collaborators and characterize ``SimpleItemHider``'s instance lifecycle
    /// without touching the private visibility-restriction assertion, Control
    /// Center, CGS, AX, or `TrailingItemPreferredPositions`.
    init(
        appState: AppState?,
        backend: AssessmentModeBackending,
        ccModuleManager: ControlCenterModuleManaging,
        cgsWindowHider: SurgicalItemHider,
        axItemHider: SurgicalItemHider,
        positionStore: TrailingItemPositioning
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
        self.isHidingAvailable = backend.isHidingAvailable
        Bridging.logSystemMenuBarWindows()
        diagLog.info("hiding backend: AssessmentMode (\(isHidingAvailable ? "available" : "unavailable")); \(sectionAssignment.count) assigned item(s)")
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
    }

    isolated deinit {
        timer?.invalidate()
        boundaryReconciliationTask?.cancel()
        for task in temporaryRevealConcealTasks.values {
            task.cancel()
        }
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    /// Re-checks whether the private assertion API is available and updates
    /// ``isHidingAvailable``. Called on init and again on
    /// `NSApplication.didBecomeActiveNotification`, since an OS update could
    /// land (or, in principle, be reverted) while the app keeps running.
    func refreshHidingAvailability() {
        let available = backend.refreshAvailability()
        guard available != isHidingAvailable else { return }
        isHidingAvailable = available
        diagLog.info("hiding availability changed: \(available ? "available" : "unavailable")")
    }

    /// Logs a one-time diagnostic error at launch when hiding is unavailable on
    /// macOS 27+. Subsequent activation rechecks update ``isHidingAvailable``
    /// silently (see ``refreshHidingAvailability()``) without repeating this.
    private func logUnavailabilityAtLaunchIfNeeded() {
        guard #available(macOS 27, *), !isHidingAvailable, !hasLoggedUnavailableAtLaunch else { return }
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

    /// Drops assignments that can never be valid hidden-section entries.
    static func sanitizedSectionAssignment(
        _ assignment: [String: MenuBarSection.Name]
    ) -> [String: MenuBarSection.Name] {
        assignment.filter { identifier, section in
            section != .visible &&
                !isControlItemAssignmentIdentifier(identifier) &&
                !isOwnAppAssignmentIdentifier(identifier) &&
                !isHidingUnsupportedAssignmentIdentifier(identifier)
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
                    sectionAssignment[$0.uniqueIdentifier] != nil
                        && (Self.isProtectedAssignmentItem(
                            $0,
                            experimentalSystemItemHiding: experimentalSystemItemHiding
                        )
                            || !Self.canAssign(
                                $0,
                                to: sectionAssignment[$0.uniqueIdentifier] ?? .visible,
                                experimentalSystemItemHiding: experimentalSystemItemHiding
                            ))
                }
                .map(\.uniqueIdentifier)
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
    func show(
        _ section: MenuBarSection.Name,
        reconcileBoundary: Bool = true
    ) {
        if !reconcileBoundary {
            boundaryReconciliationTask?.cancel()
            boundaryReconciliationTask = nil
        }
        guard let target = Self.revealTarget(for: section), revealedSection != target else {
            return
        }
        revealedSection = target
        diagLog.info("show(\(target.rawValue)); temporarily revealing assigned item(s)")
        refresh()

        guard reconcileBoundary else { return }

        // Existing assignments created by earlier macOS 27 builds may never
        // have crossed a physical divider. Once their AX elements reappear,
        // repair that persisted layout so the revealed bar is always:
        // Hidden < divider < Visible.
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
            await appState.itemManager.reconcileMacOS27SectionBoundaries(
                revealing: target
            )
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

        guard !order.isEmpty else {
            return items
        }

        let canonicalOrder = MenuBarItemTag.canonicalPersistentIdentifiers(order)
        let rank = Dictionary(canonicalOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated().sorted { lhs, rhs in
            let lr = rank[lhs.element.uniqueIdentifier] ?? (canonicalOrder.count + lhs.offset)
            let rr = rank[rhs.element.uniqueIdentifier] ?? (canonicalOrder.count + rhs.offset)
            return lr < rr
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
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    /// The section the item with the given identifier is assigned to.
    func section(for identifier: String) -> MenuBarSection.Name {
        sectionAssignment[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] ?? .visible
    }

    /// The section for a live item. System anchors and any item Thaw can't
    /// conceal are always visible even if stale defaults say otherwise.
    func section(for item: MenuBarItem) -> MenuBarSection.Name {
        let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
        if (item.sectionManagementPolicy.isForcedVisible && !experimentalSystemItemHiding) ||
            Self.isOwnAppItem(item)
        {
            return .visible
        }
        return section(for: item.uniqueIdentifier)
    }

    /// Assigns the item to a section. Dropping it back into `.visible` removes
    /// the entry (the default). Persists and re-applies the restriction.
    func setSection(_ section: MenuBarSection.Name, identifier: String) {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
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
        Set(sectionAssignment.keys.compactMap { snapshots[$0]?.tag })
    }

    private func refreshSignature(
        allItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        experimentalWindowHiding: Bool,
        experimentalOverflowPrevention: Bool
    ) -> String {
        [
            "assignment=\(sectionAssignment.map { "\($0.key)=\($0.value.rawValue)" }.sorted().joined(separator: ","))",
            "revealed=\(revealedSection?.rawValue ?? "none")",
            "temporary=\(temporarilyRevealedIDs.sorted().joined(separator: ","))",
            "items=\(allItems.map(\.uniqueIdentifier).sorted().joined(separator: ","))",
            "system=\(experimentalSystemItemHiding)",
            "window=\(experimentalWindowHiding)",
            "overflow=\(experimentalOverflowPrevention)",
        ].joined(separator: "|")
    }

    /// Re-applies the current assignment against the live item cache, and
    /// refreshes the retained snapshots.
    func refresh() {
        guard let appState else { return }
        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        let experimentalWindowHiding = appState.settings.advanced.enableExperimentalWindowHiding
        let experimentalOverflowPrevention = appState.settings.advanced.enableExperimentalOverflowPrevention
        let allItems = appState.itemManager.itemCache.managedItems
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
            experimentalWindowHiding: experimentalWindowHiding,
            experimentalOverflowPrevention: experimentalOverflowPrevention
        )
        guard signature != lastRefreshSignature else { return }
        lastRefreshSignature = signature

        // Snapshot every assigned item while it's still live, so it can keep
        // appearing in the layout bars after it's concealed. Drop snapshots for
        // items that are no longer assigned.
        for item in allItems where sectionAssignment[item.uniqueIdentifier] != nil {
            snapshots[item.uniqueIdentifier] = item
        }
        snapshots = snapshots.filter { sectionAssignment[$0.key] != nil }
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
        for (identifier, section) in sectionAssignment where section != .visible {
            if let title = ControlCenterModuleManager.governableMenuExtraTitle(forItemIdentifier: identifier) {
                ccHiddenTitles.insert(title)
            }
        }
        ccModuleManager.apply(hiddenMenuExtraTitles: ccHiddenTitles)

        // Strip CC modules from the backend input regardless of
        // reveal state (they are handled by their dedicated managers above).
        var backendAssignment = backendAssignmentInput()

        // Experimental: hide third-party items surgically (CGS window move, then
        // AX hide, then visible-position lock) instead of the assessment-mode
        // assertion, which re-composites the WHOLE bar and ghosts dynamic
        // neighbors like iStat. Items a surgical hider took over are stripped
        // from `backendAssignment` so the assertion leaves them alone. See
        // ``applyExperimentalWindowHiding`` for the strategy and the off-path
        // teardown. When the flag is off this is a no-op except for restoring
        // anything a previous on-state stranded off-screen / AX-hidden / locked.
        applyExperimentalWindowHiding(
            enabled: appState.settings.advanced.enableExperimentalWindowHiding,
            effectiveAssignment: effectiveAssignment,
            allItems: allItems,
            backendAssignment: &backendAssignment
        )

        logRestrictionProbeSnapshot(reason: "before-apply", items: allItems)
        let didChangeRestriction = backend.apply(
            sectionAssignment: backendAssignment,
            allItems: allItems
        )
        if didChangeRestriction {
            appState.itemManager.noteRestrictionChange()
            restoreVisibleControlItemAfterRestrictionChange()
            diagLog.info("restriction changed; restored visible control item state")
            runPostRestrictionSceneProbes()
            // Experimental overflow prevention: push hidden items' position
            // weights to extreme values so the native macOS 27 menu bar
            // overflow (notched displays) collapses them before visible items.
            applyExperimentalOverflowPreventionIfEnabled(allItems: allItems)
            // Post-assertion safety net: verify denylisted hiding-unsupported
            // items are still visible after the restriction reflow. Runs async
            // so the main thread isn't blocked by a fresh AX walk on every refresh.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.verifyHidingUnsupportedItemsVisiblePostAssertion()
            }
        }
    }

    /// Re-enumerates from AX after the assertion fires and tears down the
    /// restriction if any denylisted hiding-unsupported item has become
    /// invisible. Uses a fresh AX snapshot — the pre-assertion `allItems`
    /// cache has stale `isOnScreen` values.
    private func verifyHidingUnsupportedItemsVisiblePostAssertion() {
        guard #available(macOS 27, *),
              AssessmentModeBackend.isAvailable,
              !MenuBarItemTag.hidingUnsupportedBundleIDs.isEmpty
        else { return }

        let freshItems = MenuBarItemAXProvider.menuBarItems(option: [])

        let unsupportedItems = freshItems.filter { item in
            item.tag.isHidingUnsupported
        }

        let invisible = unsupportedItems.filter { !$0.isOnScreen }
        guard !invisible.isEmpty else { return }

        // Also check against the known bundle IDs: are any denylisted
        // hiding-unsupported bundles absent from the fresh enumeration entirely?
        // The assertion can remove items from AX visibility, so a bundle with
        // zero visible items in the fresh snapshot is also a signal.
        let unsupportedBundleIDs = MenuBarItemTag.hidingUnsupportedBundleIDs
        let visibleBundleIDs = Set(freshItems.compactMap { item in
            MenuBarItemTag.hidingUnsupportedBundleIDs.contains(where: {
                item.tag.namespace.description == $0
            }) ? item.tag.namespace.description : nil
        })
        let fullyAbsent = unsupportedBundleIDs.subtracting(visibleBundleIDs)

        if !invisible.isEmpty || !fullyAbsent.isEmpty {
            diagLog.error(
                "Post-assertion guard: \(invisible.count) denylisted hiding-unsupported item(s) " +
                    "invisible, \(fullyAbsent.count) bundle(s) absent — " +
                    "tearing down restriction. Invisible: " +
                    invisible.map { "\($0.uniqueIdentifier) onScreen=\($0.isOnScreen)" }.joined(separator: ", ") +
                    ". Absent: \(fullyAbsent.sorted().joined(separator: ", "))"
            )
            resetBackendRestriction()
        }
    }

    private func resetBackendRestriction() {
        backend.markExternallyTornDown()
        backend.apply(sectionAssignment: [:], allItems: [])
    }

    /// Experimental: pushes hidden items' position weights to extreme values
    /// (50000+) in `TrailingItemPreferredPositions` so the native macOS 27 menu
    /// bar overflow on notched displays collapses them before visible items.
    /// Items moved back to visible get their weights restored.
    private func applyExperimentalOverflowPreventionIfEnabled(allItems: [MenuBarItem]) {
        guard let appState,
              appState.settings.advanced.enableExperimentalOverflowPrevention
        else { return }
        guard !appState.menuBarManager.shouldDeferMacOS27MenuBarMutation else {
            diagLog.debug("Skipping experimental overflow prevention: native menu bar unavailable/transitioning")
            return
        }

        var positions = positionStore.readPositions()
        let existingKeys = Array(positions.keys)
        var changed = false
        let maxElevated = positions.values.filter { $0 >= 50000 }.max()
        var overflowBase = maxElevated.map { $0 + 10 } ?? 50000

        for (identifier, section) in sectionAssignment where section != .visible {
            guard let item = allItems.first(where: { $0.uniqueIdentifier == identifier }) ??
                snapshots[identifier]
            else { continue }

            guard let key = TrailingItemPositionStore.resolvedPositionKey(
                for: item,
                existingKeys: existingKeys
            ) ?? TrailingItemPositionStore.resolvePositionalKey(
                for: item,
                existingKeys: existingKeys,
                positions: positions,
                allItems: allItems
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
        diagLog.info("overflowPrevention: elevated \(overflowBase - 50000) hidden-item weight(s)")
    }

    /// Re-applies the current assertion allowlist without changing assignment.
    /// Used after reflow collateral leaves allowed bundles invisible at on-band
    /// AX coordinates (synthetic drags cannot recover those).
    @discardableResult
    func pulseRestrictionAfterReflow(liveItems: [MenuBarItem]) -> Bool {
        guard AssessmentModeBackend.isAvailable else { return false }
        guard sectionAssignment.values.contains(where: { $0 == .hidden || $0 == .alwaysHidden }) else {
            return false
        }

        let backendAssignment = backendAssignmentInput()
        logRestrictionProbeSnapshot(reason: "before-pulse", items: liveItems)
        let didPulse = backend.pulse(
            sectionAssignment: backendAssignment,
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
            where ControlCenterModuleManager.isGovernable(itemIdentifier: identifier)
        {
            backendAssignment.removeValue(forKey: identifier)
        }
        return backendAssignment
    }

    /// Assignment applied to hiding backends after removing single-item reveals.
    private func effectiveAssignmentExcludingTemporarilyRevealed() -> [String: MenuBarSection.Name] {
        Self.effectiveSectionAssignment(
            sectionAssignment,
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
        // Build the ordered list of surgical hiders to run on this OS version.
        // CGS runs on all versions; AX runs only on macOS < 27 (per plan 012).
        let surgicalHidersToRun: [SurgicalItemHider] = {
            var hiders = surgicalHiders
            if #available(macOS 27, *) {
                // AXItemHider is gated out on macOS 27+; drop it from the pipeline.
                hiders = hiders.filter { !($0 is AXItemHider) }
            }
            return hiders
        }()

        guard enabled else {
            positionStore.restoreAll()
            // Call apply with empty PIDs on each surgical hider so any
            // previously-hidden windows/elements get restored.
            for hider in surgicalHidersToRun {
                hider.apply(hiddenPIDs: [], allItems: allItems)
            }
            return
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

        // Strip plist-handled items from the assertion input.
        if !plistHandledKeys.isEmpty {
            for item in allItems where Self.isCGSWindowHideable(item) {
                guard (effectiveAssignment[item.uniqueIdentifier] ?? .visible) != .visible else { continue }
                if plistHandledKeys.contains(TrailingItemPositionStore.key(for: item)) {
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
            if plistHandledKeys.contains(TrailingItemPositionStore.key(for: item)) { continue }
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
                .map { TrailingItemPositionStore.key(for: $0) }
        )
        positionStore.lockVisiblePositions(visibleItemKeys: visibleItemKeys, allItems: allItems)
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

    private var shouldRunAssessmentModeSceneProbes: Bool {
        guard #available(macOS 27, *) else {
            return false
        }
        return Defaults.bool(forKey: .diagnosticAssessmentModeSceneProbes)
    }

    private func logRestrictionProbeSnapshot(reason: String, items: [MenuBarItem]) {
        guard shouldRunAssessmentModeSceneProbes else {
            return
        }
        logMenuBarAgentSequence(reason: reason, items: items)
        logThawAXSequence(reason: reason, items: items)
        logControlItemStates(reason: reason)
    }

    private func runPostRestrictionSceneProbes() {
        guard shouldRunAssessmentModeSceneProbes else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard #available(macOS 27, *) else { return }
            await runSceneProbe(reason: "after-apply+0ms")
            try? await Task.sleep(for: .milliseconds(250))
            await runSceneProbe(reason: "after-apply+250ms")
            try? await Task.sleep(for: .milliseconds(750))
            await runSceneProbe(reason: "after-apply+1000ms")
        }
    }

    @available(macOS 27, *)
    private func runSceneProbe(reason: String) async {
        let items = MenuBarItemAXProvider.menuBarItems(option: [])
        logRestrictionProbeSnapshot(reason: reason, items: items)
        await logControlItemCrops(reason: reason, items: items)
        if reason == "after-apply+250ms" {
            probeHiddenTriggerPressIfEnabled(reason: reason)
        }
    }

    private func logControlItemStates(reason: String) {
        guard let menuBarManager = appState?.menuBarManager else {
            return
        }

        for section: MenuBarSection.Name in [.visible, .hidden, .alwaysHidden] {
            guard let controlItem = menuBarManager.controlItem(withName: section) else {
                diagLog.info("controlState[\(reason)] \(section.rawValue): nil")
                continue
            }
            diagLog.info("controlState[\(reason)] \(controlItem.diagnosticStateDescription())")
        }
    }

    private func logMenuBarAgentSequence(reason: String, items: [MenuBarItem]) {
        let sequence = items
            .filter { $0.tag.namespace == .menuBarAgent }
            .sorted { $0.bounds.minX < $1.bounds.minX }
            .map { item in
                "\(item.uniqueIdentifier) title=\(item.title ?? "nil") frame=\(NSStringFromRect(item.bounds))"
            }
        diagLog.info("menuBarAgentSequence[\(reason)] count=\(sequence.count) \(sequence.joined(separator: " | "))")
    }

    private func logThawAXSequence(reason: String, items: [MenuBarItem]) {
        let sequence = items
            .filter { item in
                item.tag.namespace == .thaw || item.uniqueIdentifier.contains("Thaw.ControlItem.")
            }
            .sorted { $0.bounds.minX < $1.bounds.minX }
            .map { item in
                "\(item.uniqueIdentifier) title=\(item.title ?? "nil") frame=\(NSStringFromRect(item.bounds))"
            }
        diagLog.info("thawAXSequence[\(reason)] count=\(sequence.count) \(sequence.joined(separator: " | "))")
    }

    @available(macOS 27, *)
    private func logControlItemCrops(reason: String, items: [MenuBarItem]) async {
        let displayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        await ScreenCapture.logMenuBarHostingWindowCandidates(displayID: displayID, reason: reason)

        guard let capture = await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID) else {
            diagLog.warning("controlCrop[\(reason)]: hosting capture unavailable")
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        for identifier in [ControlItem.Identifier.visible, .hidden] {
            guard let item = controlItem(in: items, matching: identifier) else {
                diagLog.info("controlCrop[\(reason)] id=\(identifier.rawValue): missing from fresh AX items")
                continue
            }

            let cropRect = CGRect(
                x: (item.bounds.minX - capture.windowFrame.minX) * capture.scale,
                y: (item.bounds.minY - capture.windowFrame.minY) * capture.scale,
                width: item.bounds.width * capture.scale,
                height: item.bounds.height * capture.scale
            ).integral
            let clippedCropRect = cropRect.intersection(imageBounds)

            guard !clippedCropRect.isNull, !clippedCropRect.isEmpty else {
                diagLog.warning(
                    "controlCrop[\(reason)] id=\(identifier.rawValue) crop outside host " +
                        "axFrame=\(NSStringFromRect(item.bounds)) crop=\(NSStringFromRect(cropRect))"
                )
                continue
            }

            guard let cropped = capture.image.cropping(to: clippedCropRect) else {
                diagLog.warning(
                    "controlCrop[\(reason)] id=\(identifier.rawValue) crop failed " +
                        "axFrame=\(NSStringFromRect(item.bounds)) crop=\(NSStringFromRect(clippedCropRect))"
                )
                continue
            }

            diagLog.info(
                "controlCrop[\(reason)] id=\(identifier.rawValue) " +
                    "axFrame=\(NSStringFromRect(item.bounds)) crop=\(NSStringFromRect(clippedCropRect)) " +
                    "size=\(cropped.width)x\(cropped.height) transparent=\(cropped.isTransparent())"
            )
        }
    }

    private func controlItem(
        in items: [MenuBarItem],
        matching identifier: ControlItem.Identifier
    ) -> MenuBarItem? {
        items.first { item in
            item.title == identifier.rawValue ||
                item.uniqueIdentifier.hasSuffix(":\(identifier.rawValue)") ||
                item.uniqueIdentifier == identifier.rawValue
        }
    }

    @available(macOS 27, *)
    private func probeHiddenTriggerPressIfEnabled(reason: String) {
        guard Defaults.bool(forKey: .diagnosticAssessmentModeProbeHiddenTriggerPress) else {
            return
        }

        guard let element = controlAXElement(matching: .hidden) else {
            diagLog.warning("hiddenTriggerAXPress[\(reason)]: element not found")
            return
        }

        let frame = AXHelpers.frame(for: element).map(NSStringFromRect) ?? "nil"
        let enabled = AXHelpers.enabledAttribute(element).map(String.init) ?? "nil"
        let role = AXHelpers.role(for: element).map { "\($0)" } ?? "nil"
        let didPress = AXHelpers.press(element)
        diagLog.info(
            "hiddenTriggerAXPress[\(reason)]: didPress=\(didPress) " +
                "role=\(role) enabled=\(enabled) frame=\(frame)"
        )
    }

    @available(macOS 27, *)
    private func controlAXElement(matching identifier: ControlItem.Identifier) -> UIElement? {
        guard
            let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                Constants.isThawOwnedBundleIdentifier($0.bundleIdentifier)
            }),
            let app = AXHelpers.application(for: runningApp),
            let extrasMenuBar = AXHelpers.extrasMenuBar(for: app)
        else {
            return nil
        }

        return AXHelpers.children(for: extrasMenuBar).first { child in
            resolvedAXIdentifier(for: child) == identifier.rawValue
        }
    }

    @available(macOS 27, *)
    private func resolvedAXIdentifier(for element: UIElement) -> String? {
        AXHelpers.identifier(for: element)?.nonEmpty
            ?? AXHelpers.children(for: element)
            .lazy
            .compactMap { AXHelpers.identifier(for: $0)?.nonEmpty }
            .first
            ?? AXHelpers.title(for: element)?.nonEmpty
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
