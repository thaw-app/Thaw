//
//  WindowInfoDecodingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers the halves of ``WindowInfo`` that survive without a window server:
/// the memberwise initializer, the *refusal* side of the synthesized `Codable`
/// conformance, and the derived properties that the menu-bar rules read.
///
/// `WindowInfoTests` already covers the happy path — an encode/decode round
/// trip, every field's contribution to `==`, hashing of equal values, and the
/// three window levels `isMenuRelated` names outright. This suite deliberately
/// starts where that one stops:
///
/// - **Decoding refusals.** A `WindowInfo` is persisted and replayed (menu-bar
///   item caches, failure ledgers, diagnostic captures), so a truncated or
///   wrongly typed payload has to fail loudly rather than decode into a window
///   with a plausible-looking zero rect. `bounds` is the interesting one: it is
///   a `CGRect`, which encodes as the nested unkeyed pair `[[x, y], [w, h]]`
///   and whose decoder reads positionally, so arity is the only thing standing
///   between a short payload and a silent misread.
/// - **The memberwise initializer's defaults**, which exist purely so the rules
///   below can be exercised without a live window, and which nothing else
///   asserts.
/// - **`isMenuRelated`'s off-by-one arm.** The rule accepts the pop-up menu
///   level *and the level one below it*; nothing currently distinguishes that
///   arm, and `isMenuRelatedForWindowServer` in the sibling suite happens to
///   use layer 25 — the status level — so it passes whether or not the
///   Window-Server arm exists at all.
///
/// Deliberately **not** covered, and not coverable here:
///
/// - `createWindows(from:)`, `createWindows(option:)`, `createMenuBarWindows`,
///   `init?(windowID:)` and `currentBounds()`. All four go through `Bridging`
///   to the live window server; their answers depend on what is on screen.
/// - `init?(dictionary:)`, which is `private` and only ever reached from those
///   enumeration functions.
/// - `wallpaperWindow(from:for:)` and `menuBarWindow(from:for:)`. Both close
///   over `CGDisplayBounds(display)`, which answers with a real display's frame
///   on any machine that has one, so neither a match nor a non-match can be
///   arranged deterministically — a test would assert the developer's monitor
///   layout rather than the code.
@Suite("Window info decoding and derived rules")
struct WindowInfoDecodingTests {
    // MARK: - Helpers

    /// A payload carrying every key the synthesized decoder reads, in the
    /// shape `JSONEncoder` produces for a `WindowInfo`.
    ///
    /// Computed rather than stored: `[String: Any]` is not `Sendable`, so a
    /// `static let` is rejected under strict concurrency. Recomputing also
    /// means a test that mutates its copy cannot leak into the next one.
    private static var wellFormedPayload: [String: Any] {
        [
            "windowID": 12345,
            "ownerPID": 501,
            "bounds": [[12.0, 34.0], [200.0, 24.0]],
            "layer": 25,
            "title": "Menubar",
            "ownerName": "Window Server",
            "isOnScreen": true,
        ]
    }

    private func decodeWindow(from payload: [String: Any]) throws -> WindowInfo {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(WindowInfo.self, from: data)
    }

