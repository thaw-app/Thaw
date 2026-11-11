//
//  LayoutEditorWorld.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// An app state whose item cache holds items owned by the test process, so they count as running.
@MainActor
struct LayoutEditorWorld {
    let appState = AppState()
    private static var nextWindowID: CGWindowID = 9000

    static func item(_ tag: MenuBarItemTag, ownerPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> MenuBarItem {
        nextWindowID += 1
        return MenuBarItem(
            tag: tag,
            windowID: nextWindowID,
            ownerPID: ownerPID,
            sourcePID: ownerPID,
            bounds: CGRect(x: CGFloat(nextWindowID), y: 0, width: 24, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }

    static func item(_ title: String) -> MenuBarItem {
        item(MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0))
    }

    func seat(_ items: [MenuBarItem], in section: MenuBarSection.Name = .visible) {
        appState.itemManager.itemCache[section] = items
    }
}
