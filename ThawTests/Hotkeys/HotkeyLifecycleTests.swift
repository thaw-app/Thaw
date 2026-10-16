//
//  HotkeyLifecycleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``Hotkey`` construction, enable/disable, the change announcement,
/// and value equality, without an `AppState`.
///
/// Without `performSetup(with:)` the private `Listener` init returns `nil`,
/// so the hotkey never becomes enabled and `enable()` touches nothing global.
///
/// `HotkeysSettings`, `MenuBarManager`, and `ProfileManager` persist the
/// binding from the `keyCombination` `didSet` callback, which relies on:
///
/// - The value passed to `init` is **not** announced, so a binding just read
///   off disk is not written straight back.
/// - Every later assignment, including `nil`, announces **exactly once** with
///   the new value already stored. Otherwise `HotkeysSettings` would persist a
///   stale binding or leave a dead entry behind.
///
/// `performSetup(with:)`, listener registration and dispatch, and
/// `Listener.invalidate()` need a live `AppState` and are not covered, so
/// `isEnabled` is only asserted `false`.
@MainActor
@Suite("Hotkey lifecycle")
struct HotkeyLifecycleTests {
    // MARK: - Helpers

    private static let commandF19 = KeyCombination(key: .f19, modifiers: [.command])
    private static let controlOptionF20 = KeyCombination(key: .f20, modifiers: [.control, .option])
    private static let shiftSpace = KeyCombination(key: .space, modifiers: [.shift])

    /// Records the key combination each announcement saw.
    @MainActor
    private final class ChangeRecorder {
        private(set) var observed: [KeyCombination?] = []

        var count: Int {
            observed.count
        }

        func record(_ keyCombination: KeyCombination?) {
            observed.append(keyCombination)
        }
    }

    /// Attaches a recorder to `hotkey` that captures the key combination
    /// visible *from inside* the callback.
    private func recordChanges(of hotkey: Hotkey) -> ChangeRecorder {
        let recorder = ChangeRecorder()
        hotkey.keyCombinationDidChange = { [weak hotkey] in
            recorder.record(hotkey?.keyCombination)
        }
        return recorder
    }

    // MARK: - Construction

    @MainActor
    @Suite("Construction")
    struct Construction {
        @Test("A new hotkey keeps its action and starts unbound and disabled")
        func newHotkeyStartsUnbound() {
            let hotkey = Hotkey(action: .toggleHiddenSection)

            #expect(hotkey.action == .toggleHiddenSection)
            #expect(hotkey.keyCombination == nil)
            #expect(!hotkey.isEnabled)
        }

        @Test("A hotkey built with a key combination keeps it, still disabled")
        func newHotkeyKeepsItsKeyCombination() {
            let combination = KeyCombination(key: .f19, modifiers: [.command])
            let hotkey = Hotkey(action: .searchMenuBarItems, keyCombination: combination)

            #expect(hotkey.keyCombination == combination)
            #expect(!hotkey.isEnabled)
        }

        /// `HotkeysSettings` and `ProfileManager` build hotkeys for these
        /// actions, so no case may be special-cased out at construction.
        @Test("Every action can back a hotkey", arguments: HotkeyAction.allCases)
        func everyActionCanBackAHotkey(_ action: HotkeyAction) {
            let hotkey = Hotkey(action: action, keyCombination: KeyCombination(key: .a, modifiers: [.command]))

            #expect(hotkey.action == action)
            #expect(!hotkey.isEnabled)
        }
    }

    // MARK: - Enablement without an app state

    @MainActor
    @Suite("Enablement without an app state")
    struct Enablement {
        @Test("A hotkey with no app state cannot be enabled, bound or not")
        func enablingWithoutAnAppStateDoesNothing() {
            let unbound = Hotkey(action: .toggleHiddenSection)
            let bound = Hotkey(
                action: .toggleHiddenSection,
                keyCombination: KeyCombination(key: .f19, modifiers: [.command])
            )

            unbound.enable()
            bound.enable()

            #expect(!unbound.isEnabled)
            #expect(!bound.isEnabled)
        }

        @Test("Enabling repeatedly is harmless")
        func repeatedEnableIsHarmless() {
            let hotkey = Hotkey(
                action: .enableIceBar,
                keyCombination: KeyCombination(key: .f20, modifiers: [.control, .option])
            )

            hotkey.enable()
            hotkey.enable()
            hotkey.enable()

            #expect(!hotkey.isEnabled)
        }

        /// `disable()` runs on teardown paths that cannot know whether a
        /// listener was ever installed.
        @Test("Disabling a hotkey that was never enabled is idempotent")
        func disableIsIdempotent() {
            let hotkey = Hotkey(action: .toggleApplicationMenus)

            hotkey.disable()
            hotkey.disable()
            #expect(!hotkey.isEnabled)

            hotkey.enable()
            hotkey.disable()
            hotkey.disable()
            #expect(!hotkey.isEnabled)
        }
    }

    // MARK: - Change announcements

    @Test("The key combination a hotkey is built with is never announced")
    func initialKeyCombinationIsNotAnnounced() {
        let hotkey = Hotkey(action: .toggleHiddenSection, keyCombination: Self.commandF19)
        let recorder = recordChanges(of: hotkey)

        #expect(recorder.observed.isEmpty)
        #expect(hotkey.keyCombination == Self.commandF19)
    }

    @Test("Assigning a key combination announces it exactly once")
    func assignmentAnnouncesOnce() {
        let hotkey = Hotkey(action: .toggleHiddenSection)
        let recorder = recordChanges(of: hotkey)

        hotkey.keyCombination = Self.commandF19

        #expect(recorder.count == 1)
        #expect(recorder.observed == [Self.commandF19])
    }

