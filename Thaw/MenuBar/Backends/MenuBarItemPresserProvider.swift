//
//  MenuBarItemPresserProvider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// The press ladder that opens an item's menu without synthetic HID input.
nonisolated enum MenuBarItemPresserProvider {
    static let current: any MenuBarItemPressing = RuntimeItemPresserAdapter()
}

/// Process-addressed Command-drags for reorders; see MenuBarItemDragging.
nonisolated enum MenuBarItemDraggerProvider {
    static let current: any MenuBarItemDragging = RuntimeItemDraggerAdapter()
}
