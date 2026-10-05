//
//  RuntimeSectionContextAdapter.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa
import MenuBarModel
import PlatformRuntimeKit
import ThawCapture

@MainActor
final class RuntimeSectionContextAdapter: RuntimeSectionContext {
    private weak var appState: AppState?

    /// The settings this component reads. MenuBarEngineConfiguration states
    /// why the engine holds this rather than AppState.
    private var configuration: any MenuBarEngineConfiguration = AppSettings.engineDefaults
    private let diagLog = DiagLog(category: "RuntimeSectionController")

    /// Captured at init so the PRK-facing context can answer menu-open queries
    /// without reaching through the item manager.
    private let menuOpenMonitor: MenuOpenMonitor
    private let onScreenItems: OnScreenItemSnapshot

    init(appState: AppState) {
        self.appState = appState
        configuration = appState.settings
        menuOpenMonitor = appState.itemManager.menuOpenMonitor
        onScreenItems = appState.itemManager.onScreenItemSnapshot
    }

    var experimentalSystemItemHiding: Bool {
        configuration.enableExperimentalSystemItemHiding
    }

    var enableExperimentalOverflowPrevention: Bool {
        configuration.enableExperimentalOverflowPrevention
    }

    var isAlwaysHiddenSectionEnabled: Bool {
        configuration.isAlwaysHiddenSectionEnabled
    }

    var revealFollowingEnabled: Bool {
        Defaults.bool(forKey: .enableExperimentalRevealSystemExtras)
    }

    var tempShowInterval: TimeInterval {
        configuration.tempShowInterval
    }

    var diagnosticsEnabled: Bool {
        return Defaults.bool(forKey: .diagnosticRestrictionSceneProbes)
    }

    func currentLiveItems() -> [MenuBarItem] {
        appState?.itemManager.managedItems ?? []
    }

    func currentLiveItems(for section: MenuBarSectionName) -> [MenuBarItem] {
        appState?.itemManager.managedItems(for: section) ?? []
    }

    func lastOnScreenMenuBarItems() -> [MenuBarItem] {
        onScreenItems.items
    }

    func requestCacheWalk() async {
        await appState?.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
    }

    func noteRestrictionChange() {
        appState?.itemManager.noteRestrictionChange()
    }

    func isAnyMenuBarItemMenuOpen() async -> Bool {
        await menuOpenMonitor.isAnyMenuOpen()
    }

    /// How long the synchronous accessibility walk in freshMenuBarItems()
    /// may hold the main thread.
    ///
    /// The walk runs on the main actor with the event taps, so mouse input
    /// stalls system-wide while it waits. A healthy busy walk takes about 100 ms.
    private static let freshItemsBudget = Duration.milliseconds(150)

    /// The last walk that ran to completion, served when a later one runs out
    /// of time.
    private var lastCompleteMenuBarItems: [MenuBarItem]?

    func freshMenuBarItems() -> [MenuBarItem] {
        let result = MenuBarItemAXProvider.enumerateMenuBarItems(
            option: [],
            deadline: .now + Self.freshItemsBudget
        )

        // Position-store items are recovered here too, or the controller would
        // read them as having left the bar.
        guard result.completed else {
            // The controller reads absence as departure, so never publish a
            // truncated walk; the last complete answer is the safe reading.
            if let lastCompleteMenuBarItems {
                diagLog.warning("freshMenuBarItems: walk incomplete, serving the last complete answer")
                return lastCompleteMenuBarItems
            }
            // No complete answer yet: pay the unbounded walk once.
            diagLog.warning("freshMenuBarItems: no complete answer yet, walking without a budget")
            let full = PositionStoreItemSource.recovering(
                MenuBarItemAXProvider.menuBarItems(option: [])
            )
            lastCompleteMenuBarItems = full
            return full
        }

        // A mid-reveal walk can mint positional ids for MenuBarAgent extras; the
        // provider already restored them, so these are the identities the store resolves.
        let items = PositionStoreItemSource.recovering(result.items)
        lastCompleteMenuBarItems = items
        return items
    }

