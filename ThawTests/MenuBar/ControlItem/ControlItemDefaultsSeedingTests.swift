//
//  ControlItemDefaultsSeedingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes the section-divider write guard and the seeding path that
/// bypasses it (#890).
///
/// The guard was added by ff7517f7 to stop a user breaking their menu bar by
/// dragging a chevron. It cannot do that — AppKit writes
/// `NSStatusItem Preferred Position <autosaveName>` itself, never through
/// `ControlItemDefaults` — so it only ever blocked Thaw's own writes,
/// including the seeding the very same commit introduced.
/// Serialized and run against a scratch defaults suite: these cases write
/// real `NSStatusItem Preferred Position` keys, and `Defaults.store` is
/// process-wide, so without both a run would clobber the divider positions of
/// whoever is running the tests.
@Suite("Control item defaults seeding", .serialized)
struct ControlItemDefaultsSeedingTests {
    private static let hidden = ControlItem.Identifier.hidden.rawValue
    private static let alwaysHidden = ControlItem.Identifier.alwaysHidden.rawValue
    private static let visible = ControlItem.Identifier.visible.rawValue

    private func storedPosition(_ autosaveName: String) -> CGFloat? {
        ControlItemDefaults[.preferredPosition, autosaveName]
    }

    /// Both dividers are covered by the guard; the visible control item is not.
    @Test("Only the two dividers are treated as section dividers")
    func identifiesSectionDividers() {
        #expect(ControlItemDefaults.isSectionDivider(autosaveName: Self.hidden))
        #expect(ControlItemDefaults.isSectionDivider(autosaveName: Self.alwaysHidden))
        #expect(!ControlItemDefaults.isSectionDivider(autosaveName: Self.visible))
    }

    /// The behavior that made every seeding site a no-op. Pinned rather than
    /// removed: the guard still applies to any caller that is not one of the
    /// two deliberate seeding paths.
    @Test("The subscript still refuses to write a divider position")
    func subscriptStillRefusesDividerWrites() throws {
        try withScratchDefaults { _ in
            ControlItemDefaults[.preferredPosition, Self.hidden] = 1
            #expect(storedPosition(Self.hidden) == nil)
        }
    }

    /// The fix. Without this, the hidden divider never receives the position
    /// preflightSetup intends to give it, and with no stored position both
    /// dividers can be placed at the same X — collapsing the span between
    /// them to zero width.
    @Test("The seeding path writes through the guard")
    func seedingPathWritesThroughTheGuard() throws {
        try withScratchDefaults { _ in
            ControlItemDefaults.setIgnoringSectionDividerGuard(.preferredPosition, Self.hidden, to: 1)
            #expect(storedPosition(Self.hidden) == 1)
        }
    }

    /// The seeding path is not divider-specific — it is simply unguarded —
    /// so it must behave identically for a non-divider autosave name.
    @Test("The seeding path is unguarded for non-dividers too")
    func seedingPathWorksForNonDividers() throws {
        try withScratchDefaults { _ in
            ControlItemDefaults.setIgnoringSectionDividerGuard(.preferredPosition, Self.visible, to: 0)
            #expect(storedPosition(Self.visible) == 0)
        }
    }

    /// Non-position keys were never guarded and must stay unaffected.
    @Test("Non-position keys are unaffected by the guard")
    func nonPositionKeysAreUnaffected() {
        #expect(!ControlItemDefaults.Key<Bool>.visible.isPreferredPosition)
        #expect(ControlItemDefaults.Key<CGFloat>.preferredPosition.isPreferredPosition)
    }

    /// The reporter's workaround writes this exact defaults key by hand, so
    /// the key shape is part of the contract with anyone already using it.
    @Test("The stored key matches the AppKit defaults key")
    func keyShapeMatchesAppKit() {
        #expect(
            ControlItemDefaults.Key<CGFloat>.preferredPosition.stringKey(for: Self.hidden)
                == "NSStatusItem Preferred Position Thaw.ControlItem.Hidden"
        )
    }
}
