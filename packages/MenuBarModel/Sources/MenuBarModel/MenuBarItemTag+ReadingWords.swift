//
//  MenuBarItemTag+ReadingWords.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension MenuBarItemTag {
    /// Notion Calendar, still under Cron's bundle ID, has one item titled by the next event and
    /// its countdown, and untitled between events. No part of the title is stable.
    static let singleItemCalendarBundleMatchers: [(prefix: String, suffix: String)] = [
        (prefix: "com.cron.electron", suffix: ""),
    ]

    /// Whether bundleID is such a calendar. Its one item has no instance index, so a
    /// trailing ":<number>" in a saved identifier belongs to the event title.
    static func isSingleItemCalendar(_ bundleID: String) -> Bool {
        singleItemCalendarBundleMatchers.contains { bundleID.hasPrefix($0.prefix) && bundleID.hasSuffix($0.suffix) }
    }

    /// Drops weather conditions, months, AM/PM, the weekday in a weekday clock and a battery's
    /// charge state after the reading's numbers have been replaced with #.
    static func collapsingReadingWords(_ neutralized: String) -> String {
        if neutralized.hasPrefix("Currently #°") {
            return "Currently"
        }
        let month = TagRegex.readingMonth
        return neutralized
            .replacing(month, with: "#")
            .replacing(TagRegex.readingMeridiem) { $0.output.1 }
            .replacing(TagRegex.readingWeekday, with: "#")
            .replacing(TagRegex.readingBatteryState) { $0.output.1 }
    }
}
