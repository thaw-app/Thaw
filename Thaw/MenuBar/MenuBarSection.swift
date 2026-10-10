//
//  MenuBarSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import os
import QuartzCore

@MainActor
final class MenuBarSection {
    typealias Name = MenuBarSectionName

    let name: Name

    let controlItem: ControlItem

    private weak var appState: AppState?

    /// Captured at setup so rehide reads menu state without reaching through the item manager.
    private var menuOpenMonitor: MenuOpenMonitor?

    /// Engine-facing settings; see MenuBarEngineConfiguration for the dependency boundary.
    private var configuration: any MenuBarEngineConfiguration = AppSettings.engineDefaults

    private var rehideTask: Task<Void, Never>?

    /// Starts rehide when the mouse leaves the menu bar.
    private var rehideMonitor: EventMonitor?

    private nonisolated let diagLog = DiagLog(category: "MenuBarSection")

    private var useThawBar: Bool {
        guard let appState else { return false }
        let screen = screenForThawBar
        let displayID = screen?.displayID ?? CGMainDisplayID()
        return appState.menuBarManager.shouldUseThawBar(for: displayID)
    }

    /// The gap that macOS leaves to the left and right of the notch (in points).
    static nonisolated let notchGap = MenuBarCapacitySnapshot.notchGap

    /// The preferred way to present the section on the menu bar.
    nonisolated enum PresentationMode: Equatable {
        /// Show the items inline without modifying the application menus.
        case inline
        /// Show the items inline, but only after hiding the application menus.
        case inlineHidingApplicationMenus
        /// Fall back to the Thaw Bar.
        case thawBar
    }

    /// Hiding app menus may recover enough space for inline presentation.
    static nonisolated func presentationMode(
        totalItemsWidth: CGFloat,
        capacity: MenuBarCapacitySnapshot,
        allowHidingApplicationMenus: Bool
    ) -> PresentationMode {
        if let inlineWidth = capacity.availableWidth(
            in: .inline,
            applicationMenus: .visible
        ), totalItemsWidth <= inlineWidth {
            return .inline
        }

        guard allowHidingApplicationMenus else {
            return .thawBar
        }

        if let inlineWidthWithoutAppMenus = capacity.availableWidth(
            in: .inline,
            applicationMenus: .hidden
        ), totalItemsWidth <= inlineWidthWithoutAppMenus {
            return .inlineHidingApplicationMenus
        }

        return .thawBar
    }

    /// Unknown free width keeps inline reveal as the default, even when hiding app menus is allowed.
    static nonisolated func overflowsInline(
        totalItemsWidth: CGFloat,
        capacity: MenuBarCapacitySnapshot,
        allowHidingApplicationMenus: Bool
    ) -> Bool {
        let menus: MenuBarCapacitySnapshot.ApplicationMenus = allowHidingApplicationMenus ? .hidden : .visible
        guard let width = capacity.availableWidth(in: .inline, applicationMenus: menus) else {
            return false
        }
        return totalItemsWidth > width
    }

    /// Inline items behind the native overflow chevron would be unreachable.
    func overflowsInline(on screen: NSScreen) -> Bool {
        guard let appState else { return false }
        let capacity = MenuBarCapacitySnapshot.capture(
            on: screen,
            items: appState.itemManager.managedItems,
            overflowControlBounds: appState.menuBarManager.sectionController
                .nativeOverflowControlBounds(on: screen.displayID)
        )
        return Self.overflowsInline(
            totalItemsWidth: totalItemsWidthToShow(),
            capacity: capacity,
            allowHidingApplicationMenus: configuration.hideApplicationMenus
        )
    }

    private func totalItemsWidthToShow() -> CGFloat {
        guard let appState else { return 0 }

        let hiddenItems = appState.itemManager.itemCache[Name.hidden]
        let visibleItems = appState.itemManager.itemCache[Name.visible]
            .filter { $0.tag != .controlCenter }
        let hiddenWidth = hiddenItems.reduce(0) { acc, item in acc + item.bounds.width }
        let visibleWidth = visibleItems.reduce(0) { acc, item in acc + item.bounds.width }

        switch name {
        case .visible, .hidden:
            return hiddenWidth + visibleWidth
        case .alwaysHidden:
            let alwaysHiddenItems = appState.itemManager.itemCache[Name.alwaysHidden]
            let alwaysHiddenWidth = alwaysHiddenItems.reduce(0) { acc, item in acc + item.bounds.width }
            return alwaysHiddenWidth + hiddenWidth + visibleWidth
        }
    }

