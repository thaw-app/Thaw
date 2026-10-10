//
//  LayoutChangeReason.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Observed changes accept the settled live order; only explicit requests may enforce order.
/// Deriving permission here prevents automatic callers from claiming it.
public enum LayoutChangeReason: Sendable, Hashable {
    /// An observed app change, AX refresh, overflow change, or native overflow control arrival.
    case externalChange
    /// The user rearranged items directly (a layout-pane drop, a group edit).
    case userReorder
    /// The user applied a profile or a saved layout.
    case profileApply
    /// The user revealed a section; the reveal restores what was recorded.
    case revealRestore
    /// A setting reshaped the bar, such as toggling overflow or returning the overlay conceal set.
    case settingChange
    /// A new item arrived and disturbed the order of the items already there;
    /// the recorded order is written back without moving the pointer.
    case arrivalRestore

    /// Whether this reason may move items or write preferred positions at all.
    public var permitsOrderEnforcement: Bool {
        switch self {
        case .externalChange: false
        case .userReorder, .profileApply, .revealRestore, .settingChange, .arrivalRestore: true
        }
    }

    /// Authored edits may run during restriction reflow and bypass the idle convergence budget.
    public var isAuthoredEdit: Bool {
        switch self {
        case .userReorder, .profileApply, .settingChange: true
        case .externalChange, .revealRestore, .arrivalRestore: false
        }
    }

    /// User-initiated passes bypass the circuit breaker that stops repeated failed automatic drags.
    public var isUserInitiated: Bool {
        switch self {
        case .userReorder, .profileApply, .revealRestore, .settingChange: true
        case .externalChange, .arrivalRestore: false
        }
    }

    /// Whether the pass may move items under Manual arrangement, where only the user's own Layout edit does.
    public var permitsMoveInManualArrangement: Bool {
        self == .userReorder
    }

    /// Whether the pass may only write preferred positions. Nobody asked for
    /// this pass, so it never drags an item or takes the pointer.
    public var isPositionWriteOnly: Bool {
        self == .arrivalRestore
    }
}
