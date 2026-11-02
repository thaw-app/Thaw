//
//  TimeMachineStatus.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// What `tmutil status` says about the current backup. It prints an old-style
/// property list, and only two top-level keys matter here: Running, and the
/// Percent done, which is -1 while nothing is copying yet.
struct TimeMachineStatus: Equatable {
    var isRunning: Bool
    /// From 0 to 1, or nil before copying starts.
    var fraction: Double?

    static let idle = TimeMachineStatus(isRunning: false, fraction: nil)

    /// Reads the first Running and Percent lines. A nested Progress block
    /// repeats Percent with the same value, so the first one is enough.
    static func parse(_ output: String) -> TimeMachineStatus {
        var isRunning = false
        var fraction: Double?
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Running = ") {
                isRunning = value(of: trimmed) == "1"
            } else if fraction == nil, trimmed.hasPrefix("Percent = "), let number = Double(value(of: trimmed)), number >= 0 {
                fraction = min(number, 1)
            }
        }
        return TimeMachineStatus(isRunning: isRunning, fraction: isRunning ? fraction : nil)
    }

    private static func value(of line: String) -> String {
        guard let equals = line.firstIndex(of: "=") else { return "" }
        return line[line.index(after: equals)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " ;\""))
    }

    /// How long to wait before asking tmutil again, or nil to stop asking.
    /// Each ask wakes backupd, so the idle wait is long: a backup shows up
    /// within half a minute, and opening the menu or Back Up Now asks at once.
    /// While one runs the wait is short, for the percentage. Nothing is asked
    /// while Thaw hides the stand-in or the screens are asleep.
    static func pollInterval(isRunning: Bool, isHiddenByThaw: Bool, areScreensAsleep: Bool) -> Duration? {
        if isHiddenByThaw || areScreensAsleep {
            return nil
        }
        return isRunning ? .seconds(3) : .seconds(30)
    }

    /// Whether the stand-in belongs in the menu bar. Thaw hiding it wins, and
    /// with "Show Only While Backing Up" on it appears only during a backup.
    static func showsItem(hiddenByThaw: Bool, onlyWhileBackingUp: Bool, isRunning: Bool) -> Bool {
        !hiddenByThaw && (!onlyWhileBackingUp || isRunning)
    }
}
