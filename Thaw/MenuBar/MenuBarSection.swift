//
//  MenuBarSection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A representation of a section in a menu bar.
@MainActor
final class MenuBarSection {
    /// The name of the section.
    let name: Name

    /// The control item that manages the section.
    let controlItem: ControlItem

    /// The shared app state.
    private weak var appState: AppState?

    /// A task that manages rehiding the section.
    private var rehideTask: Task<Void, Never>?

    /// The section's diagnostic logger.
    private nonisolated let diagLog = DiagLog(category: "MenuBarSection")

    /// A Boolean value that indicates whether the Thaw Bar should be used
    /// on the current active display.
    private var useIceBar: Bool {
        guard let appState else { return false }
        let screen = screenForIceBar
        let displayID = screen?.displayID ?? CGMainDisplayID()
        let displaySettings = appState.settings.displaySettings
        if Self.usesThawBar(
            for: name,
            displayUsesThawBar: displaySettings.useIceBar(for: displayID),
            alwaysHiddenUsesThawBar: displaySettings.useThawBarForAlwaysHidden(for: displayID)
        ) {
            return true
        }
        return Self.forcesIceBarForNotchOverflow(
            settings: appState.settings.advanced,
            hasEjectedItems: appState.itemManager.hasNotchOverflowEjectedItems
        )
    }

    @MainActor
    private static func forcesIceBarForNotchOverflow(
        settings: AdvancedSettings,
        hasEjectedItems: Bool
    ) -> Bool {
        forcesIceBarForNotchOverflow(
            overflowEnabled: settings.enableMenuBarItemOverflow,
            useThawBarOnOverflow: settings.useThawBarOnNotchOverflow,
            hasEjectedItems: hasEjectedItems
        )
    }

    /// Calculates the total width of the items that must be shown when the
    /// section is expanded.
    private func totalItemsWidthToShow() -> CGFloat {
        guard let appState else { return 0 }

        let hiddenItems = appState.itemManager.itemCache[Name.hidden]
        let visibleItems = appState.itemManager.itemCache[Name.visible]
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

    /// Chooses how the section should be presented on the given screen.
    private func presentationMode(on screen: NSScreen) -> PresentationMode {
        guard let appState else { return .iceBar }
        let appMenuFrame = screen.getApplicationMenuFrame()

        return Self.presentationMode(
            totalItemsWidth: totalItemsWidthToShow(),
            appMenuRightEdge: appMenuFrame?.maxX,
            screenFrameMinX: screen.frame.minX,
            screenVisibleMaxX: screen.visibleFrame.maxX,
            notchFrame: screen.frameOfNotch,
            allowHidingApplicationMenus: appState.settings.advanced.hideApplicationMenus
        )
    }

    /// A weak reference to the menu bar manager.
    private weak var menuBarManager: MenuBarManager? {
        appState?.menuBarManager
    }

    /// The best screen to show the Thaw Bar on.
    ///
    /// Always returns the screen with the active menu bar so that
    /// clicking icons in the IceBar actually activates their popups.
    private weak var screenForIceBar: NSScreen? {
        NSScreen.screenWithActiveMenuBar ?? NSScreen.main
    }

    /// The hiding state the user desires for the section.
    @Published var desiredState: ControlItem.HidingState = .hideSection

    /// A Boolean value that indicates whether the section is hidden.
    var isHidden: Bool {
        if useIceBar {
            if controlItem.state == .showSection {
                return false
            }
            switch name {
            case .visible, .hidden:
                return menuBarManager?.iceBarPanel.currentSection != .hidden
            case .alwaysHidden:
                return menuBarManager?.iceBarPanel.currentSection != .alwaysHidden
            }
        }
        switch name {
        case .visible, .hidden:
            if menuBarManager?.iceBarPanel.currentSection == .hidden {
                return false
            }
            return desiredState == .hideSection
        case .alwaysHidden:
            if menuBarManager?.iceBarPanel.currentSection == .alwaysHidden {
                return false
            }
            return desiredState == .hideSection
        }
    }

    /// A Boolean value that indicates whether the section is enabled.
    var isEnabled: Bool {
        if case .visible = name {
            // The visible section should always be enabled.
            return true
        }
        return controlItem.isAddedToMenuBar
    }

    /// The hotkey to toggle the section.
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

    /// Creates a section with the given name and control item.
    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
    }