    func shouldDeferMenuBarMutation() -> Bool {
        appState?.menuBarManager.shouldDeferBarMutation ?? false
    }

    func isThawBarShowing() -> Bool {
        appState?.menuBarManager.thawBarPanel.currentSection != nil
    }

    func isMenuBarHiddenBySystem() -> Bool {
        appState?.menuBarManager.isMenuBarHiddenBySystem ?? false
    }

    func activeMenuBarDisplayID() -> CGDirectDisplayID? {
        // Ask the window server: AppKit is wrong with "Displays have separate
        // Spaces" off and lags after a topology change. The bridge falls back
        // to the main display, so an unbacked id means mid-change.
        guard let displayID = Bridging.getActiveMenuBarDisplayID(),
              connectedDisplayIDs().contains(displayID)
        else {
            return nil
        }
        return displayID
    }

    func connectedDisplayIDs() -> Set<CGDirectDisplayID> {
        Set(NSScreen.screens.map(\.displayID))
    }

    func nativeOverflowObservation(on displayID: CGDirectDisplayID) async -> NativeOverflowObservation {
        await MenuBarItemAXProvider.nativeOverflowObservationConcurrent(on: displayID)
    }

    func restoreVisibleControlItemAfterRestrictionChange() {
        appState?.menuBarManager
            .controlItem(withName: .visible)?
            .restoreVisibleIconAfterRestrictionChange()
    }

    func setRevealHideTransitionActive(_ active: Bool) {
        appState?.menuBarManager.setRevealHideTransitionActive(active)
    }

