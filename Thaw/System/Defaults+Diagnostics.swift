//
//  Defaults+Diagnostics.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

nonisolated extension Defaults.DefaultValue {
    #if DEBUG
        static let enableDiagnosticLogging = true
    #else
        static let enableDiagnosticLogging = false
    #endif
    /// Thaw 2's log settings and defaults, stored under its key names so they carry over.
    static let diagnosticLogMaxSizeMB = 10
    static let diagnosticLogRetentionDays = 2
    static let diagnosticLogRotationInterval = LogRotationInterval.off
}
