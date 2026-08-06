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

    /// Preflight ran a second, unconditional reset of the hidden divider
    /// alongside the seed above. It was inert while the subscript guard
    /// refused divider writes, so activating the seed in #890 also activated
    /// the reset: a populated bar had its hidden divider yanked back beside
    /// the visible one on every launch and every `recreateStatusItem()`, and
    /// the save that followed persisted the collapsed span (#895).
    @Test("Preflight leaves a divider position the user already has")
    func preflightKeepsStoredDividerPosition() throws {
        try withScratchDefaults { _ in
            ControlItemDefaults.setIgnoringSectionDividerGuard(.preferredPosition, Self.hidden, to: 1051)
            ControlItemDefaults.preflightSetup(for: .hidden)
            #expect(storedPosition(Self.hidden) == 1051)
        }
    }

    /// The seed itself has to survive the fix above: a first launch has no
    /// stored position, and leaving it unset lets both dividers land on the
    /// same X.
    @Test("Preflight still seeds a divider that has no stored position")
    func preflightSeedsUnsetDivider() throws {
        try withScratchDefaults { _ in
            ControlItemDefaults.preflightSetup(for: .hidden)
            #expect(storedPosition(Self.hidden) == 1)
        }
    }

    /// Always-hidden is positioned dynamically and is deliberately never
    /// seeded, so preflight must leave it absent rather than default it.
    @Test("Preflight does not seed the always-hidden divider")
    func preflightLeavesAlwaysHiddenUnset() throws {
        try withScratchDefaults { _ in
            ControlItemDefaults.preflightSetup(for: .alwaysHidden)
            #expect(storedPosition(Self.alwaysHidden) == nil)
        }
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
