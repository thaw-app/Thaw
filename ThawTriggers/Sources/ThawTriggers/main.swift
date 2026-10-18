//
//  main.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

let app = NSApplication.shared
let delegate = TriggersAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
