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

    /// A helper that acknowledges each request with a fast reply,
    /// logs launches, and exits when stdin closes.
    private struct EchoHelper {
        let directory: URL
        let executable: URL
        let launchLog: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AXSubprocessClientTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            executable = directory.appendingPathComponent("echo-helper")
            launchLog = directory.appendingPathComponent("launches")
            let script = """
            #!/usr/bin/env python3
            import json, struct, sys
            with open('\(launchLog.path)', 'a') as f:
                f.write('launch\\n')
            while True:
                header = sys.stdin.buffer.read(4)
                if not header or len(header) < 4:
                    break
                length = struct.unpack('>I', header)[0]
                payload = sys.stdin.buffer.read(length)
                if not payload:
                    break
                req = json.loads(payload.decode('utf-8'))
                req_id = req.get('id', 0)
                reply = {
                    'id': req_id,
                    'outcome': {
                        'reply': {
                            '_0': {
                                'press': {
                                    'accessibilityTrusted': True,
                                    'pressed': True
                                }
                            }
                        }
                    }
                }
                reply_bytes = json.dumps(reply).encode('utf-8')
                sys.stdout.buffer.write(struct.pack('>I', len(reply_bytes)))
                sys.stdout.buffer.write(reply_bytes)
                sys.stdout.buffer.flush()
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
                _ = try await client.send(.hitTest(x: 0, y: 0), timeoutSeconds: 0.2)
            }
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(helper.launches == 2)
    }

    @Test
    func `an idle helper shuts down cleanly and relaunches on demand`() async throws {
        let helper = try EchoHelper()
        defer { helper.remove() }
        let client = AXSubprocessClient(configuration: .init(
            helperURL: helper.executable,
            idleTimeoutSeconds: 0.2
        ))
        defer { client.stop() }

        #expect(!client.isHelperRunning)

        // First request starts the helper.
        let firstReply = try await client.send(.pressStatusItem(pid: 1, targetX: 0, targetY: 0, tolerance: 10))
        #expect(firstReply == .press(pressed: true, accessibilityTrusted: true))
        #expect(client.isHelperRunning)
        #expect(helper.launches == 1)

        // Wait for idle shutdown.
        try await Task.sleep(for: .milliseconds(350))
        #expect(!client.isHelperRunning)

        // Next request relaunches the helper. Measure relaunch duration.
        let clock = ContinuousClock()
        var secondReply: AXHelperReply?
        let elapsed = try await clock.measure {
            secondReply = try await client.send(.pressStatusItem(pid: 1, targetX: 0, targetY: 0, tolerance: 10))
        }
        #expect(secondReply == .press(pressed: true, accessibilityTrusted: true))
        #expect(client.isHelperRunning)
        #expect(helper.launches == 2)
        print("AX helper relaunch latency after idle shutdown: \(elapsed)")
    }
}