    func presentationMode(on screen: NSScreen) -> PresentationMode {
        guard let appState else { return .thawBar }
        let items = appState.itemManager.managedItems
        let overflowBounds = appState.menuBarManager.sectionController
            .nativeOverflowControlBounds(on: screen.displayID)
        let capacity = MenuBarCapacitySnapshot.capture(
            on: screen,
            items: items,
            overflowControlBounds: overflowBounds
        )

        return Self.presentationMode(
            totalItemsWidth: totalItemsWidthToShow(),
            capacity: capacity,
            allowHidingApplicationMenus: configuration.hideApplicationMenus
        )
    }

    private weak var menuBarManager: MenuBarManager? {
        appState?.menuBarManager
    }

    /// Use the active menu bar's screen so icon clicks activate their popups.
    private weak var screenForThawBar: NSScreen? {
        NSScreen.screenWithActiveMenuBar ?? NSScreen.main
    }

    /// The hiding state the user desires for the section.
    var desiredState: ControlItem.HidingState = .hideSection

    var isHidden: Bool {
        // An open Thaw Bar counts as revealed even while the assertion conceals its items.
        // A second click must close it, not rerun prewarm and flash hidden items.
        let presentedName = name == .alwaysHidden ? Name.alwaysHidden : Name.hidden
        if let panel = menuBarManager?.thawBarPanel,
           panel.presentation == .section,
           panel.currentSection == presentedName
        {
            return false
        }
        return appState?.menuBarManager.sectionController.isSectionHidden(name) ?? true
    }

    /// Visible and Hidden stay enabled even with zero-width controls because layout bars drive assignments.
    /// Always Hidden requires user opt-in.
    var isEnabled: Bool {
        switch name {
        case .visible, .hidden:
            true
        case .alwaysHidden:
            configuration.isAlwaysHiddenSectionEnabled
        }
    }

