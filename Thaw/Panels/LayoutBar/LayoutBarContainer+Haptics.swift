//
//  LayoutBarContainer+Haptics.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit

extension LayoutBarContainer {
    /// A drag reaching this bar, with a tap when it came from another section.
    func handleDragEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        LayoutDragHaptics.enter(section)
        return handleDrag(draggingInfo, phase: .entered)
    }
}
