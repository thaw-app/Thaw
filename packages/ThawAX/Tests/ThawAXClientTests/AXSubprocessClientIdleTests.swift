//
//  AXSubprocessClientIdleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawAXClient
@testable import ThawAXCore

@Suite("AXSubprocessClient idle lifecycle", .timeLimit(.minutes(1)))
struct AXSubprocessClientIdleTests {
    @Test
    func `idle helper shuts down cleanly and relaunches on demand`() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "ThawAXClientIdleTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let templateData = try AXWire.encode(
            AXReplyFrame(id: 0, outcome: .reply(.hitTest(nil, accessibilityTrusted: false)))
        )
        let templateLiteral = try #require(String(data: templateData, encoding: .utf8))

        let scriptURL = dir.appending(path: "mock-ax-helper.py", directoryHint: .notDirectory)
        let script = """
        #!/usr/bin/python3
        import json, struct, sys

        template = json.loads(\(String(reflecting: templateLiteral)))

        while True:
            hdr = sys.stdin.buffer.read(4)
            if len(hdr) < 4:
                break
            (size,) = struct.unpack('>I', hdr)
            payload = sys.stdin.buffer.read(size)
            if len(payload) < size:
                break
            req = json.loads(payload.decode('utf-8'))
            reply = dict(template)
            reply['id'] = req['id']
            out = json.dumps(reply).encode('utf-8')
            sys.stdout.buffer.write(struct.pack('>I', len(out)) + out)
            sys.stdout.buffer.flush()
        """
        try Data(script.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let client = AXSubprocessClient(
            configuration: AXSubprocessClient.Configuration(
                helperURL: scriptURL,
                replyTimeoutSeconds: 5,
                idleTimeoutSeconds: 0.25
            )
        )
        defer { client.stop() }

        #expect(!client.isHelperRunning)

        let first = try await client.send(.hitTest(x: 10, y: 10))
        #expect(first == .hitTest(nil, accessibilityTrusted: false))
        #expect(client.isHelperRunning)

        // Wait past idleTimeoutSeconds (0.25s) so the client terminates the idle helper.
        for _ in 0 ..< 40 where client.isHelperRunning {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!client.isHelperRunning)
        #expect(client.lastExitDescription == nil)
        #expect(!client.hasAbandonedHelper)

        // Subsequent request lazily relaunches the helper without error.
        let second = try await client.send(.hitTest(x: 20, y: 10))
        #expect(second == .hitTest(nil, accessibilityTrusted: false))
        #expect(client.isHelperRunning)
    }
}
