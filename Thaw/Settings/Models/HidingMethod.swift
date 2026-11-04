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
    /// The restriction macOS applies to the whole bar, for apps' items and for the items macOS pins
    /// to the right: Clock, Control Center and Siri.
    case standard = 1

    /// Standard needs the restriction Native releases.
    init(nativeAppHidingEnabled: Bool) {
        self = nativeAppHidingEnabled ? .native : .standard
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
        self == .standard
    }

    var localized: LocalizedStringResource {
        switch self {
        case .native: "Native"
        case .standard: "Standard"
        }
    }

    /// One short sentence on what the method hides and keeps. The costs are spelled out
    /// once, in the Known macOS 27 limitations popover beside the picker.
    var explanation: LocalizedStringResource {
        switch self {
        case .native:
            "Hides apps’ items and leaves Apple’s items, Live Activities and the camera indicator on the menu bar."
        case .standard:
            "Hides any item, including Clock, Control Center and Siri, and macOS removes Live Activities and the camera indicator while it does."
        }
    }
}
