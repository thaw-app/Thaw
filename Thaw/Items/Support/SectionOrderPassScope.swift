//
//  SectionOrderPassScope.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// What one section-order pass is for: the reveal it belongs to and the items it puts in order.
///
/// The pass runs across awaits, so it asks again whether it is still wanted before each write. The caller
/// reads the controller and passes plain values in.
nonisolated enum SectionOrderPassScope {
    /// Whether the pass is still wanted. A pass started for a reveal is only wanted while that section is
    /// the one revealed; hiding it, or revealing another, ends the work, since it would reorder a bar the
    /// user no longer has open. A pass with no reveal is wanted until it is cancelled.
    static func isStillWanted(
        isCancelled: Bool,
        startedWhileRevealing expected: MenuBarSection.Name?,
        revealedNow: MenuBarSection.Name?
    ) -> Bool {
        guard !isCancelled else {
            return false
        }
        guard let expected else {
            return true
        }
        return revealedNow == expected
    }

    /// The identifiers the pass puts in order for a section: the recorded order, narrowed to the items
    /// the controller assigns to that section. Only Visible takes a replacement order, which a reveal
    /// passes as the mirrored bar order and a pane edit as the order it just committed.
    static func desiredOrder(
        for section: MenuBarSection.Name,
        recorded: [String]?,
        visibleOverride: [String]?,
        sectionOf: (String) -> MenuBarSection.Name?
    ) -> [String] {
        let source = if section == .visible, let visibleOverride {
            visibleOverride
        } else {
            recorded ?? []
        }
        return source.filter { sectionOf($0) == section }
    }
}
