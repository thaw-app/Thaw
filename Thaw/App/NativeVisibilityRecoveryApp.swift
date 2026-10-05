//
//  NativeVisibilityRecoveryApp.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A separate bootstrap deliberately never constructs AppState or its engines.
struct NativeVisibilityRecoveryApp: App {
    @NSApplicationDelegateAdaptor private var delegate: NativeVisibilityRecoveryDelegate

    var body: some Scene {
        Window("Menu Bar Visibility Recovery", id: "visibility-recovery") {
            NativeVisibilityRecoveryView()
        }
        .defaultSize(width: 680, height: 600)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
    }
}

@MainActor
private final class NativeVisibilityRecoveryDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