    var hotkey: Hotkey? {
        guard let hotkeys = appState?.settings.hotkeys else {
            return nil
        }
        return switch name {
        case .visible: nil
        case .hidden: hotkeys.hotkey(withAction: .toggleHiddenSection)
        case .alwaysHidden: hotkeys.hotkey(withAction: .toggleAlwaysHiddenSection)
        }
    }

    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
    }

    convenience init(name: Name) {
        let controlItem = switch name {
        case .visible:
            ControlItem(identifier: .visible)
        case .hidden:
            ControlItem(identifier: .hidden)
        case .alwaysHidden:
            ControlItem(identifier: .alwaysHidden)
        }
        self.init(name: name, controlItem: controlItem)
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        configuration = appState.settings
        menuOpenMonitor = appState.itemManager.menuOpenMonitor
        controlItem.performSetup(with: appState)
        desiredState = controlItem.state
    }

    /// Flush appearance synchronously after assertion swaps; deferred divider width changes cause two animated reflows.
    /// - Parameter screen: Screen to update for; nil selects the best screen automatically.
    func updateControlItemState(for screen: NSScreen? = nil) {
        guard let appState else { return }

        if desiredState == .showSection {
            controlItem.state = .showSection
            controlItem.applyAppearanceNow()
            return
        }

        // Use screenWithMouse to react immediately when switching displays.
        guard let activeScreen = screen ?? NSScreen.screenWithMouse ?? NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            controlItem.state = desiredState
            controlItem.applyAppearanceNow()
            return
        }

        let displaySettings = appState.settings.displaySettings
        let useThawBar = appState.menuBarManager.shouldUseThawBar(for: activeScreen.displayID)

        // Apply alwaysShowHiddenItems only when the mouse and active menu bar share a screen.
        let alwaysShow: Bool = if let menuBarScreen = NSScreen.screenWithActiveMenuBar,
                                  menuBarScreen.displayID == NSScreen.screenWithMouse?.displayID
        {
            displaySettings.alwaysShowHiddenItems(for: menuBarScreen.displayID)
        } else {
            false
        }

        if alwaysShow, !useThawBar {
            controlItem.state = .showSection
        } else {
            controlItem.state = desiredState
        }
        controlItem.applyAppearanceNow()
    }

    func show(triggeredByHotkey: Bool = false, forcingInline: Bool = false) {
        // User reveals own the state; a racing capture prewarm must leave the section open.
        menuBarManager?.noteUserRevealOwnership()
        // Only the hover path marks its reveal after return to select the shorter hover hide.
        appState?.hidEventManager.isHoverReveal = false
        guard let menuBarManager, isEnabled, isHidden else {
            if name == .alwaysHidden {
                diagLog.debug("show(alwaysHidden) aborted: menuBarManager=\(self.menuBarManager != nil), isEnabled=\(isEnabled), isHidden=\(isHidden)")
            }
            return
        }

        menuBarManager.updateLastShowTimestamp()

        // ThawBarPanel captures glyphs during a brief reveal and forwards clicks through revealClickAndConceal.
        // Use it when requested or when inline items would be unreachable behind native overflow.
        let overflowsInline = !useThawBar && (screenForThawBar.map { overflowsInline(on: $0) } ?? false)
        if overflowsInline {
            diagLog.info("show(\(name.logString)): the items do not fit inline; using the Thaw Bar")
        }
        if !forcingInline, useThawBar || overflowsInline, let screen = screenForThawBar {
            for section in menuBarManager.sections {
                section.desiredState = section.name == .visible ? .showSection : .hideSection
                section.updateControlItemState(for: nil)
            }
            menuBarManager.thawBarPanel.show(
                section: name == .alwaysHidden ? .alwaysHidden : .hidden,
                on: screen,
                triggeredByHotkey: triggeredByHotkey
            )
            startRehideChecks()
            return
        }

        menuBarManager.thawBarPanel.close()
        menuBarManager.sectionController.show(name)
        switch name {
        case .visible, .hidden:
            for section in menuBarManager.sections {
                section.desiredState = section.name == .alwaysHidden ? .hideSection : .showSection
                section.updateControlItemState(for: nil)
            }
        case .alwaysHidden:
            for section in menuBarManager.sections {
                section.desiredState = .showSection
                section.updateControlItemState(for: nil)
            }
        }
        showThawBarOnlyCompanionIfNeeded()
        refreshRevealedItemImages()
        startRehideChecks()
    }

    /// Inline reveal cannot reach Thaw Bar Only items; show a companion bar that closes with the reveal.
    private func showThawBarOnlyCompanionIfNeeded() {
        guard let appState, let menuBarManager,
              name != .visible,
              appState.settings.general.showThawBarOnlyWithInlineReveal,
              !appState.itemManager.thawBarOnlyItems.isEmpty,
              let screen = screenForThawBar
        else { return }
        menuBarManager.thawBarPanel.show(section: .hidden, on: screen, presentation: .alongsideReveal)
    }

    /// Capture glyphs while the section is revealed to replace app-icon fallbacks in layout and search.
    private func refreshRevealedItemImages() {
        guard let appState else { return }
        let revealedName = name == .alwaysHidden ? Name.alwaysHidden : Name.hidden
        let sections: [Name] = revealedName == .alwaysHidden
            ? Name.allCases
            : [.visible, .hidden]

        Task { @MainActor [weak appState] in
            // Wait for revealed AX elements before capture.
            // Skip boundary repair: preferred-position writes invalidate Thaw's hit target.
            try? await Task.sleep(for: .milliseconds(500))
            guard
                let appState,
                !Task.isCancelled,
                appState.menuBarManager.sectionController.revealedSection == revealedName
            else {
                return
            }

            await appState.itemManager.cacheItemsRegardless(
                skipRecentMoveCheck: true,
                resolveSourcePID: false,
                skipSavedLayoutApply: true
            )

            guard appState.menuBarManager.sectionController.revealedSection == revealedName else {
                return
            }
            await appState.imageCache.recaptureNow(sections: sections)
        }
    }

    func hide() {
        guard let menuBarManager else {
            return
        }

        if !isHidden {
            menuBarManager.sectionController.hideRevealedSections()
            menuBarManager.thawBarPanel.close()
        }
        resetClosedPresentationState(using: menuBarManager)
        stopRehideChecks()
    }

    private func resetClosedPresentationState(using menuBarManager: MenuBarManager) {
        menuBarManager.showOnHoverAllowed = true
        for section in menuBarManager.sections {
            section.desiredState = .hideSection
            section.updateControlItemState(for: nil)
        }
    }

    func toggle(triggeredByHotkey: Bool = false) {
        if isHidden {
            show(triggeredByHotkey: triggeredByHotkey)
        } else {
            hide()
        }
    }

    /// Pointer activity in either bar defers rehide.
    private func isMouseInsideActiveArea() -> Bool {
        guard let appState else { return false }
        if let screen = appState.hidEventManager.bestScreen(appState: appState),
           appState.hidEventManager.isMouseInsideMenuBarHoverBand(appState: appState, screen: screen)
        {
            return true
        }
        if appState.hidEventManager.isMouseInsideThawBar(appState: appState) {
            return true
        }
        return false
    }

    private func startRehideChecks() {
        rehideTask?.cancel()
        rehideMonitor?.stop()

        guard
            let appState,
            configuration.autoRehide
        else {
            return
        }

        switch configuration.rehideStrategy {
        case .smart:
            // The interval is a fallback for click-based smart rehide; task cancellation stops the wait.
            rehideTask = makeRehideTask(interval: configuration.rehideInterval) { [weak self] in
                self?.startRehideChecks()
            }
        case .timed:
            rehideMonitor = EventMonitor.universal(for: .mouseMoved) { [weak self, weak appState] event in
                // Throttle: process at most ~20fps regardless of mouse polling rate.
                enum Context {
                    static let lastTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
                }
                let now = CACurrentMediaTime()
                guard now - Context.lastTime.withLock({ $0 }) > 0.05 else { return event }
                Context.lastTime.withLock { $0 = now }

                guard
                    let self,
                    let appState,
                    let screen = NSScreen.main
                else {
                    return event
                }
                let mouseInActiveArea =
                    NSEvent.mouseLocation.y >= screen.visibleFrame.maxY ||
                    appState.hidEventManager.isMouseInsideThawBar(appState: appState)

                if !mouseInActiveArea {
                    if rehideTask == nil {
                        rehideTask = makeRehideTask(interval: configuration.rehideInterval) { [weak self] in
                            self?.diagLog.debug("Open menu detected - restarting timed rehide task")
                            await self?.restartTimedRehideTimer()
                        }
                    }
                } else {
                    rehideTask?.cancel()
                    rehideTask = nil
                }
                return event
            }

            rehideMonitor?.start()
        case .focusedApp:
            break
        }
    }

    /// Restarts the timed rehide task (used when a menu is detected).
    @MainActor
    private func restartTimedRehideTimer() async {
        guard
            appState != nil,
            configuration.autoRehide,
            case .timed = configuration.rehideStrategy
        else {
            return
        }

        rehideTask?.cancel()
        rehideTask = makeRehideTask(interval: configuration.rehideInterval) { [weak self] in
            self?.diagLog.debug("Open menu still detected - restarting timed rehide task again")
            await self?.restartTimedRehideTimer()
        }
    }

    /// Require a full eligible interval; active-area mouse movement restarts checks, open menus defer to onOpenMenu.
    private func makeRehideTask(
        interval: TimeInterval,
        onOpenMenu: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self, weak appState] in
            guard
                let self,
                let appState,
                await self.waitForContinuousRehideEligibility(
                    appState: appState,
                    interval: interval
                )
            else { return }
            if self.isMouseInsideActiveArea() {
                self.startRehideChecks()
                return
            }
            if await menuOpenMonitor?.isAnyMenuOpen() == true {
                await onOpenMenu()
                return
            }
            self.hide()
        }
    }

    /// Open-menu time does not count toward rehide, avoiding immediate collapse after a menu choice.
    private func waitForContinuousRehideEligibility(
        appState _: AppState,
        interval: TimeInterval
    ) async -> Bool {
        let pollInterval: TimeInterval = 0.25
        let clock = ContinuousClock()
        var eligibleSince = clock.now

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(pollInterval))
            guard !Task.isCancelled else { return false }

            if isMouseInsideActiveArea() {
                return false
            }

            if await menuOpenMonitor?.isAnyMenuOpen() == true {
                eligibleSince = clock.now
                continue
            }

            if eligibleSince.duration(to: clock.now) >= .seconds(interval) {
                return true
            }
        }

        return false
    }

    private func stopRehideChecks() {
        rehideTask?.cancel()
        rehideMonitor?.stop()
        rehideTask = nil
        rehideMonitor = nil
    }
}
