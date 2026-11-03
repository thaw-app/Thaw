//
//  NativeVisibilityRecoveryBypassing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// An optional runtime capability for leaving recovery after the user explicitly chose to skip it.
/// Older runtimes do not conform, so hosts keep their existing recovery flow.
@MainActor
public protocol NativeVisibilityRecoveryBypassing: AnyObject {
    /// Backs up the recovery records before removing them from active recovery.
    /// Changes neither app visibility nor saved layouts and returns the backup locations.
    @discardableResult
    func bypassRecovery() throws -> [URL]
}
