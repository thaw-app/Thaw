//
//  HIDEventManager+ClickPairing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension HIDEventManager {
    /// How long a first click in empty menu bar space waits for the second that asks for always-hidden.
    /// Capped like clicks on Thaw's icon, so a slow double-click speed in macOS does not pair ordinary clicks.
    static func menuBarClickPairingWindow(systemInterval: TimeInterval = NSEvent.doubleClickInterval) -> Duration {
        .seconds(ControlItem.PrimaryActivationSequence.pairingInterval(systemInterval: systemInterval))
    }
}
