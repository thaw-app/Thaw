//
//  ParsingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import thawctl_cli

@Suite("thawctl argument parsing")
struct ParsingTests {
    private func query(_ args: [String]) throws -> [String: String] {
        let parsed = try #require(try parse(args))
        return Dictionary(uniqueKeysWithValues: parsed.query.map { ($0.name, $0.value ?? "") })
    }

    @Test("set takes the documented key=value form")
    func setShorthand() throws {
        let parsed = try #require(try parse(["set", "showOnHover=true"]))
        #expect(parsed.host == "set")
        #expect(try query(["set", "showOnHover=true"]) == ["key": "showOnHover", "value": "true"])
    }

    @Test("A value may itself contain an equals sign")
    func valueWithEquals() throws {
        #expect(try query(["set", "hotkey=cmd=1"]) == ["key": "hotkey", "value": "cmd=1"])
    }

    @Test("The explicit key= and value= form still works, with a display")
    func explicitForm() throws {
        #expect(try query(["set", "key=showOnHover", "value=false", "--display", "UUID-1"])
            == ["key": "showOnHover", "value": "false", "display": "UUID-1"])
    }

    @Test("set refuses a second pair and a missing value")
    func setRefusals() {
        #expect(throws: ParseError.invalidPair("b=2")) { try parse(["set", "a=1", "b=2"]) }
        #expect(throws: ParseError.missingValue(command: "set", param: "value")) { try parse(["set", "key=showOnHover"]) }
    }

    @Test("A one-value command takes its value positionally, and nothing else takes an unknown pair")
    func positional() throws {
        #expect(try query(["toggle-setting", "showOnHover"]) == ["key": "showOnHover"])
        #expect(throws: ParseError.invalidPair("showOnHover=true")) { try parse(["toggle-setting", "showOnHover=true"]) }
    }

    @Test("get is refused up front, since thawctl can't receive Thaw's reply")
    func getRefused() {
        #expect(throws: ParseError.noReplyChannel) { try parse(["get", "showOnHover"]) }
        #expect(!Command.all.contains { $0.name == "get" })
    }

    @Test("Help and unknown commands")
    func helpAndUnknown() throws {
        #expect(try parse([]) == nil)
        #expect(try parse(["--help"]) == nil)
        #expect(throws: ParseError.unknownCommand("frobnicate")) { try parse(["frobnicate"]) }
    }
}
