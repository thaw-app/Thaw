//
//  InvocationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing

@Suite("thawctl process invocation")
struct InvocationTests {
    private final class TestBundle: NSObject {}

    /// Runs only help or invalid invocations, which must exit before opening a thaw:// URL.
    private func run(_ arguments: [String]) throws -> (status: Int32, output: String, error: String) {
        let executable = Bundle(for: TestBundle.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("thawctl-cli")
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            try #require(String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)),
            try #require(String(bytes: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
        )
    }

    /// An explicit help request is successful and writes its usage text to standard output.
    @Test("Explicit help succeeds", arguments: ["--help", "-h"])
    func helpSucceeds(argument: String) throws {
        let result = try run([argument])
        #expect(result.status == 0)
        #expect(result.output.contains("Usage: thawctl"))
        #expect(result.error.isEmpty)
    }

    /// Missing or invalid commands remain usage errors on standard error.
    @Test("Invalid invocations fail", arguments: [[], ["--unknown"], ["frobnicate"]])
    func invalidInvocations(arguments: [String]) throws {
        let result = try run(arguments)
        #expect(result.status == 64)
        #expect(result.output.isEmpty)
        #expect(result.error.contains("Usage: thawctl"))
    }
}
