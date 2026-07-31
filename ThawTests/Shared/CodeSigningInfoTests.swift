//
//  CodeSigningInfoTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers `CodeSigningInfo.processTeamIdentifier`, the value both the XPC
/// service's `Listener` and the app's `MenuBarItemServiceConnection` consult
/// to decide whether a same-team peer requirement can ever be satisfied.
///
/// The concrete identifier depends on how the binary under test was signed —
/// a Developer ID build reports a team, an ad-hoc CI build reports `nil` —
/// so the assertions cover the contract that holds either way: the lookup
/// must not trap, must be stable across reads, and must never produce an
/// empty or malformed team string.
@Suite("Process code-signing identity")
struct CodeSigningInfoTests {
    @Test("Resolving the team identifier does not trap")
    func lookupSucceeds() {
        // The whole chain is SecCode C API with several failure points, each
        // of which must degrade to nil rather than crash.
        _ = CodeSigningInfo.processTeamIdentifier
    }

    @Test("The team identifier is resolved once and stays stable")
    func valueIsStableAcrossReads() {
        // Callers read this on every connection attempt, so a value that
        // changed between reads would make peer validation nondeterministic.
        let first = CodeSigningInfo.processTeamIdentifier

        #expect(CodeSigningInfo.processTeamIdentifier == first)
        #expect(CodeSigningInfo.processTeamIdentifier == first)
    }

    @Test("A resolved team identifier is never empty or malformed")
    func resolvedIdentifierIsWellFormed() {
        guard let team = CodeSigningInfo.processTeamIdentifier else {
            // Ad-hoc signed (the CI case). Absence is a supported outcome:
            // it tells callers the same-team requirement is unsatisfiable.
            return
        }

        #expect(!team.isEmpty)
        // Apple team identifiers are uppercase alphanumeric. An empty or
        // punctuation-bearing string would mean we read the wrong key.
        #expect(team.allSatisfy { $0.isUppercase || $0.isNumber })
    }
}
