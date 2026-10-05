//
//  MenuBarPositionStoreProvider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// The preferred-position table the move and persistence paths read and write.
///
/// One seam over three PlatformRuntimeKit types that only ever get used
/// together: the store itself, the parked-weight rule, and the ledger of keys
/// settled as naming no icon. Callers reason about one table, so they ask one
/// thing about it.
///
/// The seam is also where MenuBarArrangementMode.manual takes effect. Every
/// path that could write a weight comes through here, so wrapping the store is
/// what makes "Thaw never reorders" true for callers that have never heard of
/// the setting, see ReadOnlyPositionStore. The one exception is forLayoutEdit.
nonisolated enum MenuBarPositionStoreProvider {
    /// The live store. Held rather than rebuilt because current sits on the
    /// move and enumeration paths, and both wrappers are cheap only if they are
    /// not re-boxed per call.
    @MainActor
    private static let live: any MenuBarPositionStoring = RuntimePositionStoreAdapter()

    /// live with its ordering writes refused, for manual arrangement.
    @MainActor
    private static let readOnly: any MenuBarPositionStoring = ReadOnlyPositionStore(wrapping: live)

    /// The store to use right now, chosen by arrangement mode.
    ///
    /// Read from Defaults rather than from AppState so the choice does not
    /// depend on settings having loaded, and so a caller deep in persistence
    /// need not reach for app state to get the right answer.
    @MainActor
    static var current: any MenuBarPositionStoring {
        let raw = Defaults.integer(forKey: .menuBarArrangementMode)
        return MenuBarArrangementMode(rawValue: raw) == .manual ? readOnly : live
    }

    /// The store for the writes an explicit Layout edit makes: live inside one, current otherwise.
    /// Only the move, seat and section-apply writes ask for it, so repair paths stay read-only in Manual.
    @MainActor
    static var forLayoutEdit: any MenuBarPositionStoring {
        ExplicitLayoutEdit.isActive ? live : current
    }
}
