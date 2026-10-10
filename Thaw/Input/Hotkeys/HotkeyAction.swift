//
//  HotkeyAction.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

nonisolated enum HotkeyAction: String, Codable, CaseIterable {
    // MARK: Menu Bar Sections

    case toggleHiddenSection = "ToggleHiddenSection"
    case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"

    /// Trades the shown and hidden groups: Visible items move to Hidden,
    /// Hidden items move to Visible, and a second press trades them back.
    /// See MenuBarManager.toggleSwap().
    case toggleSwap = "ToggleSwap"

    // MARK: Menu Bar Items

    /// Summons the search panel, in whichever face
    /// AdvancedSettings.menuBarSearchPresentation asks for. The Lab palettes
    /// are modes of this panel, so this is the only way in.
    case searchMenuBarItems = "SearchMenuBarItems"

    /// Opens the small Thaw Bar with every Thaw Bar Only item.
    case showThawBarOnlyItems = "ShowThawBarOnlyItems"

    /// Puts a letter under every item on the menu bar; typing one opens that
    /// item. See ItemHints.
    case showItemHints = "ShowItemHints"

    // MARK: Other

    case revealSystemMenuBar = "RevealSystemMenuBar"
    case enableThawBar = "EnableIceBar"
    case toggleApplicationMenus = "ToggleApplicationMenus"
    case toggleAutoRehide = "ToggleAutoRehide"
    case toggleZenMode = "ToggleZenMode"
    case toggleLayoutEditor = "ToggleLayoutEditor"

    /// Used by profile hotkeys, action is handled externally.
    case profileApply = "ProfileApply"

    /// Used by per-item hotkeys, action is handled externally.
    case openMenuBarItem = "OpenMenuBarItem"

    /// Actions that should appear in the Hotkeys settings pane as fixed,
    /// singleton recorders. Dynamic per-profile and per-item hotkeys are
    /// created separately and are excluded here.
    static var settingsActions: [HotkeyAction] {
        allCases.filter { $0 != .profileApply && $0 != .openMenuBarItem }
    }

    @MainActor
    func perform(appState: AppState) {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            section.toggle(triggeredByHotkey: true)
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .toggleAlwaysHiddenSection:
            guard
                let section = appState.menuBarManager.section(withName: .alwaysHidden),
                section.isEnabled
            else {
                return
            }
            section.toggle(triggeredByHotkey: true)
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .toggleSwap:
            // The swap is a reflow that lands later, so the manager owns the
            // feedback: a refusal answers at once, an accepted swap answers
            // when the bar has actually changed.
            appState.menuBarManager.toggleSwap()
        case .searchMenuBarItems:
            appState.menuBarManager.searchPanel.toggle()
        case .revealSystemMenuBar:
            let provider = MenuBarPresentationProvider.current
            guard provider.isSupported else {
                appState.userNotificationManager.requestAuthorization()
                appState.userNotificationManager.addRequest(
                    with: .hotkeyToggleFeedback,
                    title: String(localized: "Not available on this version of macOS"),
                    body: ""
                )
                return
            }
            Task { [provider] in
                _ = await provider.revealSystemMenuBar()
            }
        case .showThawBarOnlyItems:
            appState.thawBarOnlyProxies.toggleThawBarOnlyBar()
        case .showItemHints:
            appState.itemHints.toggle()
        case .enableThawBar:
            appState.settings.displaySettings.toggleThawBarForActiveDisplay()
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        case .toggleAutoRehide:
            let general = appState.settings.general
            general.autoRehide.toggle()
            // The toggle has no visible effect until the next reveal, so
            // confirm the new state with a notification.
            appState.userNotificationManager.requestAuthorization()
            appState.userNotificationManager.addRequest(
                with: .hotkeyToggleFeedback,
                title: general.autoRehide
                    ? String(localized: "Automatic rehiding is on")
                    : String(localized: "Automatic rehiding is off"),
                body: ""
            )
        case .toggleZenMode:
            guard appState.menuBarManager.toggleZenMode() else {
                return
            }
            let isActive = appState.menuBarManager.isZenModeActive
            appState.userNotificationManager.requestAuthorization()
            appState.userNotificationManager.addRequest(
                with: .hotkeyToggleFeedback,
                title: isActive
                    ? String(localized: "Zen Mode is on")
                    : String(localized: "Zen Mode is off"),
                body: ""
            )
            // Zen mode dims the bar the user may not be looking at, and a
            // notification can be muted, deferred to a Focus summary, or land
            // seconds late. The HUD answers the keystroke immediately, on the
            // screen the pointer is on.
            ThawHUD.show(
                symbol: isActive ? "moon.zzz.fill" : "moon.zzz",
                text: isActive ? "Zen Mode on" : "Zen Mode off"
            )
        case .toggleLayoutEditor:
            // Deliberately a toggle: the same keystroke that summons the layout
            // editor puts it away, so rearranging the bar never requires reaching
            // for the pointer. The panel picks the pointer's screen itself; a
            // hotkey carries no display of its own.
            appState.menuBarManager.layoutEditorPanel.toggle()
        case .profileApply:
            // Handled externally by ProfileManager's custom registration.
            break
        case .openMenuBarItem:
            // Handled externally by MenuBarManager's per-item registration.
            break
        }
    }
}
