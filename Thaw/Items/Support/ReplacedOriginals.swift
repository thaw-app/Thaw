//
//  ReplacedOriginals.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Apple's items whose place one of Thaw's stand-ins has taken.
///
/// The original stays assigned to Hidden so macOS keeps it off the bar, and macOS can still report it
/// there. Listed, it shows beside its stand-in: two AirDrops in Layout and in the Thaw Bar.
nonisolated enum ReplacedOriginals {
    /// items without the originals in replaced, which holds canonical identifiers.
    static func excluding(_ items: [MenuBarItem], replaced: Set<String>) -> [MenuBarItem] {
        guard !replaced.isEmpty else { return items }
        return items.filter { !replaced.contains($0.canonicalIdentifier) }
    }
}
