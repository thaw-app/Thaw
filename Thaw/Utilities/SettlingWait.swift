//
//  SettlingWait.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Waits out a settling period that a later settle can replace with a new task.
@MainActor
enum SettlingWait {
    /// Follows the settling task through replacements. Returns when the settle ends, when the awaited task
    /// finished and nothing replaced it, or when the caller is cancelled.
    static func follow(isSettling: () -> Bool, currentTask: () -> Task<Void, Never>?) async {
        while !Task.isCancelled, isSettling(), let task = currentTask() {
            await task.value
            guard currentTask() != task else { return }
        }
    }
}
