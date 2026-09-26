//
//  main.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

Listener.shared.activate()

while true {
    autoreleasepool {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 60))
    }
}
