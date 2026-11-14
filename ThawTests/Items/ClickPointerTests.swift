//
//  ClickPointerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Pointer handling around a synthetic click")
struct ClickPointerTests {
    private static let item = CGPoint(x: 1200, y: 12)
    private static let home = CGPoint(x: 400, y: 600)

    private struct Stopped: Error {}

    @MainActor
    private final class PointerLog {
        var events = [String]()

        func pointer(settle: @escaping () -> Void = {}) -> ClickPointer {
            ClickPointer(
                warp: { self.events.append("warp \(Int($0.x)),\(Int($0.y))") },
                hide: { self.events.append("hide") },
                show: { self.events.append("show") },
                settle: settle
            )
        }
    }

    @Test("A click cancelled while the pointer settles posts nothing and puts the pointer back")
    func cancelledDuringSettle() async {
        let log = PointerLog()
        let pointer = log.pointer(settle: { withUnsafeCurrentTask { $0?.cancel() } })
        let task = Task { @MainActor in
            try await MenuBarItemManager.withPointerParked(at: Self.item, restoringTo: Self.home, pointer: pointer) {
                log.events.append("click")
            }
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(log.events == ["warp 1200,12", "hide", "warp 400,600", "show"])
    }

    @Test("A failed click still puts the pointer back")
    func failedClickRestores() async {
        let log = PointerLog()
        await #expect(throws: Stopped.self) {
            try await MenuBarItemManager.withPointerParked(at: Self.item, restoringTo: Self.home, pointer: log.pointer()) {
                log.events.append("click")
                throw Stopped()
            }
        }
        #expect(log.events == ["warp 1200,12", "hide", "click", "warp 400,600", "show"])
    }
}
