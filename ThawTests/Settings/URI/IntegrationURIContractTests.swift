//
//  IntegrationURIContractTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

// MARK: - Raycast

//
// Source: github.com/thaw-app/raycast-extension
//   - src/data/index.ts — DIRECT_ACTIONS (6) and SETTINGS_ACTIONS (4)
//   - src/utils/openUrl.ts — buildThawUrl() composes `thaw://<action>?<query>`
//
// buildThawUrl drops falsy query values, so a parameter is either present with
// a non-empty value or absent entirely. Keys are compile-time constants in the
// action table, so a bare `thaw://toggle` is unreachable from Raycast.

/// Every URL the Raycast extension is able to emit.
private let raycastURIs: [String] = [
    "thaw://toggle-hidden",
    "thaw://toggle-always-hidden",
    "thaw://search",
    "thaw://toggle-thawbar",
    "thaw://toggle-application-menus",
    "thaw://open-settings",
    "thaw://authorize",
    "thaw://toggle?key=autoRehide",
    "thaw://toggle?key=showOnHover",
    "thaw://toggle?key=hideApplicationMenus",
]

// MARK: - Droppy

//
// Source: /Applications/Droppy.app — literals recovered from the shipped
// binary, since Droppy is closed source:
//   "thaw://get?key=all&callback="   (callback value interpolated)
//   "thaw://toggle?key="             (key value interpolated)
//   "droppy://thaw-response"         (its callback scheme)
//
// Droppy emits no `thaw://set` at all. Its onboarding is a text instruction
// telling the user to enable the Settings URI scheme and approve Droppy when
// Thaw prompts — it does not probe with a parameterless URL to trigger the
// dialog.

/// Every URL shape Droppy is able to emit.
private let droppyURIs: [String] = [
    "thaw://get?key=all&callback=droppy://thaw-response",
    "thaw://get?key=all&callback=droppy%3A%2F%2Fthaw-response",
    "thaw://get?key=all&callback=droppy://thaw-response&requestId=7",
    "thaw://get?key=all&callback=droppy://thaw-response&broadcast=true",
    "thaw://toggle?key=autoRehide",
    "thaw://toggle?key=useIceBar",
]

private func parse(_ string: String) throws -> SettingsURIRequest {
    let url = try #require(URL(string: string), "Could not build a URL from \(string)")
    return SettingsURIParser.parse(url)
}

@Suite("Integration URI contract")
struct IntegrationURIContractTests {
    /// The Option B regression guard.
    ///
    /// Malformed routes are rejected before the authorization gate, so if a
    /// real integration URL ever parsed as malformed it would silently stop
    /// working — no prompt, no settings change.
    @Test("No shipped integration URL is malformed", arguments: raycastURIs + droppyURIs)
    func integrationURIsAreNeverMalformed(uri: String) throws {
        let route = try parse(uri).route
        if case let .malformed(host) = route {
            Issue.record("\(uri) parsed as malformed(host: \(host)); this breaks a shipped integration")
        }
    }

    @Suite("Raycast")
    struct Raycast {
        @Test("Direct actions resolve to their action", arguments: [
            ("thaw://toggle-hidden", SettingsURIAction.toggleHidden),
            ("thaw://toggle-always-hidden", .toggleAlwaysHidden),
            ("thaw://search", .search),
            ("thaw://toggle-thawbar", .toggleThawbar),
            ("thaw://toggle-application-menus", .toggleApplicationMenus),
            ("thaw://open-settings", .openSettings),
        ])
        func directActions(uri: String, action: SettingsURIAction) throws {
            #expect(try parse(uri).route == .action(action))
        }

        /// Raycast's onboarding depends on this: it sends `thaw://authorize`
        /// rather than probing with an incomplete settings URL.
        @Test("Authorize command reaches the authorization gate")
        func authorize() throws {
            let request = try parse("thaw://authorize")
            #expect(request.route == .authorize)
            #expect(request.requiresAuthorization)
        }

        @Test("Settings toggles carry their key", arguments: [
            ("thaw://toggle?key=autoRehide", "autoRehide"),
            ("thaw://toggle?key=showOnHover", "showOnHover"),
            ("thaw://toggle?key=hideApplicationMenus", "hideApplicationMenus"),
        ])
        func settingsToggles(uri: String, key: String) throws {
            #expect(try parse(uri).route == .toggle(key: key, displayUUID: nil))
        }

        /// `buildThawUrl` forwards any query pair it is handed, so unknown
        /// parameters must be ignored rather than changing the route.
        /// See src/utils/openUrl.test.ts, which exercises a `label` pair.
        @Test("Unknown query parameters are ignored")
        func unknownParametersIgnored() throws {
            #expect(try parse("thaw://toggle?key=showOnHover&label=Show+on+hover+%26+delay").route
                == .toggle(key: "showOnHover", displayUUID: nil))
        }

        @Test("Raycast never emits a set route", arguments: raycastURIs)
        func neverSends(uri: String) throws {
            if case .set = try parse(uri).route {
                Issue.record("\(uri) parsed as a set route; Raycast has no set action")
            }
        }
    }

    @Suite("Droppy")
    struct Droppy {
        @Test("Snapshot query resolves to a get with its callback", arguments: [
            "thaw://get?key=all&callback=droppy://thaw-response",
            "thaw://get?key=all&callback=droppy%3A%2F%2Fthaw-response",
        ])
        func snapshotQuery(uri: String) throws {
            guard case let .get(key, _, callback, _, _) = try parse(uri).route else {
                Issue.record("\(uri) did not parse as a get route")
                return
            }
            #expect(key == "all")
            #expect(callback == "droppy://thaw-response")
        }

        @Test("Request correlation and broadcast are carried through")
        func requestIdAndBroadcast() throws {
            let uri = "thaw://get?key=all&callback=droppy://thaw-response&requestId=7&broadcast=true"
            guard case let .get(_, _, _, broadcast, requestId) = try parse(uri).route else {
                Issue.record("\(uri) did not parse as a get route")
                return
            }
            #expect(broadcast)
            #expect(requestId == "7")
        }

        /// Droppy interpolates the key into `thaw://toggle?key=`. An empty
        /// field yields a present-but-empty key, which must stay a toggle
        /// route and be rejected later by key validation — not malformed.
        @Test("An empty interpolated key stays a toggle route")
        func emptyInterpolatedKey() throws {
            #expect(try parse("thaw://toggle?key=").route == .toggle(key: "", displayUUID: nil))
        }

        @Test("Droppy never emits a set route", arguments: droppyURIs)
        func neverSends(uri: String) throws {
            if case .set = try parse(uri).route {
                Issue.record("\(uri) parsed as a set route; Droppy sends no set URLs")
            }
        }
    }
}
