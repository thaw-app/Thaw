//
//  ControlCenterIcon.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The Control Center icon, fetched at most once per launch.
///
/// Rows for the multi-item system agents, Control Center itself,
/// SystemUIServer, the text input menu agent, all display it in place of an
/// icon of their own, in both the search panel and the item palette.
@MainActor
enum ControlCenterIcon {
    private static var resolved: NSImage?

    static var image: NSImage? {
        if resolved == nil {
            resolved = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
                .first?
                .icon
        }
        return resolved
    }
}
