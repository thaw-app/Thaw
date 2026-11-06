//
//  PendingPassTeardown.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Calls off repair passes that are armed and must not run: a settling period began, layout work was
/// suspended, or the user took the bar into their own hands.
///
/// Calling a pass off is four steps that belong together: cancel its task, drop the task, clear the
/// rerun it still owed, and tell the orchestrator to forget what was asked of it, so those requests
/// are not credited to a later, unrelated run. Written out at each site, a step is easy to leave out.
///
/// The passes are named by where their owner keeps them, so the owner keeps its stored properties and
/// gains no code of its own.
@MainActor
enum PendingPassTeardown<Owner: AnyObject> {
    /// Where an owner keeps one kind of pass.
    struct Pass {
        let work: RepairOrchestrator.Work
        /// The pass's armed task.
        let task: ReferenceWritableKeyPath<Owner, Task<Void, Never>?>
        /// The flag for one more pass owed after the running one, for work that keeps such a flag.
        var owedRerun: ReferenceWritableKeyPath<Owner, Bool>?
    }

    /// Cancels and drops every named pass in the order given, then forgets their requests in the same
    /// order. `alongside` runs between the two, for a caller that cancels other work in the same breath.
    static func callOff(
        _ passes: [Pass],
        of owner: Owner,
        on repairs: RepairOrchestrator,
        alongside: () -> Void = { /* Most callers cancel nothing else. */ }
    ) {
        for pass in passes {
            owner[keyPath: pass.task]?.cancel()
            owner[keyPath: pass.task] = nil
            if let owedRerun = pass.owedRerun {
                owner[keyPath: owedRerun] = false
            }
        }
        alongside()
        for pass in passes {
            repairs.withdraw(pass.work)
        }
    }
}

extension PendingPassTeardown.Pass where Owner == MenuBarItemManager {
    /// The repair that follows a restriction reflow.
    static var postRestrictionRepair: Self {
        Self(
            work: .postRestrictionRepair,
            task: \.postRestrictionRepairTask,
            owedRerun: \.postRestrictionRepairNeedsRerun
        )
    }

    /// The structural weight write that follows bar activity.
    static var structuralNormalization: Self {
        Self(work: .structuralNormalization, task: \.structuralNormalizationTask)
    }
}
