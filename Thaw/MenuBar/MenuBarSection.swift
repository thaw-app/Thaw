//
//  MenuBarSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

@MainActor
final class MenuBarSection {
    typealias Name = MenuBarSectionName

    let name: Name

    let controlItem: ControlItem

    private weak var appState: AppState?

    /// Engine-facing settings; see MenuBarEngineConfiguration for the dependency boundary.
    private var configuration: any MenuBarEngineConfiguration = AppSettings.engineDefaults

    private nonisolated let diagLog = DiagLog(category: "MenuBarSection")

    /// Whether a reveal on screen uses the Thaw Bar, by that display's own setting.
    private func usesThawBar(on screen: NSScreen?) -> Bool {
        guard let appState else { return false }
        return appState.menuBarManager.shouldUseThawBar(for: screen?.displayID ?? CGMainDisplayID(), section: name)
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
        if let inlineWidth = capacity.availableWidth(applicationMenus: .visible), totalItemsWidth <= inlineWidth {
            return .inline
        }

        guard allowHidingApplicationMenus else {
            return .thawBar
        }

        if let inlineWidthWithoutAppMenus = capacity.availableWidth(applicationMenus: .hidden), totalItemsWidth <= inlineWidthWithoutAppMenus {
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
        guard let width = capacity.availableWidth(applicationMenus: menus) else {
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

    /// The display setting owns Hidden's visibility while Always Hidden stays toggleable.
    var isToggleEnabled: Bool {
        isEnabled && (name != .hidden || menuBarManager?.shouldAlwaysShowHiddenItems != true)
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

    func performSetup(with appState: AppState, displays: DisplayEnvironment) {
        self.appState = appState
        configuration = appState.settings
        controlItem.performSetup(with: appState, displayInvalidations: displays.invalidations)
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

        // Prefer the active menu bar so pointer movement does not change visibility.
        guard let activeScreen = NSScreen.screenWithActiveMenuBar ?? screen ?? NSScreen.main else {
            controlItem.state = desiredState
            controlItem.applyAppearanceNow()
            return
        }

        let displaySettings = appState.settings.displaySettings
        let useThawBar = appState.menuBarManager.shouldUseThawBar(for: activeScreen.displayID, section: name)
        let alwaysShow = !appState.menuBarManager.isZenModeActive
            && displaySettings.alwaysShowHiddenItems(for: activeScreen.displayID)

        if name != .alwaysHidden, alwaysShow, !useThawBar {
            controlItem.state = .showSection
        } else {
            controlItem.state = desiredState
        }
        controlItem.applyAppearanceNow()
    }

    /// eventScreen is the display a pointer reveal happened on; without one, the active menu bar's.
    func show(triggeredByHotkey: Bool = false, forcingInline: Bool = false, on eventScreen: NSScreen? = nil) {
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

        menuBarManager.rehideController?.revealed()

        // ThawBarPanel captures glyphs during a brief reveal and forwards clicks through revealClickAndConceal.
        // Use it when requested or when inline items would be unreachable behind native overflow.
        let revealScreen = eventScreen ?? screenForThawBar
        let useThawBar = usesThawBar(on: revealScreen)
        let overflowsInline = !useThawBar && (revealScreen.map { overflowsInline(on: $0) } ?? false)
        if overflowsInline {
            diagLog.info("show(\(name.logString)): the items do not fit inline; using the Thaw Bar")
        }
        if !forcingInline, useThawBar || overflowsInline, let screen = revealScreen {
            // A section left revealed inline would stay expanded behind the panel.
            let revealedInline = menuBarManager.sectionController.revealedSection
            if revealedInline != nil {
                menuBarManager.sectionController.hideRevealedSections()
            }
            for section in menuBarManager.sections {
                section.desiredState = section.name == .visible ? .showSection : .hideSection
                section.updateControlItemState(for: nil)
            }
            menuBarManager.thawBarPanel.show(
                section: name == .alwaysHidden ? .alwaysHidden : .hidden,
                on: screen,
                triggeredByHotkey: triggeredByHotkey
            )
            menuBarManager.rehideController?.revealed(name)
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
        refreshRevealedItemImages()
        menuBarManager.rehideController?.revealed(name)
    }

    /// Capture glyphs while the section is revealed to replace app-icon fallbacks in layout and search.
    private func refreshRevealedItemImages() {
        guard let appState else { return }
        let revealedName = name == .alwaysHidden ? Name.alwaysHidden : Name.hidden
        let sections: [Name] = revealedName == .alwaysHidden ? Name.allCases : [.visible, .hidden]

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

            guard appState.menuBarManager.sectionController.revealedSection == revealedName else { return }
            await appState.imageCache.recaptureNow(sections: sections)
        }
    }

    func hide(using manager: MenuBarManager? = nil) {
        guard let menuBarManager = manager ?? menuBarManager else {
            return
        }

        if !isHidden {
            if menuBarManager.shouldAlwaysShowHiddenItems {
                menuBarManager.synchronizeAlwaysShowHiddenItems(closingSections: true)
            } else {
                menuBarManager.sectionController.hideRevealedSections()
            }
            menuBarManager.thawBarPanel.close()
        }
        resetClosedPresentationState(using: menuBarManager)
        menuBarManager.rehideController?.hidden(name)
    }

    private func resetClosedPresentationState(using menuBarManager: MenuBarManager) {
        menuBarManager.showOnHoverAllowed = !menuBarManager.isZenModeActive
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
}
