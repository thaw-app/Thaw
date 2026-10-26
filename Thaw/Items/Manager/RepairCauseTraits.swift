//
//  RepairCauseTraits.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// What a request stamped with a cause does to the passes around it.
nonisolated struct RepairCauseTraits: Equatable, Sendable {
    /// Someone is at the bar, so the passes this cause starts are not a loop.
    var isUserAction = false
    /// The user has changed the layout.
    var isLayoutChangeByUser = false
    /// The automatic passes asked for before this cause were planned on a bar that is changing under them, so they are called off.
    var callsOffPlannedWork = false
    /// The loop budget starts again, lifting a pause.
    var refillsBudget = false
    /// The passes this cause asks for keep their turn when the user acts later.
    var keepsTurnOnUserInput = false

    /// A cause that only says where a request came from.
    static let attribution = Self()

    /// The user acting at the bar without changing the layout.
    static let userAction = Self(isUserAction: true, refillsBudget: true, keepsTurnOnUserInput: true)

    /// The user changing the layout.
    static let userLayoutChange = Self(isUserAction: true, isLayoutChangeByUser: true, refillsBudget: true, keepsTurnOnUserInput: true)

    /// The user starting something that changes the bar under the passes already planned.
    static let userInput = Self(isUserAction: true, callsOffPlannedWork: true, refillsBudget: true, keepsTurnOnUserInput: true)
}

extension RepairOrchestrator.Cause {
    var traits: RepairCauseTraits {
        switch self {
        case .userDragEnded, .userEdit:
            .userLayoutChange
        case .sectionRevealed:
            .userAction
        case .revealStarting, .userDragStarted, .userClickedItem:
            .userInput
        case .policyReveal:
            // Not the user, but the restores it asks for run at user priority, so later input never calls them off.
            RepairCauseTraits(keepsTurnOnUserInput: true)
        case .displayChanged:
            // A new display arrangement makes every planned pass stale, and nothing planned on it has looped yet.
            RepairCauseTraits(callsOffPlannedWork: true, refillsBudget: true)
        case .moveFulfilled, .structuralDriftObserved, .revealHideTransition, .settled, .restrictionChanged,
             .cachePublished, .nativeOverflowChanged, .arrivalDisturbedOrder, .layoutApplyBlocked, .rearmed,
             .profileApplied, .settingChanged, .spaceChanged, .appLaunched, .appTerminated:
            .attribution
        }
    }
}
