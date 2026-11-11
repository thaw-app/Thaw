//
//  ApplicationMenuHider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Observation

/// Hides the front app's menus by activating Thaw, when a revealed section needs their room or the user asks.
@MainActor
@Observable
final class ApplicationMenuHider {
    /// The live calls the hider makes, replaceable in tests.
    struct Environment {
        var activateAsRegular: @MainActor () -> Void
        var activate: @MainActor () -> Void
        var deactivateToAccessory: @MainActor () -> Void
        /// The screen with the active menu bar, without falling back to the main screen.
        var activeMenuBarScreen: @MainActor () -> NSScreen? = { NSScreen.screenWithActiveMenuBar }
        var mainScreen: @MainActor () -> NSScreen? = { NSScreen.main }
        var presentationMode: @MainActor (MenuBarSection, NSScreen) -> MenuBarSection.PresentationMode = {
            $0.presentationMode(on: $1)
        }
        var sleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

        /// Activates and deactivates the app through its app state.
        static func live(appState: AppState) -> Self {
            Self(
                activateAsRegular: { [weak appState] in appState?.activate(withPolicy: .regular) },
                activate: { [weak appState] in appState?.activate() },
                deactivateToAccessory: { [weak appState] in appState?.deactivate(withPolicy: .accessory) }
            )
        }
    }

    /// Thaw has replaced the front app's menus with its own empty menus.
    private(set) var isHidingApplicationMenus = false

    /// Manual URL/hotkey hiding must not be undone by automatic section state.
    private var isManuallyHidingApplicationMenus = false

    @ObservationIgnored
    private let diagLog = DiagLog(category: "MenuBarManager")

    /// Weak because AppState owns the menu bar manager that holds this hider.
    @ObservationIgnored
    private weak var appState: AppState?

    @ObservationIgnored
    private var environment: Environment?

    /// - Parameter environment: The live calls; nil wires them to appState.
    func performSetup(with appState: AppState, environment: Environment? = nil) {
        self.appState = appState
        self.environment = environment ?? .live(appState: appState)
    }

    /// What a section state change does to the menus.
    nonisolated enum Reconciliation: Equatable {
        case leaveMenus
        case showMenus
        /// Hide the menus if this shown section needs their room.
        case hideIfSectionNeedsRoom(MenuBarSectionName)
    }

    /// Restore only automatic hiding once both sections close; a shown always-hidden section wins over hidden.
    static nonisolated func reconciliation(
        isShowingHidden: Bool,
        isShowingAlwaysHidden: Bool,
        isHiding: Bool,
        isManual: Bool
    ) -> Reconciliation {
        guard isShowingHidden || isShowingAlwaysHidden else {
            return isHiding && !isManual ? .showMenus : .leaveMenus
        }
        return .hideIfSectionNeedsRoom(isShowingAlwaysHidden ? .alwaysHidden : .hidden)
    }

    /// Control state changes signal section reveals and concealment, requiring menu visibility reconciliation.
    func observeSectionStates(of sections: [MenuBarSection], into bag: inout Set<AnyCancellable>) {
        Publishers.MergeMany(sections.map(\.controlItem.$state))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconcileApplicationMenuVisibility()
            }
            .store(in: &bag)
    }

    /// Do not take app menus when Thaw Bar presents elsewhere, the system hides the bar, or fullscreen/settings needs them.
    func reconcileApplicationMenuVisibility() {
        guard let appState, let environment else {
            return
        }
        let menuBarManager = appState.menuBarManager

        let activeDisplayID = (environment.activeMenuBarScreen() ?? environment.mainScreen())?.displayID ?? CGMainDisplayID()
        guard
            appState.settings.hideApplicationMenus,
            !menuBarManager.shouldUseThawBar(for: activeDisplayID),
            !menuBarManager.isMenuBarHiddenBySystem,
            !appState.activeSpace.isFullscreen,
            !appState.navigationState.isSettingsPresented
        else {
            return
        }

        let reconciliation = Self.reconciliation(
            isShowingHidden: menuBarManager.section(withName: .hidden).map { !$0.isHidden } ?? false,
            isShowingAlwaysHidden: menuBarManager.section(withName: .alwaysHidden).map { !$0.isHidden } ?? false,
            isHiding: isHidingApplicationMenus,
            isManual: isManuallyHidingApplicationMenus
        )
        let shownName: MenuBarSectionName
        switch reconciliation {
        case .leaveMenus:
            return
        case .showMenus:
            showApplicationMenus()
            return
        case let .hideIfSectionNeedsRoom(name):
            shownName = name
        }

        guard let screen = environment.activeMenuBarScreen() ?? environment.mainScreen() else {
            return
        }
        hideIfNeedingRoom(menuBarManager.section(withName: shownName), on: screen)
    }

    /// Hides the menus once the shown section settles, if it cannot fit inline beside them.
    @discardableResult
    func hideIfNeedingRoom(_ shownSection: MenuBarSection?, on screen: NSScreen) -> Task<Void, Never>? {
        guard let environment else {
            return nil
        }
        let displayID = screen.displayID
        return Task {
            // Let WindowServer settle the expanded section before checking its presentation mode.
            try? await environment.sleep(.milliseconds(50))
            guard
                !Task.isCancelled,
                environment.activeMenuBarScreen()?.displayID == displayID,
                let shownSection
            else {
                return
            }

            switch environment.presentationMode(shownSection, screen) {
            case .inline:
                break
            case .inlineHidingApplicationMenus, .thawBar:
                self.hideApplicationMenus()
            }
        }
    }

    /// AppKit cannot hide another app's menus; activating Thaw as regular replaces them with empty menus and briefly shows it in the Dock.
    /// - Parameter manual: true for URL/hotkey requests, preventing section state from restoring the menus.
    /// - Returns: The activation task, or nil when nothing started.
    @discardableResult
    func hideApplicationMenus(manual: Bool = false) -> Task<Void, Never>? {
        guard appState != nil, let environment else {
            diagLog.error("Error hiding application menus: Missing app state")
            return nil
        }

        if isHidingApplicationMenus {
            return nil
        }

        diagLog.info("Hiding application menus")
        isHidingApplicationMenus = true
        if manual {
            isManuallyHidingApplicationMenus = true
        }

        return Task { @MainActor in
            guard isHidingApplicationMenus else { return }

            environment.activateAsRegular()

            // Retry activation after a short delay because the system can ignore the first after a policy change.
            try? await environment.sleep(.milliseconds(25))
            guard isHidingApplicationMenus else { return }
            environment.activate()
        }
    }

    /// Return to accessory policy and clear manual ownership of menu hiding.
    func showApplicationMenus() {
        guard appState != nil, let environment else {
            diagLog.error("Error showing application menus: Missing app state")
            return
        }
        diagLog.info("Showing application menus")
        environment.deactivateToAccessory()
        isHidingApplicationMenus = false
        isManuallyHidingApplicationMenus = false
    }

    /// Only users reach this toggle, so hiding here takes manual ownership.
    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus(manual: true)
        }
    }
}
