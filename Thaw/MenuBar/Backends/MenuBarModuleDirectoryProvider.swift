//
//  MenuBarModuleDirectoryProvider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// The lookup the layout editor uses to name a governable extra it cannot see.
nonisolated enum MenuBarModuleDirectoryProvider {
    static let current: any MenuBarModuleDirectory = RuntimeModuleDirectoryAdapter()
}
