//
//  TerminationStatus+Code.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Subprocess

nonisolated extension TerminationStatus {
    /// The exit code, or the signal number for a process a signal ended.
    /// AutomationCore keeps its own copy; the app does not link it.
    var code: Code {
        switch self {
        case let .exited(code), let .signaled(code): code
        }
    }
}
