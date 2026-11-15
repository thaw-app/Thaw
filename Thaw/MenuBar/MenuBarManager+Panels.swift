//
//  MenuBarManager+Panels.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation

extension MenuBarManager {
    var thawBarPanel: ThawBarPanel {
        if let thawBarPanelIfCreated {
            return thawBarPanelIfCreated
        }
        let panel = ThawBarPanel()
        thawBarPanelIfCreated = panel
        if let appState {
            panel.performSetup(
                with: appState,
                displayInvalidations: appState.displayEnvironment.invalidations,
                displaySettlements: appState.displayEnvironment.settlements
            )
        }
        return panel
    }

    var searchPanel: MenuBarSearchPanel {
        if let searchPanelIfCreated {
            return searchPanelIfCreated
        }
        let panel = MenuBarSearchPanel()
        searchPanelIfCreated = panel
        if let appState {
            panel.performSetup(with: appState, displayInvalidations: appState.displayEnvironment.invalidations)
        }
        return panel
    }

    var appearanceEditorPanel: MenuBarAppearanceEditorPanel {
        if let appearanceEditorPanelIfCreated {
            return appearanceEditorPanelIfCreated
        }
        let panel = MenuBarAppearanceEditorPanel()
        appearanceEditorPanelIfCreated = panel
        if let appState {
            panel.performSetup(with: appState)
        }
        return panel
    }

    var layoutEditorPanel: MenuBarLayoutEditorPanel {
        if let layoutEditorPanelIfCreated {
            return layoutEditorPanelIfCreated
        }
        let panel = MenuBarLayoutEditorPanel()
        layoutEditorPanelIfCreated = panel
        if let appState {
            panel.performSetup(with: appState, displayInvalidations: appState.displayEnvironment.invalidations)
        }
        return panel
    }
}
