//
//  SyntheticMoveEngineTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
@testable import Thaw
import XCTest

/// Characterization tests for `SyntheticMoveEngine.move`.
///
/// Pins down three behaviors of the physical Command-drag reorder engine:
/// anchored-target refusal, the dropX computation derived from the target's
/// live bounds, and the retry-until-`maxAttempts` give-up path. The real
/// `postCommandDrag` gesture (which posts hardware `CGEvent`s) is replaced
/// with a recording fake injected through the struct's `postCommandDrag`
/// property, so these tests assert *that it was called with the right
/// coordinates*, never that a real window moved.
@MainActor
final class SyntheticMoveEngineTests: XCTestCase {
    // MARK: - Helpers

    /// Records every `(start, end)` pair the engine hands to
    /// `postCommandDrag`, standing in for the real CGEvent-posting gesture.
    @MainActor
    private final class DragRecorder {
        private(set) var calls: [(start: CGPoint, end: CGPoint)] = []

        var fake: @MainActor (CGPoint, CGPoint, CGEventSource) async -> Void {
            { [weak self] start, end, _ in
                self?.calls.append((start, end))
            }
        }
    }

    /// Hands back one `[MenuBarItem]` layout per call, holding on the last
    /// layout once the sequence is exhausted. Mirrors repeated AX re-walks
    /// during the engine's retry loop.
    @MainActor
    private final class LayoutSequence {
        private let layouts: [[MenuBarItem]]
        private(set) var callCount = 0

        init(_ layouts: [[MenuBarItem]]) {
            self.layouts = layouts
        }

        var provider: @MainActor () async -> [MenuBarItem] {
            {
                defer { self.callCount += 1 }
                let index = min(self.callCount, self.layouts.count - 1)
                return self.layouts[index]
            }
        }
    }

    private func appTag(_ bundleID: String, _ title: String) -> MenuBarItemTag {
        .appItem(bundleID: bundleID, title: title)
    }

    /// Builds an engine wired with a fresh semaphore, a real event source
    /// (never actually used to post events since `postCommandDrag` is
    /// replaced), and the given fakes.
    private func makeEngine(
        enumerateItems: @escaping @MainActor () async -> [MenuBarItem],
        postCommandDrag: @escaping @MainActor (CGPoint, CGPoint, CGEventSource) async -> Void
    ) -> SyntheticMoveEngine {
        SyntheticMoveEngine(
            eventSemaphore: SimpleSemaphore(value: 1),
            makeEventSource: Self.makeRealEventSource,
            enumerateItems: enumerateItems,
            postCommandDrag: postCommandDrag
        )
    }

