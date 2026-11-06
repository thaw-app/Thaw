//
//  ConcurrencyHelpers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawCapture

/// The timeout type is shared with the capture package through
/// ThawConcurrency. The alias keeps the name resolvable for the rest of the
/// app, which does not import ThawCapture directly.
typealias TaskTimeoutError = ThawConcurrency.TaskTimeoutError
