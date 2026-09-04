//
//  DiagnosticRedactor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Removes potentially sensitive information from diagnostic text before it
/// leaves the Mac.
///
/// Reports keep app and menu bar identifiers plus display geometry because
/// those values are needed to investigate move failures. Exact terms supplied
/// by the caller remove account, network, device, and trigger values; general
/// patterns provide a second layer for paths, addresses, and location pairs.
/// Automated redaction is best effort, so callers must still ask the user to
/// review a report before sharing it.
nonisolated struct DiagnosticRedactor {
    /// An exact string to replace wherever it appears.
    struct Term: Hashable {
        /// The text to remove.
        let value: String

        /// What to put in its place.
        let placeholder: String

        init(_ value: String, placeholder: String) {
            self.value = value
            self.placeholder = placeholder
        }
    }

    /// Terms shorter than this are matched only at identifier boundaries.
    /// A short account name such as "Li" still needs redaction, but must not
    /// turn an unrelated value such as "client" into "c<user>ent".
    static let minimumTermLength = 3

    /// The exact terms, longest first, so containing values are replaced
    /// before their substrings.
    let terms: [Term]

    init(terms: [Term]) {
        let usable = Set(terms.filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        self.terms = usable.sorted { lhs, rhs in
            if lhs.value.count != rhs.value.count {
                return lhs.value.count > rhs.value.count
            }
            return lhs.value < rhs.value
        }
    }

    /// Terms for the current macOS account: the home directory, login name,
    /// full name, and each component of the full name.
    static func accountTerms(
        userName: String = NSUserName(),
        fullName: String = NSFullUserName(),
        homeDirectory: String = NSHomeDirectory()
    ) -> [Term] {
        var terms = [
            Term(homeDirectory, placeholder: "~"),
            Term(userName, placeholder: "<user>"),
        ]
        let trimmedFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFullName.isEmpty {
            terms.append(Term(trimmedFullName, placeholder: "<user>"))
        }
        for part in fullName.split(whereSeparator: \.isWhitespace) {
            terms.append(Term(String(part), placeholder: "<user>"))
        }
        return terms
    }

    /// Returns `text` with every exact term and recognized pattern replaced.
    func redact(_ text: String) -> String {
        var result = text
        for term in terms {
            if term.value.count < Self.minimumTermLength {
                let escaped = NSRegularExpression.escapedPattern(for: term.value)
                let pattern = #"(?i)(?<![\p{L}\p{M}\p{N}_])"# + escaped + #"(?![\p{L}\p{M}\p{N}_])"#
                result = result.replacingOccurrences(
                    of: pattern,
                    with: term.placeholder,
                    options: .regularExpression
                )
            } else {
                result = result.replacingOccurrences(
                    of: term.value,
                    with: term.placeholder,
                    options: [.caseInsensitive]
                )
            }
        }
        // Any home directory, not only the current account's.
        result = result.replacing(#//Users/[^/\s"'`)\]]+/#, with: "/Users/<user>")
        result = result.replacing(#/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/#, with: "<email>")
        result = result.replacing(#/\b(?:\d{1,3}\.){3}\d{1,3}\b/#, with: "<ip-address>")
        result = result.replacingOccurrences(
            of: #"(?<![0-9A-Fa-f:])(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4}){0,5})?|::(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4}){0,6})?)(?![0-9A-Fa-f:])"#,
            with: "<ip-address>",
            options: .regularExpression
        )
        // IPv6 must run first: a full eight-group address can contain a
        // six-group substring that also satisfies the MAC-address pattern.
        result = result.replacing(#/\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b/#, with: "<mac-address>")
        // Values written after privacy-sensitive labels. This catches
        // trigger-like values that can appear in a log without requiring the
        // report code to depend on a particular automation implementation.
        // The optional quote after the label covers JSON-style field names
        // such as {"wifiSSID":"Home Network"}.
        result = result.replacingOccurrences(
            of: #"(?i)\b(?:ssid|wifi(?:ssid|network)?|networkname|devicename|bluetoothdevice|audiodevice|focusmode|trigger(?:name|value)?|condition(?:name|value)?|script(?:path|output)|location(?:name|label)?)"?\s*[=:]\s*(?:\"[^\"\r\n]*\"|'[^'\r\n]*'|[^,;\r\n]+)"#,
            with: "<sensitive-value>",
            options: .regularExpression
        )
        // A high-precision latitude/longitude pair. Menu bar geometry uses
        // one decimal and is intentionally retained for debugging.
        result = result.replacing(#/-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}/#, with: "<coordinates>")
        return result
    }
}
