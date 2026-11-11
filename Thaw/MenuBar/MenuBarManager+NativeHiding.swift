//
//  MenuBarManager+NativeHiding.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

extension MenuBarManager {
    /// Apps native hiding leaves alone because their switch changed in System Settings after it hid them.
    var nativeLeftAloneBundleIDs: Set<String> {
        runtimeSectionController?.nativeLeftAloneBundleIDs ?? []
    }
}
