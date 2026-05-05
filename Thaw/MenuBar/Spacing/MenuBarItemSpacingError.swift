//
//  MenuBarItemSpacingError.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// An error that can occur while managing menu bar item spacing.
struct MenuBarItemSpacingError: Error {
    /// The kind of error that occurred.
    let kind: Kind

    /// The command that was being run when the error occurred.
    let command: String

    /// The arguments that were passed to the command.
    let arguments: [String]
}

extension MenuBarItemSpacingError {
    /// The kind of an error that can occur while managing menu bar item spacing.
    enum Kind {
        /// The process failed to run.
        case processRun(Error)
        /// The process exited with a non-zero status.
        case nonZeroExitStatus(Int32)
    }
}
