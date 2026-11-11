//
//  TagRegex.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

/// Built once: a regex literal is parsed again on every evaluation, and these run for every item on each
/// overlay refresh, read and rebuild. Regex isn't marked Sendable, but it is immutable once built.
enum TagRegex {
    static nonisolated(unsafe) let appKitPlaceholder = /(_NS:\d+)(?::(\d+))?/
    static nonisolated(unsafe) let appKitPlaceholderTitle = /_NS:\d+/
    static nonisolated(unsafe) let appKitPlaceholderIdentifier = /_NS:\d+(?::\d+)?/
    static nonisolated(unsafe) let trailingClock = /\d{1,2}:\d{2}(?::\d{2})?$/
    static nonisolated(unsafe) let genericItem = /Item-\d+/
    static nonisolated(unsafe) let instanceSuffix = /.+:\d+/
    static nonisolated(unsafe) let number = /[-+]?\d+(?:[.,]\d+)?/
    static nonisolated(unsafe) let byteRate = /#\s*[KMGTPE]?[Bb]\/s/
    static nonisolated(unsafe) let byteSize = /#\s*[KMGTPE]?[Bb]/
    static nonisolated(unsafe) let readingMonth = /\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?(?= #| at\b)/
    static nonisolated(unsafe) let readingMeridiem = /(#:#)\s*[AaPp]\.?\s?[Mm]\.?$/
    static nonisolated(unsafe) let camelBoundary = /([a-z]{2})([A-Z])/
    static nonisolated(unsafe) let timeMachine = /TimeMachine/
}