    private static func makeRealEventSource() throws -> CGEventSource {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw MenuBarItemManager.EventError.invalidEventSource
        }
        return source
    }

    /// The real display frame, used so on-screen guard checks in `move`
    /// pass for scenarios that are not deliberately testing the off-screen
    /// refusal path.
    private func requireScreenFrame() throws -> CGRect {
        guard let frame = NSScreen.screens.first?.frame else {
            throw XCTSkip("No screen available to anchor fixture bounds against")
        }
        return frame
    }

    // MARK: - 1. Anchored-target refusal

    /// A destination anchored on a fixed system item (not physically
    /// orderable, and not the zero-width section-boundary divider either)
    /// is refused before any semaphore/event-source/enumeration work
    /// happens.
    func testMove_RefusesAnchoredTarget() async throws {
        let frame = try requireScreenFrame()
        let mover = MenuBarItem.fixture(
            tag: appTag("com.example.mover", "Mover"),
            windowID: 1,
            bounds: CGRect(x: frame.minX + 100, y: frame.maxY - 22, width: 24, height: 22)
        )
        // .screenCaptureUI lives in a fixedSystemAgentNamespace: not
        // physically orderable, and not a control-item boundary divider
        // either, so it must be refused as an anchor.
        let anchoredTarget = MenuBarItem.fixture(
            tag: .screenCaptureUI,
            windowID: 2,
            bounds: CGRect(x: frame.minX + 200, y: frame.maxY - 22, width: 24, height: 22)
        )

        let recorder = DragRecorder()
        let sequence = LayoutSequence([[mover, anchoredTarget]])
        let engine = makeEngine(enumerateItems: sequence.provider, postCommandDrag: recorder.fake)

        do {
            try await engine.move(item: mover, to: .leftOfItem(anchoredTarget))
            XCTFail("expected itemNotMovable to be thrown")
        } catch let MenuBarItemManager.EventError.itemNotMovable(erroredItem) {
            XCTAssertEqual(erroredItem.tag, anchoredTarget.tag)
        }

        XCTAssertEqual(recorder.calls.count, 0, "anchored-target refusal must happen before any drag is posted")
        XCTAssertEqual(sequence.callCount, 0, "anchored-target refusal must happen before live enumeration")
    }

    // MARK: - 2. Already-satisfied short circuit

    /// When the first AX snapshot already satisfies the destination, the
    /// engine returns immediately without posting a drag.
    func testMove_ReturnsSuccessWhenAlreadySatisfied() async throws {
        let frame = try requireScreenFrame()
        let target = MenuBarItem.fixture(
            tag: appTag("com.example.anchor", "Anchor"),
            windowID: 910,
            bounds: CGRect(x: frame.minX + 100, y: frame.maxY - 22, width: 24, height: 22)
        )
        // Directly right of target's maxX (126): already satisfies
        // .rightOfItem(target).
        let mover = MenuBarItem.fixture(
            tag: appTag("com.example.mover", "Mover"),
            windowID: 810,
            bounds: CGRect(x: frame.minX + 126, y: frame.maxY - 22, width: 24, height: 22)
        )

        let recorder = DragRecorder()
        let sequence = LayoutSequence([[target, mover]])
        let engine = makeEngine(enumerateItems: sequence.provider, postCommandDrag: recorder.fake)

        try await engine.move(item: mover, to: .rightOfItem(target))

        XCTAssertEqual(recorder.calls.count, 0, "already-satisfied destination must not trigger a drag")
        XCTAssertEqual(sequence.callCount, 1, "only the initial enumeration is needed once already satisfied")
    }

    // MARK: - 3. dropX computed from target bounds

    /// `.leftOfItem` drops at `targetBounds.minX - syntheticDragDropInset`
    /// (read from SyntheticMoveEngine.swift's dropX switch). The engine
    /// must call `postCommandDrag` with exactly that x, and the target's
    /// midY as its y.
    func testMove_ComputesDropXFromTargetBounds() async throws {
        let frame = try requireScreenFrame()
        let targetBounds = CGRect(x: frame.minX + 200, y: frame.maxY - 22, width: 24, height: 22)
        let target = MenuBarItem.fixture(
            tag: appTag("com.example.anchor", "Anchor"),
            windowID: 910,
            bounds: targetBounds
        )
        let moverBounds = CGRect(x: frame.minX + 500, y: frame.maxY - 22, width: 24, height: 22)
        let mover = MenuBarItem.fixture(
            tag: appTag("com.example.mover", "Mover"),
            windowID: 810,
            bounds: moverBounds
        )

        // After the drag, mover lands left of target so the retry loop
        // stops.
        let satisfiedMover = MenuBarItem.fixture(
            tag: appTag("com.example.mover", "Mover"),
            windowID: 810,
            bounds: CGRect(x: frame.minX + 150, y: frame.maxY - 22, width: 24, height: 22)
        )
        let satisfiedTarget = MenuBarItem.fixture(
            tag: appTag("com.example.anchor", "Anchor"),
            windowID: 910,
            bounds: CGRect(x: frame.minX + 300, y: frame.maxY - 22, width: 24, height: 22)
        )

        let recorder = DragRecorder()
        let sequence = LayoutSequence([
            [mover, target],
            [satisfiedMover, satisfiedTarget],
        ])
        let engine = makeEngine(enumerateItems: sequence.provider, postCommandDrag: recorder.fake)

        try await engine.move(item: mover, to: .leftOfItem(target))

        XCTAssertEqual(recorder.calls.count, 1)
        let inset: CGFloat = Constants.MenuBarTuning.syntheticDragDropInset
        XCTAssertEqual(recorder.calls[0].end.x, targetBounds.minX - inset)
        XCTAssertEqual(recorder.calls[0].end.y, targetBounds.midY)
        XCTAssertEqual(recorder.calls[0].start.x, moverBounds.midX)
        XCTAssertEqual(recorder.calls[0].start.y, moverBounds.midY)
    }

    // MARK: - 4. Off-screen source refused

    /// When the source item's live bounds fall outside every screen's
    /// frame, the on-screen-frame guard refuses the move before posting a
    /// drag.
    func testMove_ThrowsItemNotMovableWhenStartOffScreen() async throws {
        let frame = try requireScreenFrame()
        let target = MenuBarItem.fixture(
            tag: appTag("com.example.anchor", "Anchor"),
            windowID: 910,
            bounds: CGRect(x: frame.minX + 100, y: frame.maxY - 22, width: 24, height: 22)
        )
        // Far outside any real screen frame, and to the right of target so
        // .leftOfItem is not already (trivially) satisfied by index
        // adjacency alone.
        let mover = MenuBarItem.fixture(
            tag: appTag("com.example.mover", "Mover"),
            windowID: 810,
            bounds: CGRect(x: 999_999, y: 999_999, width: 24, height: 22)
        )

        let recorder = DragRecorder()
        let sequence = LayoutSequence([[target, mover]])
        let engine = makeEngine(enumerateItems: sequence.provider, postCommandDrag: recorder.fake)

        do {
            try await engine.move(item: mover, to: .leftOfItem(target))
            XCTFail("expected itemNotMovable to be thrown")
        } catch let MenuBarItemManager.EventError.itemNotMovable(erroredItem) {
            XCTAssertEqual(erroredItem.tag, mover.tag)
        }

        XCTAssertEqual(recorder.calls.count, 0, "off-screen source must be refused before posting a drag")
    }

    // MARK: - 5. Retries until maxAttempts then gives up

    /// When the live layout never satisfies the destination, the engine
    /// retries `maxAttempts` times (one drag per attempt) and then throws
    /// `.cannotComplete`.
    func testMove_RetriesUntilMaxAttempts() async throws {
        let frame = try requireScreenFrame()
        let target = MenuBarItem.fixture(
            tag: appTag("com.example.anchor", "Anchor"),
            windowID: 910,
            bounds: CGRect(x: frame.minX + 100, y: frame.maxY - 22, width: 24, height: 22)
        )
        // Stays left of target on every enumeration, so .rightOfItem never
        // becomes satisfied.
        let mover = MenuBarItem.fixture(
            tag: appTag("com.example.mover", "Mover"),
            windowID: 810,
            bounds: CGRect(x: frame.minX + 10, y: frame.maxY - 22, width: 24, height: 22)
        )

        let recorder = DragRecorder()
        let sequence = LayoutSequence([[target, mover]])
        let engine = makeEngine(enumerateItems: sequence.provider, postCommandDrag: recorder.fake)

        let maxAttempts = 3
        do {
            try await engine.move(item: mover, to: .rightOfItem(target), maxAttempts: maxAttempts)
            XCTFail("expected cannotComplete to be thrown")
        } catch MenuBarItemManager.EventError.cannotComplete {
            // expected
        }

        XCTAssertEqual(recorder.calls.count, maxAttempts, "one drag per attempt")
        XCTAssertEqual(sequence.callCount, maxAttempts + 1, "one initial enumeration plus one per attempt")
    }

    // MARK: - 6. currentBounds prefers the exact windowID+tag match

    /// `currentBounds` tries an exact `windowID`+`tag` match before falling
    /// back to a tag match that ignores `windowID`. When both a stale
    /// same-tag entry (different windowID, far-away bounds) and the exact
    /// match are present in the same live snapshot, the exact match must
    /// win — proving the drag is computed from fresh bounds, not a stale
    /// duplicate.
    func testMove_CurrentBoundsExactMatch() async throws {
        let frame = try requireScreenFrame()
        let moverTag = appTag("com.example.mover", "Mover")
        let target = MenuBarItem.fixture(
            tag: appTag("com.example.anchor", "Anchor"),
            windowID: 910,
            bounds: CGRect(x: frame.minX + 300, y: frame.maxY - 22, width: 24, height: 22)
        )
        // Exact match: same windowID as the item passed to move().
        let moverExactBounds = CGRect(x: frame.minX + 100, y: frame.maxY - 22, width: 24, height: 22)
        let moverExact = MenuBarItem.fixture(
            tag: moverTag,
            windowID: 800,
            bounds: moverExactBounds
        )
        // Decoy: same tag ignoring windowID, but a different windowID and
        // wildly different bounds. Must never be picked while the exact
        // match is present.
        let moverDecoy = MenuBarItem.fixture(
            tag: moverTag,
            windowID: 801,
            bounds: CGRect(x: frame.minX + 900, y: frame.maxY - 22, width: 24, height: 22)
        )
        let mover = MenuBarItem.fixture(tag: moverTag, windowID: 800, bounds: moverExactBounds)

        let satisfiedMover = MenuBarItem.fixture(
            tag: moverTag,
            windowID: 800,
            bounds: CGRect(x: frame.minX + 400, y: frame.maxY - 22, width: 24, height: 22)
        )
        let satisfiedTarget = MenuBarItem.fixture(
            tag: appTag("com.example.anchor", "Anchor"),
            windowID: 910,
            bounds: CGRect(x: frame.minX + 300, y: frame.maxY - 22, width: 24, height: 22)
        )

        let recorder = DragRecorder()
        let sequence = LayoutSequence([
            [moverExact, moverDecoy, target],
            [satisfiedMover, satisfiedTarget],
        ])
        let engine = makeEngine(enumerateItems: sequence.provider, postCommandDrag: recorder.fake)

        try await engine.move(item: mover, to: .rightOfItem(target))

        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(
            recorder.calls[0].start.x, moverExactBounds.midX,
            "currentBounds must prefer the exact windowID+tag match over the same-tag decoy"
        )
        XCTAssertEqual(recorder.calls[0].start.y, moverExactBounds.midY)
    }
}