    /// Decodes `payload` expecting failure, and hands back the error so the
    /// caller can assert *which* field the decoder objected to.
    private func decodingFailure(for payload: [String: Any]) throws -> DecodingError {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(WindowInfo.self, from: data)
        }
    }

    // MARK: - Memberwise construction

    @Suite("Building a window from its properties")
    struct MemberwiseInit {
        @Test("A window keeps every property it was built with")
        func everyPropertyIsKept() {
            let window = WindowInfo(
                windowID: 77,
                ownerPID: 4242,
                bounds: CGRect(x: 5, y: 6, width: 7, height: 8),
                layer: 3,
                title: "Some Title",
                ownerName: "Some App",
                isOnScreen: false
            )

            #expect(window.windowID == 77)
            #expect(window.ownerPID == 4242)
            #expect(window.bounds == CGRect(x: 5, y: 6, width: 7, height: 8))
            #expect(window.layer == 3)
            #expect(window.title == "Some Title")
            #expect(window.ownerName == "Some App")
            #expect(!window.isOnScreen)
        }

        /// The three defaults are what let a rule under test be written as a
        /// four-argument call. A window with no title and no owner name is also
        /// the shape the window server hands back for anonymous windows.
        @Test("The optional properties default to unnamed and on screen")
        func optionalPropertiesHaveDefaults() {
            let window = WindowInfo(windowID: 1, ownerPID: 2, bounds: .zero, layer: 0)

            #expect(window.title == nil)
            #expect(window.ownerName == nil)
            #expect(window.isOnScreen)
        }
    }

    /// Building a window by hand and decoding the same window from JSON must
    /// land on the same value, or a test fixture built one way would not stand
    /// in for a window that arrived the other.
    @Test("A hand-built window matches the same window decoded")
    func memberwiseInitMatchesDecoding() throws {
        let decoded = try decodeWindow(from: Self.wellFormedPayload)
        let built = WindowInfo(
            windowID: 12345,
            ownerPID: 501,
            bounds: CGRect(x: 12, y: 34, width: 200, height: 24),
            layer: 25,
            title: "Menubar",
            ownerName: "Window Server",
            isOnScreen: true
        )

        #expect(decoded == built)

        var decodedHasher = Hasher()
        decoded.hash(into: &decodedHasher)
        var builtHasher = Hasher()
        built.hash(into: &builtHasher)
        #expect(decodedHasher.finalize() == builtHasher.finalize())
    }

    // MARK: - Decoding refusals

    @Test(
        "A payload missing a required key is refused, naming that key",
        arguments: ["windowID", "ownerPID", "bounds", "layer", "isOnScreen"]
    )
    func missingRequiredKeyIsRefused(_ missingKey: String) throws {
        var payload = Self.wellFormedPayload
        payload.removeValue(forKey: missingKey)

        let error = try decodingFailure(for: payload)

        guard case let .keyNotFound(key, _) = error else {
            Issue.record("expected a keyNotFound error for \(missingKey), got \(error)")
            return
        }
        #expect(key.stringValue == missingKey)
    }

    /// `title` and `ownerName` are the only optional properties, so they are
    /// the only two a payload may leave out.
    @Test("A payload without a title or an owner name still decodes")
    func absentOptionalKeysDecodeAsUnset() throws {
        var payload = Self.wellFormedPayload
        payload.removeValue(forKey: "title")
        payload.removeValue(forKey: "ownerName")

        let window = try decodeWindow(from: payload)

        #expect(window.title == nil)
        #expect(window.ownerName == nil)
        #expect(window.windowID == 12345)
    }

    @Test(
        "A wrongly typed field is refused rather than coerced",
        arguments: ["windowID", "ownerPID", "bounds", "layer", "title", "ownerName", "isOnScreen"]
    )
    func wronglyTypedFieldIsRefused(_ field: String) throws {
        // Deliberately mixed: a string where a number belongs, a number and a
        // Boolean where a string belongs, an object where the nested pair
        // belongs, and the JSON `1` that a laxer decoder would happily read
        // back as `true`.
        let wrongValues: [String: Any] = [
            "windowID": "not a number",
            "ownerPID": "not a number",
            "bounds": 5,
            "layer": "not a number",
            "title": 7,
            "ownerName": false,
            "isOnScreen": 1,
        ]

        var payload = Self.wellFormedPayload
        payload[field] = try #require(wrongValues[field])

        _ = try decodingFailure(for: payload)
    }

    /// `CGRect` decodes positionally out of an unkeyed container, so a payload
    /// that runs out of elements has to fail rather than fill the rest in.
    @Test(
        "A bounds payload of the wrong shape is refused",
        arguments: ["originOnly", "empty", "flattened"]
    )
    func malformedBoundsIsRefused(_ shape: String) throws {
        let malformedBounds: [String: [Any]] = [
            "originOnly": [[1.0, 2.0]],
            "empty": [],
            "flattened": [1.0, 2.0, 3.0, 4.0],
        ]

        var payload = Self.wellFormedPayload
        payload["bounds"] = try #require(malformedBounds[shape])

        _ = try decodingFailure(for: payload)
    }

    /// The complement of the arity check: `CGRect` stops after the origin and
    /// the size, so trailing elements are ignored rather than rejected. Pinned
    /// because it is the difference between the two ends of the same guard.
    @Test("A bounds payload with trailing elements is tolerated")
    func trailingBoundsElementsAreIgnored() throws {
        var payload = Self.wellFormedPayload
        payload["bounds"] = [[12.0, 34.0], [200.0, 24.0], [99.0, 99.0]]

        let window = try decodeWindow(from: payload)

        #expect(window.bounds == CGRect(x: 12, y: 34, width: 200, height: 24))
    }

    /// `windowID` is a `CGWindowID`, which is unsigned. A negative number is
    /// not a window identifier that merely wrapped around.
    @Test("A negative window identifier is refused")
    func negativeWindowIdentifierIsRefused() throws {
        var payload = Self.wellFormedPayload
        payload["windowID"] = -1

        _ = try decodingFailure(for: payload)
    }

    /// A window description carries far more keys than `WindowInfo` reads, so
    /// the decoder must not be tightened into rejecting the extras.
    @Test("Keys the window does not model are ignored")
    func unmodelledKeysAreIgnored() throws {
        var payload = Self.wellFormedPayload
        payload["kCGWindowAlpha"] = 0.5
        payload["kCGWindowSharingState"] = 1
        payload["kCGWindowStoreType"] = 2

        let window = try decodeWindow(from: payload)

        #expect(window.windowID == 12345)
        #expect(window.bounds == CGRect(x: 12, y: 34, width: 200, height: 24))
    }

    // MARK: - Derived properties

    @Suite("Derived window rules")
    struct DerivedRules {
        private func window(layer: Int = 0, ownerName: String? = nil, ownerPID: pid_t = 501) -> WindowInfo {
            WindowInfo(
                windowID: 1,
                ownerPID: ownerPID,
                bounds: CGRect(x: 0, y: 0, width: 100, height: 22),
                layer: layer,
                ownerName: ownerName
            )
        }

        /// A negative process identifier can never name a running process, so
        /// this is the one owner lookup with an answer that does not depend on
        /// what happens to be running.
        @Test("A window owned by no possible process has no owning application")
        func impossibleOwnerHasNoApplication() {
            #expect(window(ownerPID: -1).owningApplication == nil)
            #expect(window(ownerPID: -424_242).owningApplication == nil)
        }

        /// A window with area is the ordinary case and must stay eligible to
        /// start a source-PID scan; the fixture's 100x22 is a normal status
        /// item's geometry.
        @Test("A window with area is not degenerate")
        func windowWithAreaIsNotDegenerate() {
            #expect(!window().isDegenerate)
        }

        /// Every source-PID match path anchors on the window's centre, so a
        /// window missing either dimension has nothing to match against. The
        /// zero-width case is the one observed in the field (#956): a status
        /// item at `(-4323, 0, 0, 0)` that nine consecutive scans over seven
        /// minutes never resolved, while waking a full traversal of every
        /// running app each time.
        @Test(
            "A window missing either dimension is degenerate",
            arguments: [
                CGRect(x: -4323, y: 0, width: 0, height: 0),
                CGRect(x: 0, y: 0, width: 0, height: 22),
                CGRect(x: 0, y: 0, width: 100, height: 0),
            ]
        )
        func windowMissingADimensionIsDegenerate(_ bounds: CGRect) {
            let window = WindowInfo(windowID: 1, ownerPID: 501, bounds: bounds, layer: 0)
            #expect(window.isDegenerate)
        }

        /// Position alone must not decide this. An off-screen or negatively
        /// positioned item is perfectly matchable — the field case sits at
        /// x = -4323 and would be wrongly skipped by a rule that keyed on
        /// coordinates instead of size.
        @Test("A window far off-screen is not degenerate as long as it has area")
        func offScreenWindowWithAreaIsNotDegenerate() {
            let window = WindowInfo(
                windowID: 1,
                ownerPID: 501,
                bounds: CGRect(x: -4323, y: 0, width: 40, height: 33),
                layer: 0
            )
            #expect(!window.isDegenerate)
        }

        @Test(
            "The Window Server is recognized only under its exact name",
            arguments: ["window server", "WINDOW SERVER", "WindowServer", "Window  Server", " Window Server", ""]
        )
        func windowServerNameIsMatchedExactly(_ ownerName: String) {
            #expect(!window(ownerName: ownerName).isWindowServerWindow)
        }

        /// The sibling suite's Window-Server case uses layer 25, which is the
        /// status level and so satisfies `isMenuRelated` on its own. Layer 0 is
        /// the normal window level, so only the Window-Server arm can carry
        /// this one.
        @Test("A Window Server window is menu related even at the normal window level")
        func windowServerWindowIsMenuRelatedAtAnyLayer() {
            #expect(window(layer: 0, ownerName: "Window Server").isMenuRelated)
        }

        /// The rule accepts the pop-up menu level *and the level immediately
        /// below it*, because some menus sit slightly under it. Nothing else
        /// pins where that tolerance starts and stops.
        @Test("The tolerance below the pop-up menu level is exactly one level wide")
        func popUpMenuToleranceIsOneLevelWide() {
            let popUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))

            #expect(window(layer: popUpLevel - 1, ownerName: "Some App").isMenuRelated)
            #expect(!window(layer: popUpLevel - 2, ownerName: "Some App").isMenuRelated)
            #expect(!window(layer: popUpLevel + 1, ownerName: "Some App").isMenuRelated)
        }

        /// The levels between the main menu and the status window are not menu
        /// related; the rule names three levels, it does not name a range.
        @Test("A level between the ones the rule names is not menu related")
        func levelsBetweenNamedOnesAreNotMenuRelated() {
            let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
            let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

            // The two named levels are adjacent on every macOS to date, so the
            // gap is asserted on the far side of each instead.
            #expect(!window(layer: mainMenuLevel - 1, ownerName: "Some App").isMenuRelated)
            #expect(!window(layer: statusLevel + 1, ownerName: "Some App").isMenuRelated)
        }
    }
}