    /// Creates a section with the given name.
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

    /// Performs the initial setup of the section.
    func performSetup(with appState: AppState) {
        self.appState = appState
        controlItem.performSetup(with: appState)
        desiredState = controlItem.state
    }

    /// Updates the state of the control item based on the desired state
    /// and the current display configuration.
    ///
    /// - Parameter screen: The screen to use for the update. If `nil`, the
    ///   best screen is determined automatically.
    func updateControlItemState(for screen: NSScreen? = nil) {
        guard let appState else { return }

        // If the user wants to show, always show.
        if desiredState == .showSection {
            controlItem.state = .showSection
            return
        }

        // If the user wants to hide, check the current display config.
        // Use screenWithMouse for instant reactivity when switching displays.
        guard let activeScreen = screen ?? NSScreen.screenWithMouse ?? NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            controlItem.state = desiredState
            return
        }

        let displaySettings = appState.settings.displaySettings
        let useIceBar = Self.usesThawBar(
            for: name,
            displayUsesThawBar: displaySettings.useIceBar(for: activeScreen.displayID),
            alwaysHiddenUsesThawBar: displaySettings.useThawBarForAlwaysHidden(for: activeScreen.displayID)
        )
            || Self.forcesIceBarForNotchOverflow(
                settings: appState.settings.advanced,
                hasEjectedItems: appState.itemManager.hasNotchOverflowEjectedItems
            )

        // only apply alwaysShowHiddenItems when mouse + active menu bar on same screen
        let alwaysShow: Bool = if let menuBarScreen = NSScreen.screenWithActiveMenuBar,
                                  menuBarScreen.displayID == NSScreen.screenWithMouse?.displayID
        {
            displaySettings.alwaysShowHiddenItems(for: menuBarScreen.displayID)
        } else {
            false
        }

