//
//  CodeSigningInfoTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("Process code-signing identity")
struct CodeSigningInfoTests {
    @Test("A resolved team identifier is stable and well formed; an ad-hoc build has none")
    func teamIdentifier() {
        let team = CodeSigningInfo.processTeamIdentifier
        #expect(CodeSigningInfo.processTeamIdentifier == team)
        if let team {
            #expect(!team.isEmpty)
            #expect(team.allSatisfy { $0.isUppercase || $0.isNumber })
        }
    }
}
