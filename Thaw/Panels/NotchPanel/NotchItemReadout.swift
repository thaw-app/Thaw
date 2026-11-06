//
//  NotchItemReadout.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

nonisolated struct NotchItemReadout: Equatable {
    let primary: String
    /// A second, non-overlapping line, when the item offered one.
    let secondary: String?
}

/// Reject accessibility text that adds nothing beyond the item's name and boilerplate.
nonisolated enum NotchReadoutResolver {
    /// Ignore boilerplate when testing meaning, not when displaying text.
    /// "Garage Open" keeps "Open"; "Open Philips Hue" adds nothing beyond the app name.
    private static let fillerWords: Set<String> = [
        "a", "an", "the", "of", "for", "to",
        "app", "application", "menu", "menubar", "bar", "item", "items",
        "status", "statusitem", "extra", "extras", "icon", "indicator",
        "button", "control", "click", "press", "show", "shows", "open", "opens",
    ]

    /// Characters that only ever separate a name from the thing it qualifies.
    private static let separators = CharacterSet(charactersIn: ":-–—|·•,()[]{}")

    /// Shorter candidates are glyph labels, not additional state information.
    private static let minimumLength = 3

    /// Picks up to two meaningful lines after excluding known item names.
    /// - Parameters:
    ///   - candidates: Accessibility strings, most promising first.
    ///   - names: The item's app name, window title, and bundle name.
    static func resolve(candidates: [String?], names: [String?]) -> NotchItemReadout? {
        let nameWords = Set(names.compactMap(\.self).flatMap(words(in:)))

        var accepted: [(text: String, meaning: Set<String>)] = []
        for candidate in candidates.compactMap(\.self) {
            guard let text = refine(candidate, nameWords: nameWords) else {
                continue
            }
            let meaning = Set(words(in: text)).subtracting(nameWords).subtracting(fillerWords)
            // Reject overlapping meaning words so lines like "78 Cloudy" and "Cloudy in San Diego" do not repeat.
            guard !accepted.contains(where: { !meaning.isDisjoint(with: $0.meaning) }) else {
                continue
            }
            accepted.append((text, meaning))
            if accepted.count == 2 {
                break
            }
        }

        guard let primary = accepted.first else {
            return nil
        }
        return NotchItemReadout(
            primary: primary.text,
            secondary: accepted.count > 1 ? accepted[1].text : nil
        )
    }

    /// Strip names only from label-like ends, preserving names within sentences.
    /// Reject the remainder if it carries no meaning.
    private static func refine(_ raw: String, nameWords: Set<String>) -> String? {
        var parts = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        var leading = 0
        while leading < parts.count, isNameOrSeparator(parts[leading], nameWords: nameWords) {
            leading += 1
        }
        if leading > 0, leading < parts.count, !startsLabel(parts, after: leading) {
            // Keep sentence subjects intact, as in "Amphetamine is active for 2 hours".
            leading = 0
        }
        parts.removeFirst(leading)
        while let last = parts.last, isNameOrSeparator(last, nameWords: nameWords) {
            parts.removeLast()
        }

        let text = parts.joined(separator: " ")
            .trimmingCharacters(in: separators.union(.whitespaces))
        guard text.count >= minimumLength else {
            return nil
        }

        // Names and boilerplate alone add no state information.
        let meaning = Set(words(in: text)).subtracting(nameWords).subtracting(fillerWords)
        guard !meaning.isEmpty else {
            return nil
        }
        return text
    }

    /// Punctuation or a new phrase after the name indicates a label rather than a sentence subject.
    private static func startsLabel(_ parts: [String], after index: Int) -> Bool {
        if let previous = parts[index - 1].unicodeScalars.last, separators.contains(previous) {
            return true
        }
        guard let next = parts[index].trimmingCharacters(in: separators.union(.whitespaces)).first else {
            return true
        }
        return !next.isLowercase
    }

    private static func isNameOrSeparator(_ part: String, nameWords: Set<String>) -> Bool {
        let stripped = part.trimmingCharacters(in: separators.union(.whitespaces))
        if stripped.isEmpty {
            return true
        }
        return words(in: stripped).allSatisfy { nameWords.contains($0) }
    }

    /// Fold case and diacritics, splitting on non-alphanumerics for consistent name and candidate comparisons.
    private static func words(in string: String) -> [String] {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