    /// The owners read `hotkey.keyCombination` from inside the callback rather
    /// than being handed the value, so the store has to have happened first.
    @Test("An announcement sees the new value already stored")
    func announcementSeesTheStoredValue() {
        let hotkey = Hotkey(action: .searchMenuBarItems)
        let recorder = recordChanges(of: hotkey)

        hotkey.keyCombination = Self.controlOptionF20

        #expect(recorder.observed == [Self.controlOptionF20])
    }

    @Test("Each assignment announces once, in order")
    func everyAssignmentAnnouncesInOrder() {
        let hotkey = Hotkey(action: .toggleAlwaysHiddenSection)
        let recorder = recordChanges(of: hotkey)

        hotkey.keyCombination = Self.commandF19
        hotkey.keyCombination = Self.controlOptionF20
        hotkey.keyCombination = Self.shiftSpace

        #expect(recorder.observed == [Self.commandF19, Self.controlOptionF20, Self.shiftSpace])
    }

    /// Unbinding deletes the stored entry, so the callback has to see `nil`.
    @Test("Clearing a key combination announces the cleared value")
    func clearingIsAnnounced() {
        let hotkey = Hotkey(action: .enableIceBar, keyCombination: Self.commandF19)
        let recorder = recordChanges(of: hotkey)

        hotkey.keyCombination = nil

        #expect(recorder.observed == [nil])
        #expect(hotkey.keyCombination == nil)
    }

    /// The announcement is an assignment signal, not a change signal.
    @Test("Reassigning the same key combination announces again")
    func reassigningTheSameValueAnnouncesAgain() {
        let hotkey = Hotkey(action: .toggleHiddenSection)
        let recorder = recordChanges(of: hotkey)

        hotkey.keyCombination = Self.commandF19
        hotkey.keyCombination = Self.commandF19

        #expect(recorder.observed == [Self.commandF19, Self.commandF19])
    }

    @Test("A hotkey with no observer still stores its assignments")
    func assignmentWithoutAnObserverStillStores() {
        let hotkey = Hotkey(action: .toggleApplicationMenus)

        hotkey.keyCombination = Self.commandF19
        #expect(hotkey.keyCombination == Self.commandF19)

        hotkey.keyCombination = nil
        #expect(hotkey.keyCombination == nil)
    }

    /// The owners hold the hotkey weakly from inside the callback and drop the
    /// callback when they rebuild; a dropped callback must not keep firing.
    @Test("Dropping the observer stops the announcements")
    func droppingTheObserverStopsAnnouncements() {
        let hotkey = Hotkey(action: .toggleHiddenSection)
        let recorder = recordChanges(of: hotkey)

        hotkey.keyCombination = Self.commandF19
        hotkey.keyCombinationDidChange = nil
        hotkey.keyCombination = Self.controlOptionF20

        #expect(recorder.observed == [Self.commandF19])
        #expect(hotkey.keyCombination == Self.controlOptionF20)
    }

    // MARK: - Equality and hashing

    @MainActor
    @Suite("Equality and hashing")
    struct Equality {
        private func hashValue(of hotkey: Hotkey) -> Int {
            var hasher = Hasher()
            hotkey.hash(into: &hasher)
            return hasher.finalize()
        }

        /// `Hotkey` is a class that compares by value.
        @Test("Two hotkeys with the same action and binding are equal")
        func sameActionAndBindingAreEqual() {
            let combination = KeyCombination(key: .f19, modifiers: [.command])
            let first = Hotkey(action: .toggleHiddenSection, keyCombination: combination)
            let second = Hotkey(action: .toggleHiddenSection, keyCombination: combination)

            #expect(first == second)
            #expect(hashValue(of: first) == hashValue(of: second))
        }

        @Test("Two unbound hotkeys with the same action are equal")
        func unboundHotkeysWithTheSameActionAreEqual() {
            let first = Hotkey(action: .searchMenuBarItems)
            let second = Hotkey(action: .searchMenuBarItems)

            #expect(first == second)
            #expect(hashValue(of: first) == hashValue(of: second))
        }

        @Test("A different action breaks equality")
        func differentActionBreaksEquality() {
            let combination = KeyCombination(key: .f19, modifiers: [.command])
            let first = Hotkey(action: .toggleHiddenSection, keyCombination: combination)
            let second = Hotkey(action: .toggleAlwaysHiddenSection, keyCombination: combination)

            #expect(first != second)
        }

        @Test("A different binding breaks equality")
        func differentBindingBreaksEquality() {
            let first = Hotkey(
                action: .toggleHiddenSection,
                keyCombination: KeyCombination(key: .f19, modifiers: [.command])
            )
            let second = Hotkey(
                action: .toggleHiddenSection,
                keyCombination: KeyCombination(key: .f19, modifiers: [.command, .shift])
            )

            #expect(first != second)
        }

        @Test("An unbound hotkey differs from a bound one with the same action")
        func unboundDiffersFromBound() {
            let unbound = Hotkey(action: .enableIceBar)
            let bound = Hotkey(
                action: .enableIceBar,
                keyCombination: KeyCombination(key: .f19, modifiers: [.command])
            )

            #expect(unbound != bound)
        }

        /// Equality reads the *current* binding, not the one the hotkey was
        /// built with.
        @Test("Equality follows a rebinding rather than the original value")
        func equalityFollowsRebinding() {
            let combination = KeyCombination(key: .f20, modifiers: [.control, .option])
            let first = Hotkey(action: .toggleApplicationMenus)
            let second = Hotkey(action: .toggleApplicationMenus)
            #expect(first == second)

            first.keyCombination = combination
            #expect(first != second)

            second.keyCombination = combination
            #expect(first == second)
            #expect(hashValue(of: first) == hashValue(of: second))
        }
    }
}
