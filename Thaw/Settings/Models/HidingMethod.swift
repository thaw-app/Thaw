//
//  HidingMethod.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// How Thaw takes items off the menu bar on macOS 27. One method runs at a time.
nonisolated enum HidingMethod: Int, CaseIterable, Identifiable {
    /// macOS's own per-app switch, the one in System Settings > Menu Bar. Nothing else leaves the bar.
    case native = 0
    /// The restriction macOS applies to the whole bar, for apps' items.
    case standard = 1
    /// The same restriction, extended to the items macOS pins to the right: Clock, Control Center and Siri.
    case everything = 2

    /// The method the two stored switches stand for. Native wins: it releases the restriction the
    /// other two need, so the Apple-items switch cannot be on beside it.
    init(nativeAppHidingEnabled: Bool, hidesAppleItems: Bool) {
        self = nativeAppHidingEnabled ? .native : (hidesAppleItems ? .everything : .standard)
    }

    var id: Int {
        rawValue
    }

    /// What the native-hiding switch should read for this method.
    var usesNativeAppHiding: Bool {
        self == .native
    }

    /// What the Apple-items switch should read for this method.
    var hidesAppleItems: Bool {
        self == .everything
    }

    var localized: LocalizedStringKey {
        switch self {
        case .native: "Native"
        case .standard: "Standard"
        case .everything: "Everything"
        }
    }

    /// What the method keeps or hides, then what it costs. One short line each.
    var explanation: LocalizedStringKey {
        switch self {
        case .native:
            "Keeps Live Activities, the camera indicator and Apple’s own items on the menu bar.\nCan’t hide Clock, Control Center or Siri. macOS may show the screen recording indicator."
        case .standard:
            "Hides any app’s items.\nWhile they’re hidden, macOS also removes Live Activities and the camera indicator."
        case .everything:
            "Hides any app’s items, and Clock, Control Center and Siri too.\nWhile they’re hidden, macOS also removes Live Activities and the camera indicator."
        }
    }
}