    func runPostRestrictionSceneProbes() {
        guard diagnosticsEnabled else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await runSceneProbe(reason: "after-apply+0ms")
            try? await Task.sleep(for: .milliseconds(250))
            await runSceneProbe(reason: "after-apply+250ms")
            try? await Task.sleep(for: .milliseconds(750))
            await runSceneProbe(reason: "after-apply+1000ms")
        }
    }

    func synchronizeVisibleItemGeometry(revealing section: MenuBarSectionName) async {
        await appState?.itemManager.synchronizeRevealedOrder(revealing: section)
    }

    func reconcileSectionOrderAfterRecovery(revealing section: MenuBarSectionName) async {
        await appState?.itemManager.reconcileSectionBoundaries(revealing: section)
    }

    func prepareRevealedOrder() {
        appState?.itemManager.applySavedOrderBeforeReveal()
    }

    func mirrorSectionOrder(_ identifiers: [String], for section: MenuBarSectionName) {
        appState?.itemManager.mirrorSectionOrderNow(identifiers, for: section)
    }

    func updateControlItemStates() {
        appState?.menuBarManager.updateControlItemStates()
    }

    func scheduleNativeOverflowRebalance() {
        // The native overflow control appearing is something Thaw observed,
        // not a request to reorder: conceal at once, move nothing.
        appState?.itemManager.scheduleOverflowRebalance(reason: .externalChange, immediate: true)
    }

    func enableAlwaysHiddenSectionRevealIfNeeded() {
        guard let advanced = appState?.settings.advanced else { return }
        if !advanced.enableAlwaysHiddenSection {
            advanced.enableAlwaysHiddenSection = true
        }
    }

    func loadSavedSectionOrder() -> [MenuBarSectionName: [String]] {
        guard let savedOrder = appState?.itemManager.savedSectionOrder else { return [:] }
        return savedOrder.reduce(into: [:]) { result, entry in
            guard let section = MenuBarSectionName(rawValue: entry.key) else { return }
            result[section] = entry.value
        }
    }

    func currentGroupSet() -> MenuBarItemGroupSet {
        appState?.itemGroupManager.groupSet ?? .empty
    }

    private func runSceneProbe(reason: String) async {
        // Concurrent: this probe diagnoses main-thread stalls and must not
        // cause them.
        let items = await MenuBarItemAXProvider.menuBarItemsConcurrent(option: [])
        logMenuBarAgentSequence(reason: reason, items: items)
        logThawAXSequence(reason: reason, items: items)
        logControlItemStates(reason: reason)
        await logControlItemCrops(reason: reason, items: items)
        if reason == "after-apply+250ms" {
            probeHiddenTriggerPressIfEnabled(reason: reason)
        }
    }

    private func logControlItemStates(reason: String) {
        guard let menuBarManager = appState?.menuBarManager else { return }
        for section: MenuBarSectionName in [.visible, .hidden, .alwaysHidden] {
            guard let controlItem = menuBarManager.controlItem(withName: section) else {
                diagLog.info("controlState[\(reason)] \(section.rawValue): nil")
                continue
            }
            diagLog.info("controlState[\(reason)] \(controlItem.diagnosticStateDescription())")
        }
    }

    private func logMenuBarAgentSequence(reason: String, items: [MenuBarItem]) {
        let sequence = MenuBarItem.sortByLeadingEdge(
            items.filter { $0.tag.namespace == .menuBarAgent }
        ).map { item in
            "\(item.uniqueIdentifier) title=\(item.title ?? "nil") frame=\(NSStringFromRect(item.bounds))"
        }
        diagLog.info("menuBarAgentSequence[\(reason)] count=\(sequence.count) \(sequence.joined(separator: " | "))")
    }

    private func logThawAXSequence(reason: String, items: [MenuBarItem]) {
        let sequence = MenuBarItem.sortByLeadingEdge(
            items.filter { item in
                item.tag.namespace == .thaw || item.uniqueIdentifier.contains("Thaw.ControlItem.")
            }
        ).map { item in
            "\(item.uniqueIdentifier) title=\(item.title ?? "nil") frame=\(NSStringFromRect(item.bounds))"
        }
        diagLog.info("thawAXSequence[\(reason)] count=\(sequence.count) \(sequence.joined(separator: " | "))")
    }

    private func logControlItemCrops(reason: String, items: [MenuBarItem]) async {
        let displayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        await ScreenCapture.logMenuBarHostingWindowCandidates(displayID: displayID, reason: reason)

        guard let capture = await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID) else {
            diagLog.warning("controlCrop[\(reason)]: hosting capture unavailable")
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        for identifier in [ControlItemIdentifier.visible, .hidden] {
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
            guard !clippedCropRect.isNull,
                  !clippedCropRect.isEmpty,
                  let cropped = capture.image.cropping(to: clippedCropRect)
            else {
                diagLog.warning("controlCrop[\(reason)] id=\(identifier.rawValue) crop unavailable")
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
        matching identifier: ControlItemIdentifier
    ) -> MenuBarItem? {
        items.first { item in
            item.title == identifier.rawValue ||
                item.uniqueIdentifier.hasSuffix(":\(identifier.rawValue)") ||
                item.uniqueIdentifier == identifier.rawValue
        }
    }

    private func probeHiddenTriggerPressIfEnabled(reason: String) {
        guard Defaults.bool(forKey: .diagnosticRestrictionProbeHiddenTriggerPress) else { return }
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

    private func controlAXElement(matching identifier: ControlItemIdentifier) -> UIElement? {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
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

    private func resolvedAXIdentifier(for element: UIElement) -> String? {
        let attributes = AXHelpers.menuBarChildAttributes(for: element)
        return attributes.identifier?.runtimeNonEmpty
            ?? attributes.children
            .compactMap { AXHelpers.descendantAttributes(for: $0).identifier?.runtimeNonEmpty }
            .first
            ?? attributes.title?.runtimeNonEmpty
    }
}

private extension String {
    var runtimeNonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

extension Notification.Name {
    static let menuBarAgentPositionsDidChange = Notification.Name("menuBarAgentPositionsDidChange")
}

extension Notification.Name {
    /// A layout-bar container became (or stopped being) an active drop target.
    /// UserInfo: section (rawValue String), active (Bool).
    static let layoutBarDragTargetChanged = Notification.Name("layoutBarDragTargetChanged")
}
