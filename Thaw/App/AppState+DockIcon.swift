//
//  AppState+DockIcon.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit

extension AppState {
    /// The policy for a window you open, such as Settings: regular puts Thaw in
    /// the Dock, nil only activates it. Even a moment as regular adds Thaw to
    /// the Dock's recent apps, so with the Dock icon off the policy is left alone.
    var userWindowActivationPolicy: NSApplication.ActivationPolicy? {
        Self.userWindowActivationPolicy(showDockIcon: Self.storedShowDockIconWithSettings)
    }

    static nonisolated func userWindowActivationPolicy(showDockIcon: Bool) -> NSApplication.ActivationPolicy? {
        showDockIcon ? .regular : nil
    }

    /// Read from Defaults, not the General model: the permissions window can
    /// open before the model loads its stored values.
    static var storedShowDockIconWithSettings: Bool {
        (Defaults.object(forKey: .showDockIconWithSettings) as? Bool) ?? Defaults.DefaultValue.showDockIconWithSettings
    }

    /// Applies a change of the Dock icon setting to the windows already open.
    func applyUserWindowActivationPolicy() {
        guard hasOpenWindow else {
            return
        }
        NSApp.setActivationPolicy(Self.storedShowDockIconWithSettings ? .regular : .accessory)
    }
}
