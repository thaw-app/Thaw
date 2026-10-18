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
        let gate = try Self.body(of: "handleSettingsURL", in: lines)
        let dispatch = try Self.body(of: "dispatchAuthorizedRoute", in: lines)

        // The gate has to be consulted before the routes are dispatched, not after.
        let gateIndex = try #require(
            gate.firstIndex { $0.contains("SettingsURIHandler.isWhitelisted") },
            "handleSettingsURL no longer consults the whitelist"
        )
        let dispatchIndex = try #require(
            gate.firstIndex { $0.contains("dispatchAuthorizedRoute(request.route, sender: identity)") },
            "handleSettingsURL no longer dispatches with the identified sender"
        )
        #expect(gateIndex < dispatchIndex, "The whitelist check must run before the action is dispatched")

        // The gate is the only way into the dispatch.
        let dispatchCalls = lines.filter { $0.contains("dispatchAuthorizedRoute(") && !$0.contains("func dispatchAuthorizedRoute(") }
        #expect(dispatchCalls.count == 1, "Expected one dispatchAuthorizedRoute call, found \(dispatchCalls.count)")

        // Each mutating action must be handed the identity the gate approved, or its bundle id.
        // A call passing anything else is a route around the check.
        let actions = [
            "handleSetRequest", "handleToggleRequest", "handleRevealItemRequest",
            "handleLauncherRequest", "handleProxyPressRequest", "handleDumpItemsRequest",
        ]
        for action in actions {
            let calls = dispatch.filter { $0.contains("\(action)(") && !$0.contains("func \(action)(") }
            #expect(calls.count == 1, "Expected exactly one \(action) call in dispatchAuthorizedRoute, found \(calls.count)")
            for call in calls {
                #expect(
                    call.contains("sender: identity"),
                    "\(action) is dispatched with an unverified sender: \(call.trimmingCharacters(in: .whitespaces))"
                )
            }
        }
    }

    @Test("The only request served without approval is the version read")
    func theOnlyUnauthenticatedRouteIsVersion() throws {
        let lines = try Self.sourceLines("Thaw/App/AppDelegate.swift")
        let gate = try Self.body(of: "handleSettingsURL", in: lines)
        let dispatch = try Self.body(of: "dispatchAuthorizedRoute", in: lines)

        // Only the public app-version read may use sender: nil; any other route would bypass authentication.
        #expect(!dispatch.contains { $0.contains("sender: nil") }, "An approved route is dispatched without its sender")
        let anonymous = gate.enumerated().filter { $0.element.contains("sender: nil") }
        #expect(anonymous.count == 1, "Expected one unauthenticated route, found \(anonymous.count)")

        for (offset, line) in anonymous {
            #expect(line.contains("handleGetRequest"), "An unauthenticated route may only read: \(line)")
            let preceding = gate.dropFirst(max(0, offset - 3)).prefix(4)
            #expect(
                preceding.contains { $0.contains("request.isVersionRead") },
                "The unauthenticated route is no longer restricted to the version key"
            )
        }
    }

    @Test("Every launcher operation is routed through the whitelist gate")
    func launcherOperationsAreGated() throws {
        let lines = try Self.sourceLines("Thaw/App/AppDelegate.swift")
        let router = try Self.body(of: "handleURL", in: lines)
        let dispatch = try Self.body(of: "dispatchAuthorizedRoute", in: lines)
        let handler = try Self.body(of: "handleLauncherRequest", in: lines)

        // A route that does not require authorization falls through to the ungated switch;
        // one missing from the dispatch passes the gate and then does nothing.
        #expect(router.contains { $0.contains("if request.requiresAuthorization {") })
        for operation in LauncherURIOperation.allCases {
            let request = try SettingsURIParser.parse(#require(URL(string: "thaw://\(operation.rawValue)")))
            #expect(request.requiresAuthorization, "\(operation.rawValue) is not routed to handleSettingsURL")
            guard case let .launcher(parsed, _) = request.route else {
                Issue.record("\(operation.rawValue) is not parsed as a launcher operation")
                continue
            }
            #expect(parsed == operation)
        }
        #expect(dispatch.contains { $0.contains("case let .launcher(") }, "Launcher operations are not dispatched after the whitelist check")

        // handleLauncherRequest is the only caller, so nothing else can reach the operations.
        let callers = lines.filter { $0.contains("SettingsURIHandler.handleLauncherRequest(") }
        #expect(callers.count == 1, "Expected one handleLauncherRequest call, found \(callers.count)")
        #expect(handler.contains { $0.contains("SettingsURIHandler.handleLauncherRequest(") })
    }

    @Test("Every gated route is dispatched after the whitelist check and never in the ungated switch")
    func everyGatedRouteIsDispatchedBehindTheGate() throws {
        let lines = try Self.sourceLines("Thaw/App/AppDelegate.swift")
        let router = try Self.body(of: "handleURL", in: lines)
        let dispatch = try Self.body(of: "dispatchAuthorizedRoute", in: lines)

        let gatedCases = [".set(", ".toggle(", ".get(", ".revealItem(", ".releaseItem(", ".launcher(", ".proxyPress(", ".toggleThawBar:", ".dumpItems("]
        for gatedCase in gatedCases {
            #expect(
                dispatch.contains { $0.contains("case") && $0.contains(gatedCase) },
                "\(gatedCase) passes the gate and then does nothing"
            )
            #expect(
                !router.contains { $0.contains("case") && $0.contains(gatedCase) },
                "\(gatedCase) also has an ungated branch in handleURL"
            )
        }
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
