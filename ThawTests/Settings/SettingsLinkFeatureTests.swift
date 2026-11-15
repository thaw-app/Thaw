//
//  SettingsLinkFeatureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Observation
import Testing
@testable import Thaw

/// Live state a page's feature reads, as a page's model would hold it.
@MainActor
@Observable
private final class LiveState {
    var count = 0
}

/// What a page's features were asked to do, on either side of the link.
@MainActor
private final class FeatureCalls {
    var commands = [String]()
    var reloads = 0
    var storeReads = [String]()
    var statuses = [String]()
    var ends = 0
}

/// The pipes between a host and a stand-in for the settings process, or between a session and a stand-in for the app.
@MainActor
private final class LinkPipes {
    let toPeer = Pipe()
    let fromPeer = Pipe()
    private(set) var received = [SettingsLinkMessage]()
    private(set) var end: SettingsLinkEndpoint?

    /// What reached the stand-in, leaving out the notices any defaults write in the test process sends.
    var messages: [SettingsLinkMessage] {
        received.filter { $0 != .settingsChanged }
    }

    /// The stand-in's end: it reads what the tested end writes, and writes what the tested end reads.
    func connectPeer() {
        end = SettingsLinkEndpoint(
            input: toPeer.fileHandleForReading,
            output: fromPeer.fileHandleForWriting,
            onMessage: { [weak self] in self?.received.append($0) }
        )
    }

    func close() {
        end?.close()
    }
}

@Suite("Settings process link features")
@MainActor
final class SettingsLinkFeatureTests {
    private let calls = FeatureCalls()
    private let live = LiveState()
    private let pipes = LinkPipes()
    /// Ends the stand-in settings process, as the system does when the real one exits.
    private var endProcess: (@Sendable (Int32) -> Void)?

    isolated deinit {
        pipes.close()
    }

    private func appFeature() -> SettingsAppFeature {
        let calls = calls
        let live = live
        return SettingsAppFeature(
            statuses: ["count": { SettingsLinkPayload.encode(live.count / 2) }],
            commands: ["bump": { payload in
                calls.commands.append("bump \(SettingsLinkPayload.decode(Int.self, from: payload) ?? -1)")
            }],
            reload: { calls.reloads += 1 },
            stores: ["profiles": { calls.storeReads.append("profiles") }],
            processEnded: { calls.ends += 1 }
        )
    }

    /// A host whose settings process is the pipes' stand-in.
    private func startedHost() -> SettingsProcessHost {
        let pipes = pipes
        let host = SettingsProcessHost(
            app: SettingsProcessHost.AppSide(
                reloadSettings: {},
                openInApp: { _ in },
                pageChanged: { _ in },
                checkForUpdates: {},
                quit: {},
                updatesState: { .updatesState(canCheck: false, lastCheck: nil) },
                features: [appFeature()]
            ),
            isEnabled: { true },
            launch: { [weak self] _, onEnd in
                self?.endProcess = onEnd
                pipes.connectPeer()
                return SettingsProcessHost.Child(
                    processIdentifier: -1,
                    isRunning: { true },
                    fromChild: pipes.fromPeer.fileHandleForReading,
                    toChild: pipes.toPeer.fileHandleForWriting
                )
            }
        )
        #expect(host.show(pane: "General", simpleMode: false))
        return host
    }

    private func counts() -> [Int] {
        pipes.messages.compactMap { message in
            guard case let .status(topic: "count", payload) = message else { return nil }
            return SettingsLinkPayload.decode(Int.self, from: payload)
        }
    }

    @Test("A page's live state is sent when the process starts and when it changes, and not twice the same")
    func statusFollowsLiveState() async {
        let host = startedHost()
        #expect(await settingsLinkWait { counts() == [0] })
        live.count = 1
        live.count = 2
        #expect(await settingsLinkWait { counts() == [0, 1] }, "A change that leaves the payload as it was is not sent")
        host.send(status: "count", payload: Data("7".utf8))
        #expect(await settingsLinkWait { counts() == [0, 1, 7] })
    }

    @Test("The app runs a page's command, reads its store again and reloads after a defaults write")
    func appRunsWhatThePageAsks() async {
        let host = startedHost()
        let remote = SettingsRemote { [pipes] in pipes.end?.send($0) }
        remote.perform("bump", 3)
        remote.perform("nobody runs this")
        remote.saved(store: "profiles")
        remote.saved(store: "another page's store")
        pipes.end?.send(.settingsChanged)
        #expect(await settingsLinkWait { calls.commands == ["bump 3"] && calls.storeReads == ["profiles"] && calls.reloads > 0 })
        host.saved(store: "profiles")
        #expect(await settingsLinkWait { pipes.messages.contains(.storeChanged(store: "profiles")) })
    }

    @Test("A page is told when the settings process has ended")
    func pageHearsTheProcessEnd() async {
        let host = startedHost()
        #expect(calls.ends == 0)
        endProcess?(0)
        #expect(await settingsLinkWait { calls.ends == 1 })
        #expect(!host.isLinked)
    }

    @Test("The settings process hands a page the app's state, reads its store again and reloads after a defaults write")
    func settingsProcessTakesWhatTheAppSends() async {
        let calls = calls
        let session = SettingsProcessSession(
            navigationState: AppNavigationState(),
            side: SettingsProcessSession.ProcessSide(
                reloadSettings: {},
                showSettings: {},
                updatesStateChanged: { _, _ in },
                terminate: {},
                features: [SettingsChildFeature(
                    statuses: ["count": { calls.statuses.append(String(decoding: $0, as: UTF8.self)) }],
                    reload: { calls.reloads += 1 },
                    stores: ["profiles": { calls.storeReads.append("profiles") }]
                )]
            )
        )
        // Here the pipes' stand-in is the app, so the session reads what it writes.
        session.start(input: pipes.toPeer.fileHandleForReading, output: pipes.fromPeer.fileHandleForWriting, onClose: {})
        let app = SettingsLinkEndpoint(
            input: pipes.fromPeer.fileHandleForReading,
            output: pipes.toPeer.fileHandleForWriting,
            onMessage: { _ in }
        )
        defer { app.close() }
        app.send(.status(topic: "count", payload: Data("4".utf8)))
        app.send(.status(topic: "another page's topic", payload: Data("5".utf8)))
        app.send(.storeChanged(store: "profiles"))
        app.send(.command(name: "bump", payload: Data()))
        app.send(.settingsChanged)
        #expect(await settingsLinkWait { calls.statuses == ["4"] && calls.storeReads == ["profiles"] && calls.reloads > 0 })
        #expect(calls.commands.isEmpty, "Commands are for the app")
    }

    @Test("A payload survives being encoded and decoded, and one of another type decodes to nothing")
    func payloads() throws {
        let data = try #require(SettingsLinkPayload.encode(["a": 1]))
        #expect(SettingsLinkPayload.decode([String: Int].self, from: data) == ["a": 1])
        #expect(SettingsLinkPayload.decode(Int.self, from: data) == nil)
    }
}
