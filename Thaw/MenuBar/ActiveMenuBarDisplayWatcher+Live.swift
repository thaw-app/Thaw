//
//  ActiveMenuBarDisplayWatcher+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension ActiveMenuBarDisplayWatcher {
    /// Checks on app activation, a Space change and once a second.
    func start() {
        guard observationTasks.isEmpty else { return }
        check()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observationTasks.append(workspace.eventsTask(named: name) { [weak self] in
                self?.check()
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isNeeded() else { return }
                self.check()
            }
        }
    }
}
