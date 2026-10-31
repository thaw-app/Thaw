//
//  ClosureMenuItem.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import AppKit

/// A menu item that runs a closure, so a menu's construction stays in one place.
@MainActor
public final class ClosureMenuItem: NSMenuItem, NSMenuItemValidation {
    private let handler: @MainActor () -> Void
    /// A menu enables an item whose target answers its action unless the target says otherwise.
    private let isAvailable: Bool

    public init(title: String, isEnabled: Bool = true, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        isAvailable = isEnabled
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
    }

    /// AppKit's initializers are nonisolated, so this stand-in has to be too.
    @available(*, unavailable)
    override nonisolated init(title _: String, action _: Selector?, keyEquivalent _: String) {
        fatalError("init(title:action:keyEquivalent:) has not been implemented")
    }

    @available(*, unavailable)
    public required nonisolated init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item !== self || isAvailable
    }
}
