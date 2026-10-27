//
//  main.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

if #available(macOS 26.0, *) {
    Listener.shared.activate()
    while true {
        autoreleasepool {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 60))
        }
    }
} else {
    Listener.shared.runLegacyMain()
}
