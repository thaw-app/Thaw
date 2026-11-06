//
//  RevealCaptureSessionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Reveal capture session", .timeLimit(.minutes(1)))
struct RevealCaptureSessionTests {
    private let first = RevealCaptureSessionTests.makeItem("First", x: 1000, windowID: 101)
    private let second = RevealCaptureSessionTests.makeItem("Second", x: 1100, windowID: 102)

    /// Everything a session did, in order.
    private final class Log {
        var events: [String] = []
        var committed: [[MenuBarItemTag]] = []
        var captured: [Set<MenuBarItemTag>] = []
    }

    private func session(
        _ log: Log,
        reader: CaptureFixture? = nil,
        settledItems: (@MainActor ([MenuBarItem]) async -> RevealCaptureSession.RevealedPairs)? = nil,
        renderSettle: @escaping @MainActor ([MenuBarItem]) async -> Void = { _ in },
        mayReveal: @escaping @MainActor () -> Bool = { true },
        lockedAt: String? = nil,
        admits: Bool = true,
        commits: Bool = true
    ) throws -> RevealCaptureSession {
        let reader = try reader ?? CaptureFixture(hosting: CaptureFixture.barCapture(opaque: false, glyphXs: [1008, 1108]), strip: nil)
        return RevealCaptureSession(
            sources: .init(
                settledItems: settledItems ?? { batch in batch.map { (requested: $0, live: $0) } },
                renderSettle: renderSettle,
                reader: reader,
                cover: { log.events.append("cover") },
                uncover: { log.events.append("uncover") },
                mayReveal: mayReveal
            ),
            displayID: 42,
            reveal: { log.events.append("reveal \($0)") },
            conceal: { log.events.append("conceal \($0)") },
            waitWhileMoving: { log.events.append("wait for moves") },
            isLocked: { step in step == lockedAt },
            cropper: AXBoundsCropper(screenIsLocked: { false }, captureIsAllowed: { false }),
            shouldSkip: { _ in false },
            admit: {
                log.events.append("admit")
                return admits ? CapturePublicationAdmission(layoutGeneration: 0, displayID: 42) : nil
            },
            commit: { pass, revealed, _ in
                log.committed.append(revealed.map(\.requested.tag))
                log.captured.append(Set(pass.captured.keys))
                return commits
            }
        )
    }

    @Test("Each batch waits out moves, is covered before its reveal and uncovered after its conceal")
    func batchesAreCoveredAndHeldForMoves() async throws {
        let log = Log()
        try await session(log).capture([[first], [second]])

        let one = first.uniqueIdentifier
        let two = second.uniqueIdentifier
        #expect(log.events == [
            "wait for moves", "cover", "reveal \(one)", "admit", "conceal \(one)", "uncover",
            "wait for moves", "cover", "reveal \(two)", "admit", "conceal \(two)", "uncover",
        ])
        #expect(log.committed == [[first.tag], [second.tag]])
        #expect(log.captured == [[first.tag], [second.tag]])
    }

    @Test("An item that moves after its first read is settled again and cropped where it ended up")
    func movedItemIsFollowed() async throws {
        let log = Log()
        let stale = Self.makeItem("First", x: 850, windowID: 101)
        var reads = 0
        var settledAt: [[CGFloat]] = []
        try await session(log, settledItems: { batch in
            reads += 1
            return batch.map { (requested: $0, live: reads == 1 ? stale : $0) }
        }, renderSettle: { items in settledAt.append(items.map(\.bounds.minX)) }).capture([[first]])

        #expect(settledAt == [[stale.bounds.minX], [first.bounds.minX]])
        #expect(log.captured == [[first.tag]])
    }

    @Test("The second read asks only for the items that appeared, and a still batch is settled once")
    func secondReadSkipsItemsThatNeverAppeared() async throws {
        let log = Log()
        var asked: [[MenuBarItemTag]] = []
        var settles = 0
        try await session(log, settledItems: { [second] batch in
            asked.append(batch.map(\.tag))
            // Second never draws, like a module that stays switched off.
            return batch.filter { $0.tag != second.tag }.map { (requested: $0, live: $0) }
        }, renderSettle: { _ in settles += 1 }).capture([[first, second]])

        #expect(asked == [[first.tag, second.tag], [first.tag]])
        #expect(settles == 1)
        #expect(log.committed == [[first.tag]])
    }

    @Test("A batch the gate refuses is never revealed")
    func gateIsAskedBeforeEachBatch() async throws {
        let log = Log()
        var asked = 0
        try await session(log, mayReveal: {
            asked += 1
            return asked == 1
        }).capture([[first], [second]])

        #expect(asked == 2)
        #expect(log.events.filter { $0.hasPrefix("reveal") } == ["reveal \(first.uniqueIdentifier)"])
    }

    @Test("A batch that never appears is skipped without a screenshot, and the next one still runs")
    func emptyReadSkipsTheBatch() async throws {
        let log = Log()
        try await session(log, settledItems: { [second] batch in
            batch.filter { $0.tag == second.tag }.map { (requested: $0, live: $0) }
        }).capture([[first], [second]])

        #expect(log.committed == [[second.tag]])
        #expect(log.events.filter { $0 == "admit" }.count == 1)
    }

    @Test("A lock, a refused admission or a refused commit stops the session after concealing", arguments: [
        "capture reveal completed", "settled capture batch", "admission", "commit",
    ])
    func stopsConcealed(at step: String) async throws {
        let log = Log()
        let reader = try CaptureFixture(hosting: CaptureFixture.barCapture(opaque: false, glyphXs: [1008, 1108]), strip: nil)
        try await session(
            log, reader: reader, lockedAt: step, admits: step != "admission", commits: step != "commit"
        ).capture([[first], [second]])

        #expect(log.events.last == "uncover")
        #expect(log.events.filter { $0.hasPrefix("reveal") } == ["reveal \(first.uniqueIdentifier)"])
        #expect(log.events.filter { $0.hasPrefix("conceal") } == ["conceal \(first.uniqueIdentifier)"])
        let tookPixels = step == "commit"
        #expect(await reader.captures.isEmpty != tookPixels)
    }

    @Test("A session locked before its first reveal touches nothing")
    func lockedBeforeRevealDoesNothing() async throws {
        let log = Log()
        try await session(log, lockedAt: "revealing capture batch").capture([[first]])

        #expect(log.events == ["wait for moves"])
    }

    private static func makeItem(_ title: String, x: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.reveal"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 999_995,
            sourcePID: 999_995,
            bounds: CGRect(x: x, y: 4.5, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }
}