        if name == .hidden || name == .visible, alwaysShow, !useIceBar {
            controlItem.state = .showSection
        } else {
            controlItem.state = desiredState
        }
    }

    /// Shows the section.
    func show(triggeredByHotkey: Bool = false) {
        guard let menuBarManager, isHidden else {
            return
        }

        menuBarManager.updateLastShowTimestamp()

        guard controlItem.isAddedToMenuBar else {
            return
        }

        // Determine whether we should use the Thaw Bar based on settings.
        let shouldUseIceBarBasedOnSettings = useIceBar

        var preferredPresentationMode: PresentationMode
        if shouldUseIceBarBasedOnSettings {
            preferredPresentationMode = .iceBar
        } else if let screen = screenForIceBar {
            preferredPresentationMode = presentationMode(on: screen)
            // Avoid hiding application menus while a fullscreen space is
            // active. Hiding the application menus activates Thaw
            // (NSApp.activate), and activating inside a fullscreen space
            // makes macOS immediately hide the menu bar (FB13544993). Fall
            // back to the Thaw Bar instead: its panel is shown via
            // orderFrontRegardless() without activating. This mirrors the
            // fullscreen guard already present in the reactive sink in
            // MenuBarManager.
            if
                preferredPresentationMode == .inlineHidingApplicationMenus,
                appState?.activeSpace.isFullscreen == true
            {
                diagLog.info("Fullscreen space active; falling back to Thaw Bar instead of hiding application menus")
                preferredPresentationMode = .iceBar
            }
            switch preferredPresentationMode {
            case .inline:
                break
            case .inlineHidingApplicationMenus:
                diagLog.info("Showing items inline by hiding the application menus")
            case .iceBar:
                diagLog.info("Not enough space to show items inline, falling back to Thaw Bar")
            }
        } else {
            preferredPresentationMode = .inline
        }

        // Use Ice Thaw if settings say so OR if items still won't fit inline.
        if preferredPresentationMode == .iceBar {
            // Make sure hidden and always-hidden control items are collapsed.
            // Still update the visible control item (Ice icon) state to show
            // its alternate icon.
            for section in menuBarManager.sections {
                switch section.name {
                case .visible:
                    section.desiredState = .showSection
                case .hidden, .alwaysHidden:
                    section.desiredState = .hideSection
                }
                section.updateControlItemState(for: nil)
            }

            if let screen = screenForIceBar {
                switch name {
                case .visible, .hidden:
                    menuBarManager.iceBarPanel.show(
                        section: .hidden,
                        on: screen,
                        triggeredByHotkey: triggeredByHotkey
                    )
                case .alwaysHidden:
                    menuBarManager.iceBarPanel.show(
                        section: .alwaysHidden,
                        on: screen,
                        triggeredByHotkey: triggeredByHotkey
                    )
                }
                startRehideChecks()
            }

            return // We're done.
        }

        // If we made it here, we're not using the Thaw Bar.
        // Make sure it's closed.
        menuBarManager.iceBarPanel.close()

        if preferredPresentationMode == .inlineHidingApplicationMenus {
            menuBarManager.hideApplicationMenus()
        }

        switch name {
        case .visible, .hidden:
            for section in menuBarManager.sections where section.name != .alwaysHidden {
                section.desiredState = .showSection
                section.updateControlItemState(for: nil)
            }
        case .alwaysHidden:
            for section in menuBarManager.sections {
                section.desiredState = .showSection
                section.updateControlItemState(for: nil)
            }
        }

        startRehideChecks()
    }

    /// Hides the section.
    func hide() {
        guard let menuBarManager, !isHidden else {
            return
        }

        menuBarManager.iceBarPanel.close() // Make sure Thaw Bar is always closed.
        menuBarManager.showOnHoverAllowed = true

        for section in menuBarManager.sections {
            section.desiredState = .hideSection
            section.updateControlItemState(for: nil)
        }

        stopRehideChecks()
    }

    /// Toggles the visibility of the section.
    func toggle(triggeredByHotkey: Bool = false) {
        if isHidden {
            show(triggeredByHotkey: triggeredByHotkey)
        } else {
            hide()
        }
    }

    /// Returns `true` when the mouse cursor is inside the menu bar or the
    /// IceBar panel, meaning the section should not be rehidden yet.
    private func isMouseInsideActiveArea() -> Bool {
        guard let appState else { return false }
        if let screen = appState.hidEventManager.bestScreen(appState: appState),
           appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen)
        {
            return true
        }
        if appState.hidEventManager.isMouseInsideIceBar(appState: appState) {
            return true
        }
        return false
    }

    /// Starts running checks to determine when to rehide the section.
    private func startRehideChecks() {
        rehideTask?.cancel()
        rehideTask = nil

        guard
            let appState,
            appState.settings.general.autoRehide
        else {
            return
        }

        switch appState.settings.general.rehideStrategy {
        case .smart, .timed:
            // Smart uses the rehide interval as a fallback to the click-based
            // rehide checks; timed uses it as the rule. The interval itself is
            // never gated, but the hide at its end is: hiding under a cursor
            // that is still over the bar or the Thaw Bar is the #924 bug, and
            // hiding while a menu bar item's menu is open would yank the menu
            // out from under the user. Both defer by restarting the checks.
            // Task.sleep replaces Timer so cancellation is automatic when the
            // task is reassigned or cancelled.
            let interval = appState.settings.general.rehideInterval
            rehideTask = Task { [weak self, weak appState] in
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, let appState else { return }
                if self.isMouseInsideActiveArea() {
                    self.startRehideChecks()
                    return
                }
                if await appState.itemManager.isAnyMenuBarItemMenuOpen() {
                    self.startRehideChecks()
                    return
                }
                self.hide()
            }
        case .focusedApp:
            break
        }
    }

    /// Stops running checks to determine when to rehide the section.
    private func stopRehideChecks() {
        rehideTask?.cancel()
        rehideTask = nil
    }
}
