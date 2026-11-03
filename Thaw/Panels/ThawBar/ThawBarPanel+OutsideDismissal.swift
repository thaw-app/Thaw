//
//  ThawBarPanel+OutsideDismissal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension ThawBarPanel {
    /// Closes the bar and notes the press so show-on-click doesn't reopen it. A
    /// folder owns no section, so its closing press may still reveal one.
    func hide(dismissedBy press: MousePress) {
        if presentation == .section {
            MousePressLedger.shared.noteDismissal(by: press)
        }
        hide()
    }
}
