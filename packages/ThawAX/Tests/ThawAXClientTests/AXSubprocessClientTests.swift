//
//  AXSubprocessClientTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawAXClient
import ThawAXCore

struct AXSubprocessClientTests {
    /// A helper that notes each launch in a log and never replies, so every
    /// request to it times out. It keeps its output open, as a wedged helper
    /// does; a closed output would read as the helper exiting.
    private struct SilentHelper {
        let directory: URL
        let executable: URL
        let launchLog: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AXSubprocessClientTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            executable = directory.appendingPathComponent("silent-helper")
            launchLog = directory.appendingPathComponent("launches")
            let script = """
            #!/bin/sh
            echo launch >> '\(launchLog.path)'
            exec sleep 600
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }

        var launches: Int {
            let text = (try? String(contentsOf: launchLog, encoding: .utf8)) ?? ""
            return text.split(separator: "\n").count
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test
    func `a replaced helper gets a fresh run of timeouts before it is replaced again`() async throws {
        let helper = try SilentHelper()
        defer { helper.remove() }
        let client = AXSubprocessClient(configuration: .init(helperURL: helper.executable))
        defer { client.stop() }

        // Three timeouts in a row replace the first helper. The fourth and
        // fifth go to its replacement, which has timed out only twice.
        for _ in 0 ..< 5 {
            await #expect(throws: AXWire.WireError.timedOut) {
                _ = try await client.send(.hitTest(x: 0, y: 0), timeoutSeconds: 0.05)
            }
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(helper.launches == 2)
    }
}
