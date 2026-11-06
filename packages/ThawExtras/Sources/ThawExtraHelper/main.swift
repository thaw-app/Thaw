//
//  main.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = ExtraHelperDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
