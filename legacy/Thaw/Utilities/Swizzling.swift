//
//  Swizzling.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

extension NSSplitViewItem {
    @MainActor
    @nonobjc private static let swizzler: () = {
        let originalCanCollapseSel = #selector(getter: canCollapse)
        let swizzledCanCollapseSel = #selector(getter: swizzledCanCollapse)

        guard
            let originalCanCollapseMethod = class_getInstanceMethod(NSSplitViewItem.self, originalCanCollapseSel),
            let swizzledCanCollapseMethod = class_getInstanceMethod(NSSplitViewItem.self, swizzledCanCollapseSel)
        else {
            return
        }

        method_exchangeImplementations(originalCanCollapseMethod, swizzledCanCollapseMethod)
    }()

    @MainActor
    @objc private var swizzledCanCollapse: Bool {
        if
            let window = viewController.view.window,
            window.identifier?.rawValue == IceWindowIdentifier.settings.rawValue
        {
            return false
        }
        return self.swizzledCanCollapse
    }

    @MainActor
    static func swizzle() {
        _ = swizzler
    }
}
