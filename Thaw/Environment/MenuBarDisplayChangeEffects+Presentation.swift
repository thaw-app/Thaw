//
//  MenuBarDisplayChangeEffects+Presentation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension MenuBarDisplayChangeEffects {
    /// Checks mirroring for automatic zen, then lets always-show, which held back since the first posting, reveal on the
    /// settled bar. The control items follow, since the active display or its width may have changed.
    func applyPresentationPolicy() {
        presentationMonitor.evaluateAfterDisplayChange()
        menuBarManager.alwaysShowHiddenItemsController?.finishDisplayChange()
        menuBarManager.updateControlItemStates()
    }
}
