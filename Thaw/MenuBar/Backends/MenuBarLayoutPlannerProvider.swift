//
//  MenuBarLayoutPlannerProvider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// The move planner the layout and reconcile paths use.
///
/// Planning is a free function in PlatformRuntimeKit; this wraps it so the
/// callers state the capability they need instead of naming the engine, and so
/// the concrete type stays in one file rather than in eight.
nonisolated enum MenuBarLayoutPlannerProvider {
    static let current: any MenuBarLayoutPlanning = RuntimeLayoutPlannerAdapter()
}
