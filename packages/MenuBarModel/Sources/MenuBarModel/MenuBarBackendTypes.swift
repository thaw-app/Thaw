//
//  MenuBarBackendTypes.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// Single-case enums are kept so a second policy can return without
// reshaping MenuBarBackend.

/// What the manager persists when the "should persist now" gate is open.
/// The manager owns the I/O and guards; the backend only picks the policy.
public enum LayoutSnapshotAction: Equatable {
    /// Persist nothing this cycle.
    case none
    /// Mirror the curated section order out of itemCache into
    /// savedSectionOrder (membership is owned by RuntimeSectionController).
    case mirrorSectionOrder
}

/// How the divider control items are kept ordered. The backend picks the
/// model; the manager runs the async moves behind the divider-thrash guard.
public enum ControlItemEnforcementStrategy: Equatable {
    /// Assignment-anchored dividers, reordered via
    /// RuntimeLayoutCoordinator.dividerMoveDestination behind the thrash guard.
    case assertionDividerReorder
}

public enum PreferredMovePath: Equatable {
    case preferredPositionsThenCommandDrag
}

public enum SectionResetTarget: Equatable {
    case freshInstallHidden
    case allVisible
    case allAlwaysHidden
}

public enum LayoutResetExecution: Equatable {
    case assignmentSweep(MenuBarSectionName?)
}

public enum ProfileLayoutStrategy: Equatable {
    case assignmentApply
}

public enum SavedLayoutRestoreStrategy: Equatable {
    case visibleControlOrderOnly
}
