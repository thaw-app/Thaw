//
//  MenuBarItemSpacingError.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// An error that can occur while managing menu bar item spacing.
struct MenuBarItemSpacingError: Error {
    let kind: Kind
    let command: String
    let arguments: [String]
}

extension MenuBarItemSpacingError {
    enum Kind {
        /// The process failed to run.
        case processRun(Error)
        /// The process exited with a non-zero status.
        case nonZeroExitStatus(Int32)
    }
}
