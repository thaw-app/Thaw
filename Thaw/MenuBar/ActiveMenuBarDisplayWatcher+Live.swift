//
//  ActiveMenuBarDisplayWatcher+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Observation

extension ActiveMenuBarDisplayWatcher {
    /// Checks on app activation and a Space change, and once a second while
    /// something needs the answer and the displays are awake.
    func start() {
        guard observationTasks.isEmpty else { return }
        check()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observationTasks.append(workspace.eventsTask(named: name) { [weak self] in
                self?.check()
            })
        }
        // A display that connects can bring its always-show setting with it, which no observation sees.
        observationTasks.append(NotificationCenter.default.eventsTask(named: NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.updateTimer()
        })
        observationTasks.append(Task { @MainActor [weak self] in
            for await _ in Observations({ [weak self] in self?.isNeeded() ?? false }) {
                self?.updateTimer()
            }
        })
        idleGateSubscription = idleGate.subscribe { [weak self] mayRun in
            self?.updateTimer()
            if mayRun {
                self?.check()
            }
        }
        updateTimer()
    }
}
