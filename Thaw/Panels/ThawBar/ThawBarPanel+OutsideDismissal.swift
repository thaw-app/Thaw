//
//  ThawBarPanel+OutsideDismissal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension ThawBarPanel {
    /// Closes the bar for a press outside it, and notes the press so show-on-click,
    /// which sees it next, does not reopen the bar. A folder presentation owns no
    /// section, so a press that closes one is free to reveal the hidden section.
    func hide(dismissedBy press: MousePress) {
        if presentation == .section {
            MousePressLedger.shared.noteDismissal(by: press)
        }
        hide()
    }
}
