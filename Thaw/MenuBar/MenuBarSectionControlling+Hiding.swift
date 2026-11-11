//
//  MenuBarSectionControlling+Hiding.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import MenuBarModel

extension MenuBarSectionControlling {
    /// Whether to warn that hiding isn't supported. Only a running backend can say so:
    /// an absent one doesn't prove it.
    var isHidingUnavailable: Bool {
        isOperational && !isHidingAvailable
    }
}
