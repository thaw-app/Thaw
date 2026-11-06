//
//  ProfileOrderHold.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Keeps a profile's Visible order as Thaw's saved one after the profile is applied, until the
/// bar can show all of it.
///
/// Thaw records the bar's order as its saved one whenever the bar looks settled. A profile
/// applied while some of its items had not appeared yet, as when macOS answers for no app's
/// items for a minute after launch, arranges the rest around them. Recording that bar replaced
/// the profile's order, and LeftOutMemberWatch then restored the late items into the partial
/// arrangement. While the hold lasts the record keeps the profile's Visible order, so the watch
/// restores that. Orders written on purpose, such as a Layout edit, still replace it.
nonisolated struct ProfileOrderHold: Equatable {
    /// The longest a hold lasts, the time LeftOutMemberWatch watches for a member: an item that
    /// never appears can't keep the record from following the bar for good.
    static let limit: Duration = .seconds(120)

    let startedAt: ContinuousClock.Instant

    /// Whether the hold is over: no member a pass left out still waits to be placed, the user
    /// arranged the bar since the profile was applied, or the hold ran its limit.
    func isOver(
        membersStillLeftOut: Bool,
        userArrangedAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        guard membersStillLeftOut else { return true }
        if let userArrangedAt, userArrangedAt > startedAt {
            return true
        }
        return startedAt.duration(to: now) >= Self.limit
    }
}
