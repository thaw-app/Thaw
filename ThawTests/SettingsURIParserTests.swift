//
//  SettingsURIParserTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Parses `string` as a `thaw://` URL, failing the test if it is not a valid URL.
private func parse(_ string: String) throws -> SettingsURIRequest {
    let url = try #require(URL(string: string), "Could not build a URL from \(string)")
    return SettingsURIParser.parse(url)
}

@Suite("SettingsURIParser")
struct SettingsURIParserTests {
    @Suite("set")
    struct Set {
        @Test("Key and value produce a set route")
        func keyAndValue() throws {
            #expect(try parse("thaw://set?key=autoRehide&value=true").route
                == .set(key: "autoRehide", value: "true", displayUUID: nil))
        }

        @Test("Display parameter is carried through")
        func displayUUID() throws {
            #expect(try parse("thaw://set?key=useIceBar&value=false&display=ABC-123").route
                == .set(key: "useIceBar", value: "false", displayUUID: "ABC-123"))
        }

        /// `key=` supplies an empty value rather than omitting the parameter, so
        /// it parses and is rejected later by key validation. ThawCtl and Droppy
        /// both emit this shape, so it must not be treated as malformed.
        @Test("An empty key is present, not absent", arguments: [
            "thaw://set?key=&value=true",
            "thaw://toggle?key=",
        ])
        func emptyKeyIsNotMalformed(uri: String) throws {
            let route = try parse(uri).route
            #expect(route != .malformed(host: "set"))
            #expect(route != .malformed(host: "toggle"))
        }
    }

    @Suite("toggle")
    struct Toggle {
        @Test("Key produces a toggle route")
        func withKey() throws {
            #expect(try parse("thaw://toggle?key=autoRehide").route
                == .toggle(key: "autoRehide", displayUUID: nil))
        }
    }

    @Suite("get")
    struct Get {
        @Test("All parameters are captured")
        func allParameters() throws {
            #expect(try parse("thaw://get?key=all&callback=droppy://thaw-response&broadcast=true&requestId=42").route
                == .get(
                    key: "all",
                    displayUUID: nil,
                    callback: "droppy://thaw-response",
                    broadcast: true,
                    requestId: "42"
                ))
        }

        /// `get` never reports malformed: every parameter is optional.
        @Test("A bare get is well formed")
        func bareGet() throws {
            #expect(try parse("thaw://get").route
                == .get(key: nil, displayUUID: nil, callback: nil, broadcast: false, requestId: nil))
        }

        @Test("broadcast is true only for exactly \"true\"", arguments: [
            ("thaw://get?broadcast=true", true),
            ("thaw://get?broadcast=TRUE", false),
            ("thaw://get?broadcast=1", false),
            ("thaw://get", false),
        ])
        func broadcast(uri: String, expected: Bool) throws {
            guard case let .get(_, _, _, broadcast, _) = try parse(uri).route else {
                Issue.record("Expected a get route for \(uri)")
                return
            }
            #expect(broadcast == expected)
        }

        @Test("Only get?key=version is a version query", arguments: [
            ("thaw://get?key=version", true),
            ("thaw://get?key=all", false),
            ("thaw://set?key=version&value=1", false),
        ])
        func versionQuery(uri: String, expected: Bool) throws {
            #expect(try parse(uri).isVersionQuery == expected)
        }
    }

    @Suite("Routing")
    struct Routing {
        @Test("authorize is its own route")
        func authorize() throws {
            #expect(try parse("thaw://authorize").route == .authorize)
        }

        @Test("Every action round-trips from its raw value", arguments: SettingsURIAction.allCases)
        func actionRoundTrip(action: SettingsURIAction) throws {
            #expect(try parse("thaw://\(action.rawValue)").route == .action(action))
        }

        @Test("Unknown and empty hosts are unrecognized", arguments: [
            ("thaw://not-a-real-host", "not-a-real-host"),
            ("thaw://", ""),
        ])
        func unrecognized(uri: String, host: String) throws {
            #expect(try parse(uri).route == .unrecognized(host: host))
        }

        @Test("Hosts are matched case-insensitively")
        func caseInsensitiveHost() throws {
            #expect(try parse("thaw://SET?key=a&value=b").route
                == .set(key: "a", value: "b", displayUUID: nil))
            #expect(try parse("thaw://Toggle-Hidden").route == .action(.toggleHidden))
        }
    }

    @Suite("Authorization surface")
    struct Authorization {
        /// Incomplete settings URLs must not be able to raise an approval
        /// dialog, so they are rejected before the authorization gate.
        @Test("Missing required parameters yield malformed", arguments: [
            ("thaw://set", "set"),
            ("thaw://set?key=autoRehide", "set"),
            ("thaw://set?value=true", "set"),
            ("thaw://toggle", "toggle"),
        ])
        func malformed(uri: String, host: String) throws {
            #expect(try parse(uri).route == .malformed(host: host))
        }

        @Test("Only settings routes pass through the gate", arguments: [
            ("thaw://set", true),
            ("thaw://authorize", true),
            ("thaw://toggle-hidden", false),
            ("thaw://bogus", false),
        ])
        func requiresAuthorization(uri: String, expected: Bool) throws {
            #expect(try parse(uri).requiresAuthorization == expected)
        }

        @Test("bundleId override is captured, empty is ignored", arguments: [
            ("thaw://set?key=a&value=b&bundleId=com.example", "com.example"),
            ("thaw://set?key=a&value=b&bundleId=", nil),
            ("thaw://set?key=a&value=b", nil),
        ])
        func bundleIdOverride(uri: String, expected: String?) throws {
            #expect(try parse(uri).bundleIdOverride == expected)
        }
    }

    /// The parser is total: any URL yields a request and nothing traps.
    @Test("Parsing is total over awkward input", arguments: [
        "thaw://set?key=a&value=b&key=c",
        "thaw://set?key=%00&value=%FF",
        "thaw://get?callback=javascript:alert(1)",
        "thaw://toggle?key=" + String(repeating: "x", count: 8192),
        "thaw://set?=&=&=",
        "thaw://%20",
        "thaw://get?key=a#fragment",
    ])
    func parsingIsTotal(uri: String) {
        guard let url = URL(string: uri) else { return }
        _ = SettingsURIParser.parse(url)
    }
}
