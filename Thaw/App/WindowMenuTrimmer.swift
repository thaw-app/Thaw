//
//  WindowMenuTrimmer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Takes the Window menu off the main menu while no Thaw window is open.
/// When another app reads Thaw's menus through Accessibility, an attached Window
/// menu makes AppKit build and keep its window commands, several MiB.
@MainActor
final class WindowMenuTrimmer {
    static let shared = WindowMenuTrimmer()

    private let diagLog = DiagLog(category: "WindowMenuTrimmer")
    private var detached: (item: NSMenuItem, index: Int, menu: NSMenu)?
    private var anyWindowOpen: () -> Bool = { false }
    private var mainMenuObservation: NSKeyValueObservation?
    private var activationTask: Task<Void, Never>?

    /// Starts trimming. The main menu can appear after launch, and SwiftUI can
    /// replace it, so the trimmer acts whenever it changes and when Thaw becomes active.
    func watch(anyWindowOpen: @escaping () -> Bool) {
        self.anyWindowOpen = anyWindowOpen
        mainMenuObservation = NSApp.observe(\.mainMenu, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        activationTask?.cancel()
        activationTask = NotificationCenter.default.eventsTask(named: NSApplication.didBecomeActiveNotification) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        update(anyWindowOpen: anyWindowOpen())
    }

    /// Detaches the Window menu while nothing is open and puts it back for a window,
    /// so Minimize and the window list work whenever there is a window to act on.
    func update(anyWindowOpen: Bool, mainMenu: NSMenu? = NSApp.mainMenu, windowsMenu: NSMenu? = NSApp.windowsMenu) {
        guard let mainMenu else {
            diagLog.debug("no main menu yet")
            return
        }
        // A rebuilt main menu brings its own Window menu; the one taken from the old menu is gone.
        if let detached, detached.menu !== mainMenu {
            self.detached = nil
        }
        if anyWindowOpen {
            reattach(to: mainMenu) { NSApp.windowsMenu = $0 }
        } else {
            detach(from: mainMenu, windowsMenu: windowsMenu ?? Self.windowsMenu(in: mainMenu))
        }
    }

    /// The submenu holding Minimize, which is the Window menu in any language.
    static func windowsMenu(in mainMenu: NSMenu) -> NSMenu? {
        mainMenu.items.first { item in
            item.submenu?.items.contains { $0.action == #selector(NSWindow.performMiniaturize(_:)) } == true
        }?.submenu
    }

    private func detach(from mainMenu: NSMenu, windowsMenu: NSMenu?) {
        guard detached == nil else { return }
        guard let windowsMenu, let index = mainMenu.items.firstIndex(where: { $0.submenu === windowsMenu }) else {
            diagLog.info("no Window menu on the main menu to detach")
            return
        }
        let item = mainMenu.items[index]
        mainMenu.removeItem(at: index)
        detached = (item, index, mainMenu)
        diagLog.info("detached the Window menu while no window is open")
    }

    private func reattach(to mainMenu: NSMenu, setWindowsMenu: (NSMenu?) -> Void) {
        guard let detached else { return }
        self.detached = nil
        // SwiftUI may have rebuilt the menu with its own Window menu meanwhile.
        guard !mainMenu.items.contains(where: { $0.submenu?.title == detached.item.submenu?.title }) else { return }
        mainMenu.insertItem(detached.item, at: min(detached.index, mainMenu.items.count))
        setWindowsMenu(detached.item.submenu)
    }

    /// Whether the Window menu is off the main menu right now.
    var isDetached: Bool {
        detached != nil
    }
}
