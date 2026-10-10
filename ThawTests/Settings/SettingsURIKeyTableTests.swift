//
//  SettingsURIKeyTableTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Keeps SettingsURIHandler.keyTable and the two settings models in step.
///
/// The URI handler's allow-list and the handleExternalSettingsChange
/// switches in AdvancedSettings and GeneralSettings are written by hand,
/// so a key can be settable but never applied, or applied but never settable.
/// These tests read the handler bodies straight from source, the same way
/// SettingsURIDispatchInventoryTests guards the dispatch gate, because the
/// change handlers are private and reaching them would launch the app.
@MainActor
@Suite("Settings URI key table")
struct SettingsURIKeyTableTests {
    private static var repositoryRoot: URL {
        // ThawTests/Settings/<this file> -> repository root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func sourceLines(_ relativePath: String) throws -> [String] {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        try #require(
            FileManager.default.fileExists(atPath: url.path),
            "\(relativePath) has moved; update this test to follow it"
        )
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        try #require(!lines.isEmpty, "\(relativePath) is empty")
        return lines
    }

    /// The body of functionName, by brace count from its declaration.
    private static func body(of functionName: String, in lines: [String]) throws -> ArraySlice<String> {
        let start = try #require(
            lines.firstIndex { $0.contains("func \(functionName)(") },
            "\(functionName) no longer exists; the table's drift guard needs a new test"
        )
        var depth = 0
        var sawOpeningBrace = false
        for index in start ..< lines.count {
            for character in lines[index] {
                if character == "{" {
                    depth += 1
                    sawOpeningBrace = true
                } else if character == "}" {
                    depth -= 1
                }
            }
            if sawOpeningBrace, depth == 0 {
                return lines[start ... index]
            }
        }
        Issue.record("Could not find the end of \(functionName)")
        return []
    }

    /// Every case "..." and key == "..." literal inside the handler.
    ///
    /// The switch cases and the equality checks are the only two shapes the
    /// change handlers use to name a key.
    private static func externalChangeKeys(in relativePath: String, functionName: String) throws -> Set<String> {
        let lines = try sourceLines(relativePath)
        let body = try body(of: functionName, in: lines).joined(separator: "\n")
        var keys: Set<String> = []
        for pattern in ["case \"([^\"]+)\"", "key == \"([^\"]+)\""] {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(body.startIndex ..< body.endIndex, in: body)
            for match in regex.matches(in: body, range: range) {
                if let keyRange = Range(match.range(at: 1), in: body) {
                    keys.insert(String(body[keyRange]))
                }
            }
        }
        return keys
    }

    @Test("Every table key is registered except the allowlist")
    func everyTableKeyIsRegisteredExceptAllowlist() throws {
        let lines = try Self.sourceLines("Thaw/System/Defaults.swift")
        let start = try #require(
            lines.firstIndex { $0.contains("var defaultRegistrationValues") },
            "Defaults.defaultRegistrationValues no longer exists; update this test"
        )
        let end = try #require(
            lines.firstIndex { $0.contains("func registerDefaults") },
            "Defaults.registerDefaults no longer exists; update this test"
        )
        let pattern = try NSRegularExpression(pattern: #"^\s*\.([A-Za-z0-9_]+)\s*:"#)
        var registered: Set<String> = []
        for line in lines[start ..< end] {
            let range = NSRange(line.startIndex ..< line.endIndex, in: line)
            if let match = pattern.firstMatch(in: line, range: range),
               let nameRange = Range(match.range(at: 1), in: line)
            {
                registered.insert(String(line[nameRange]))
            }
        }
        #expect(!registered.isEmpty, "Found no registered defaults; the parse has drifted")

        for (uriKey, entry) in SettingsURIHandler.keyTable {
            let caseName = String(describing: entry.defaultsKey)
            if uriKey == "enableSwapBar" {
                #expect(
                    !registered.contains(caseName),
                    "\(uriKey) must stay unregistered so its legacy-key migration still runs"
                )
            } else {
                #expect(
                    registered.contains(caseName),
                    "\(uriKey) maps to \(caseName), which Defaults.registerDefaults never registers"
                )
            }
        }
    }

    @Test("Every table key names a real Defaults.Key")
    func everyTableKeyMapsToARealDefaultsKey() {
        #expect(!SettingsURIHandler.keyTable.isEmpty, "An empty table would satisfy every check below")

        for (uriKey, entry) in SettingsURIHandler.keyTable {
            #expect(
                Defaults.Key(rawValue: entry.defaultsKey.rawValue) == entry.defaultsKey,
                "\(uriKey) maps to a Defaults.Key whose raw value does not round-trip"
            )
        }

        let mappedKeys = SettingsURIHandler.keyTable.map(\.value.defaultsKey)
        #expect(
            Set(mappedKeys).count == mappedKeys.count,
            "Two URI keys map to the same Defaults.Key; one of them would read and write the other's storage"
        )
    }

    @Test("Every external-change case is reachable from the table")
    func everyExternalChangeCaseIsInTheTable() throws {
        let tableKeys = Set(SettingsURIHandler.keyTable.keys)
        let sources = [
            ("Thaw/Settings/Models/Preferences/AdvancedSettings.swift", "handleExternalSettingsChange"),
            ("Thaw/Settings/Models/Preferences/GeneralSettings.swift", "handleExternalSettingsChange"),
        ]

        for (path, function) in sources {
            let keys = try Self.externalChangeKeys(in: path, functionName: function)
            #expect(!keys.isEmpty, "\(path) no longer handles any keys; update this test")
            for key in keys {
                #expect(
                    tableKeys.contains(key),
                    "\(path) applies \(key), but SettingsURIHandler.keyTable never posts it"
                )
            }
        }
    }
}
