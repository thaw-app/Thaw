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

    /// Drops the words that still change once a reading's numbers are #: the weather
    /// conditions after "Currently #°", and a date's month and AM/PM.
    static func collapsingReadingWords(_ neutralized: String) -> String {
        if neutralized.hasPrefix("Currently #°") {
            return "Currently"
        }
        let month = /\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?(?= #)/
        return neutralized
            .replacing(month, with: "#")
            .replacing(/(#:#)\s*[AaPp]\.?\s?[Mm]\.?$/) { $0.output.1 }
    }
}
