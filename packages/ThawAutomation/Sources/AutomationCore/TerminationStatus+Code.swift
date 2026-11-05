//
//  TerminationStatus+Code.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Subprocess

extension TerminationStatus {
    /// The exit code, or the signal number for a process a signal ended.
    /// The app keeps its own copy; it does not link AutomationCore.
    var code: Code {
        switch self {
        case let .exited(code), let .signaled(code): code
        }
    }
}
