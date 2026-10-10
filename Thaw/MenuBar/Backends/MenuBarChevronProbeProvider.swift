//
//  MenuBarChevronProbeProvider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// The overflow-chevron hit-test the item provider and the cover both use.
///
/// Typed as the concrete adapter rather than any MenuBarChevronProbing.
/// MenuBarModel sits below the runtime kit and cannot name
/// NativeOverflowObservation, so its seam can only carry frames, and both
/// callers here have to tell a strip that was swept and holds no chevron from
/// one the sweep never finished reading.
nonisolated enum MenuBarChevronProbeProvider {
    static let current = RuntimeChevronProbeAdapter()
}
