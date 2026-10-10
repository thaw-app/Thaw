//
//  LiveApp.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The running app's delegate, for code the system calls with nothing to reach it by: an App Intent,
/// a Control Center control's command.
///
/// NSApp.delegate does not hold it. Under SwiftUI's app lifecycle that property is SwiftUI's own
/// delegate, which forwards to this one, so a cast of it to AppDelegate is always nil. Every intent
/// looked the delegate up that way, found nothing, and reported success having done nothing.
@MainActor
enum LiveApp {
    private(set) static weak var delegate: AppDelegate?

    static var appState: AppState? {
        delegate?.appState
    }

    /// Called by the delegate as the app launches.
    static func register(_ delegate: AppDelegate) {
        self.delegate = delegate
    }
}
