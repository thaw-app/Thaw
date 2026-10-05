//
//  SettingsURIDispatchInventoryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Inspect source to enforce the whitelist boundary without a live AppDelegate, sender Apple Event or modal alert.
/// Missing declarations must fail so renames cannot silently disable enforcement; gate behaviour lives in SettingsURIWhitelistTests.
@Suite("Settings URI dispatch inventory")
struct SettingsURIDispatchInventoryTests {
    private static var repositoryRoot: URL {
        // ThawTests/System/<this file> -> repository root
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
            "\(functionName) no longer exists; the boundary it guarded needs a new test"
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

    /// Indices of every line that sits inside a #if DEBUG region.
    private static func debugGatedLineNumbers(in lines: [String]) -> Set<Int> {
        var gated: Set<Int> = []
        var stack: [Bool] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") {
                stack.append(trimmed == "#if DEBUG")
                continue
            }
            if trimmed.hasPrefix("#elseif") || trimmed == "#else" {
                // The other arm of a DEBUG condition is a release arm.
                if !stack.isEmpty {
                    stack[stack.count - 1] = false
                }
                continue
            }
            if trimmed == "#endif" {
                if !stack.isEmpty {
                    stack.removeLast()
                }
                continue
            }
            if stack.contains(true) {
                gated.insert(index)
            }
        }
        return gated
    }

    @Test("The manual sender override stays out of release builds")
    func manualBundleOverrideIsDebugOnly() throws {
        // Terminal testing can override sender identity through extractManualBundleId; this bypass must stay debug-only.
        let lines = try Self.sourceLines("Thaw/App/AppDelegate.swift")
        let gated = Self.debugGatedLineNumbers(in: lines)

        let mentions = lines.indices.filter { lines[$0].contains("extractManualBundleId") }
        try #require(
            !mentions.isEmpty,
            "extractManualBundleId is gone; if the override was removed, delete this test with it"
        )

        for index in mentions {
            #expect(
                gated.contains(index),
                "AppDelegate.swift:\(index + 1) uses extractManualBundleId outside #if DEBUG: \(lines[index].trimmingCharacters(in: .whitespaces))"
            )
        }
    }

    @Test("Every settings action is dispatched with the authorized sender")
    func everySettingsActionCarriesTheApprovedSender() throws {
        let lines = try Self.sourceLines("Thaw/App/AppDelegate.swift")
        let dispatch = try Self.body(of: "handleSettingsURL", in: lines)

        // The gate has to be consulted before the routing switch, not after.
        let gateIndex = try #require(
            dispatch.firstIndex { $0.contains("SettingsURIHandler.isWhitelisted") },
            "handleSettingsURL no longer consults the whitelist"
        )
        let switchIndex = try #require(
            dispatch.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "switch host {" },
            "handleSettingsURL no longer routes on the URL host"
        )
        #expect(gateIndex < switchIndex, "The whitelist check must run before the action is dispatched")

        // Each mutating action must be handed the bundle id the gate approved.
        // A call passing anything else is a route around the check.
        for action in ["handleSetURL", "handleToggleURL", "handleRevealItemURL", "handleLauncherURL"] {
            let calls = dispatch.filter { $0.contains("\(action)(") && !$0.contains("func \(action)(") }
            #expect(calls.count == 1, "Expected exactly one \(action) call in handleSettingsURL, found \(calls.count)")
            for call in calls {
                #expect(
                    call.contains("sender: effectiveBundleId"),
                    "\(action) is dispatched with an unverified sender: \(call.trimmingCharacters(in: .whitespaces))"
                )
            }
        }
    }

    @Test("The only request served without approval is the version read")
    func theOnlyUnauthenticatedRouteIsVersion() throws {
        let lines = try Self.sourceLines("Thaw/App/AppDelegate.swift")
        let dispatch = try Self.body(of: "handleSettingsURL", in: lines)

        // Only the public app-version read may use sender: nil; any other route would bypass authentication.
        let anonymous = dispatch.enumerated().filter { $0.element.contains("sender: nil") }
        #expect(anonymous.count == 1, "Expected one unauthenticated route, found \(anonymous.count)")

        for (offset, line) in anonymous {
            #expect(line.contains("handleGetURL"), "An unauthenticated route may only read: \(line)")
            let preceding = dispatch.dropFirst(max(0, offset - 8)).prefix(9)
            #expect(
                preceding.contains { $0.contains("\"version\"") },
                "The unauthenticated route is no longer restricted to the version key"
            )
        }
    }

    @Test("Every launcher operation is routed through the whitelist gate")
    func launcherOperationsAreGated() throws {
        let lines = try Self.sourceLines("Thaw/App/AppDelegate.swift")
        let router = try Self.body(of: "handleURL", in: lines)
        let dispatch = try Self.body(of: "handleSettingsURL", in: lines)
        let handler = try Self.body(of: "handleLauncherURL", in: lines)

        // A host missing from the first list falls through to the ungated switch;
        // one missing from the second passes the gate and then does nothing.
        for operation in LauncherURIOperation.allCases {
            let literal = "\"\(operation.rawValue)\""
            #expect(
                router.contains { $0.contains(literal) },
                "\(operation.rawValue) is not routed to handleSettingsURL"
            )
            #expect(
                dispatch.contains { $0.contains(literal) },
                "\(operation.rawValue) is not dispatched after the whitelist check"
            )
        }

        // handleLauncherURL is the only caller, so nothing else can reach the operations.
        let callers = lines.filter { $0.contains("SettingsURIHandler.handleLauncherRequest(") }
        #expect(callers.count == 1, "Expected one handleLauncherRequest call, found \(callers.count)")
        #expect(handler.contains { $0.contains("SettingsURIHandler.handleLauncherRequest(") })
    }

    @Test("Callback URLs still refuse the schemes that can run code or read files")
    func callbackSchemeBlocklistIsIntact() throws {
        // Callback responses open URLs as Thaw; scheme restrictions prevent arbitrary file or code handlers.
        let lines = try Self.sourceLines("Thaw/System/SettingsURIHandler.swift")
        let declaration = try #require(
            lines.first { $0.contains("blockedCallbackSchemes") && $0.contains("=") },
            "blockedCallbackSchemes is gone; callback URLs are no longer filtered"
        )

        for scheme in ["file", "javascript", "data", "about", "blob"] {
            #expect(declaration.contains("\"\(scheme)\""), "\(scheme): was dropped from the callback blocklist")
        }

        #expect(
            lines.contains { $0.contains("hasPrefix(\"x-apple-\")") },
            "The x-apple- prefix guard is gone; a callback could target a system handler"
        )
    }
}
