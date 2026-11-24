//
//  CodeSignatureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Security
import Testing
@testable import Thaw

@Suite("Code signature")
struct CodeSignatureTests {
    private let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")

    @Test("An app that isn't there has no signature to read")
    func missingAppFails() {
        #expect(throws: CodeSignature.Failure.self) {
            try CodeSignature(appAt: URL(fileURLWithPath: "/nonexistent/Thaw Test.app"))
        }
    }

    @Test("Apple's own app passes the plain and the strict check, and names no team")
    func appleAppIsValid() throws {
        let signature = try CodeSignature(appAt: calculator)
        #expect(signature.isValid())
        #expect(signature.isValid(flags: SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)))
        let info = try signature.signingInformation()
        #expect(info[kSecCodeInfoIdentifier as String] as? String == "com.apple.calculator")
        #expect(CodeSignature.teamIdentifier(in: info) == nil)
    }

    @Test("A file that was never signed is not valid and names no team")
    func unsignedFileIsInvalid() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("unsigned".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let signature = try CodeSignature(appAt: file)
        #expect(!signature.isValid())
        #expect(try CodeSignature.teamIdentifier(in: signature.signingInformation()) == nil)
    }

    @Test("An empty team counts as no team", arguments: [
        ([kSecCodeInfoTeamIdentifier as String: "TEAM123456"], "TEAM123456"),
        ([kSecCodeInfoTeamIdentifier as String: ""], nil),
        ([:], nil),
    ] as [([String: String], String?)])
    func teamIsRead(info: [String: String], team: String?) {
        #expect(CodeSignature.teamIdentifier(in: info) == team)
    }

    @Test("The team requirement names an Apple-issued certificate for that team")
    func teamRequirementIsAppleAnchored() throws {
        let text = try #require(CodeSignature.anchoredTeamRequirement("TEAM123456"))
        #expect(text == #"anchor apple generic and certificate leaf[subject.OU] = "TEAM123456""#)
        var requirement: SecRequirement?
        #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess)
    }

    @Test("A team that isn't ten letters and digits gets no requirement", arguments: [
        "", "TEAM12345", "team123456", #"TEAM12345" or anchor apple"#, "TEAM123456X",
    ])
    func malformedTeamHasNoRequirement(team: String) {
        #expect(CodeSignature.anchoredTeamRequirement(team) == nil)
    }

    @Test("Apple's own code is anchored to no developer team, and a malformed team is anchored to nothing")
    func appleCodeIsNotATeam() throws {
        let signature = try CodeSignature(appAt: calculator)
        #expect(!signature.isAnchored(toTeam: "ABCDE12345"))
        #expect(!signature.isAnchored(toTeam: "not a team"))
    }
}
