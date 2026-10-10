//
//  ControlItemDefaultsSeedingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes the section-divider write guard and the seeding path that
/// bypasses it (#890).
///
/// AppKit writes `NSStatusItem Preferred Position <autosaveName>` itself, never
/// through `ControlItemDefaults`, so the guard only ever blocked Thaw's own
/// writes, including seeding.
///
/// Serialized on a scratch defaults suite: these write real position keys
/// through the process-wide `Defaults.store`.
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

    /// The guard still applies to any caller other than the two seeding paths.
    @Test("The subscript still refuses to write a divider position")
    func subscriptStillRefusesDividerWrites() throws {
        try withScratchDefaults { _ in
            ControlItemDefaults[.preferredPosition, Self.hidden] = 1
            #expect(storedPosition(Self.hidden) == nil)
        }
    }

    /// With no stored position both dividers can land at the same X,
    /// collapsing the span between them to zero width.
    @Test("The seeding path writes through the guard")
    func seedingPathWritesThroughTheGuard() throws {
        try withScratchDefaults { _ in
            ControlItemDefaults.setIgnoringSectionDividerGuard(.preferredPosition, Self.hidden, to: 1)
            #expect(storedPosition(Self.hidden) == 1)
        }
    }

    /// The seeding path is simply unguarded, not divider-specific.
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

    /// An unconditional reset here yanks the hidden divider back beside the
    /// visible one on every launch and `recreateStatusItem()`, and the next
    /// save persists the collapsed span (#895).
    @Test("Preflight leaves a divider position the user already has")
    func preflightKeepsStoredDividerPosition() throws {
        try withScratchDefaults { _ in
            ControlItemDefaults.setIgnoringSectionDividerGuard(.preferredPosition, Self.hidden, to: 1051)
            ControlItemDefaults.preflightSetup(for: .hidden)
            #expect(storedPosition(Self.hidden) == 1051)
        }
    }

    /// A first launch has no stored position, and leaving it unset lets both
    /// dividers land on the same X.
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

    /// Users write this defaults key by hand as a workaround, so its shape is
    /// part of the contract.
    @Test("The stored key matches the AppKit defaults key")
    func keyShapeMatchesAppKit() {
        #expect(
            ControlItemDefaults.Key<CGFloat>.preferredPosition.stringKey(for: Self.hidden)
                == "NSStatusItem Preferred Position Thaw.ControlItem.Hidden"
        )
    }
}
