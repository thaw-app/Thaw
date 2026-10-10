//
//  ExplicitLayoutEdit.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Marks the task tree carrying out an edit the user made in Layout: a drop, a keyboard move, or a sort.
/// Task-local, so an automatic pass running at the same time never sees it and Manual still stops that pass.
nonisolated enum ExplicitLayoutEdit {
    /// Task { } inherits this; Task.detached does not.
    @TaskLocal static var isActive = false

    /// Runs a synchronous UI handler as an explicit edit; the tasks it starts inherit the mark.
    static func perform<Result>(_ edit: () throws -> Result) rethrows -> Result {
        try $isActive.withValue(true, operation: edit)
    }

    /// Starts the work of an edit the user asked for from a menu or a button, where there is no drop to wrap.
    /// Without the mark, Manual refuses the move as if Thaw had decided on it.
    @MainActor
    @discardableResult
    static func task(_ edit: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        perform { Task { @MainActor in await edit() } }
    }

    /// Whether Manual arrangement refuses a single move: everything but an explicit edit.
    static func manualArrangementForbidsMoves(
        arrangementIsManual: Bool,
        isExplicitLayoutEdit: Bool
    ) -> Bool {
        arrangementIsManual && !isExplicitLayoutEdit
    }

    /// The section-order form. The reason must agree, so a restore that runs inside an edit's task is still refused.
    static func manualArrangementForbids(
        arrangementIsManual: Bool,
        isExplicitLayoutEdit: Bool,
        reason: LayoutChangeReason
    ) -> Bool {
        arrangementIsManual && !(isExplicitLayoutEdit && reason.permitsMoveInManualArrangement)
    }
}
