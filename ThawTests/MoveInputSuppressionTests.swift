//
//  MoveInputSuppressionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under GNU GPLv3

@testable import Thaw
import XCTest

/// Tests for the pure decision logic in ``MoveInputSuppression``. Never
/// posts any of the constructed events — they exist only to exercise
/// ``MoveInputSuppression/shouldSuppress(_:)``.
///
/// These tests deliberately avoid asserting anything about per-event
/// `eventSourceUserData` *writes* (`CGEvent.setIntegerValueField`), since
/// that behavior was found to differ across macOS SDK versions (a no-op on
/// macOS 27, unverified on macOS 26 — see `MoveInputSuppression`'s
/// type-level note). They instead assert only on *source-level* marking via
/// ``MoveInputSuppression/makeSyntheticMoveEventSource()``, which is
/// documented, version-stable CoreGraphics behavior: an event inherits its
/// source's `userData` at creation time on every macOS release.
final class MoveInputSuppressionTests: XCTestCase {
    private func makeMouseEvent(type: CGEventType, source: CGEventSource) throws -> CGEvent {
        try XCTUnwrap(
            CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: .zero,
                mouseButton: .left
            )
        )
    }

    /// An event created from the dedicated synthetic-move source inherits
    /// nonzero `eventSourceUserData` at creation and must never be
    /// suppressed.
    func testEventFromSyntheticMoveSourceIsNotSuppressed() throws {
        let source = try MoveInputSuppression.makeSyntheticMoveEventSource()
        let event = try makeMouseEvent(type: .leftMouseDragged, source: source)
        XCTAssertFalse(MoveInputSuppression.shouldSuppress(event))
    }

    /// An event created from a plain source (zero `userData`, the default)
    /// of a suppressed mouse type must be suppressed.
    func testMouseEventFromPlainSourceIsSuppressed() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        XCTAssertEqual(source.userData, 0)
        let event = try makeMouseEvent(type: .leftMouseDragged, source: source)
        XCTAssertTrue(MoveInputSuppression.shouldSuppress(event))
    }

    /// A non-mouse event type from a plain (zero `userData`) source is never
    /// suppressed, regardless of source marking.
    func testNonMouseEventTypeFromPlainSourceIsNotSuppressed() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        )
        XCTAssertFalse(MoveInputSuppression.shouldSuppress(event))
    }

    /// A non-mouse event type is never suppressed even when created from the
    /// dedicated synthetic-move source.
    func testNonMouseEventTypeFromSyntheticMoveSourceIsNotSuppressed() throws {
        let source = try MoveInputSuppression.makeSyntheticMoveEventSource()
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        )
        XCTAssertFalse(MoveInputSuppression.shouldSuppress(event))
    }
}
