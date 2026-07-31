//
//  HotkeyLifecycleTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``Hotkey`` itself — construction, the enable/disable pair, the
/// change announcement, and value equality — without an `AppState`.
///
/// `Hotkey`'s private `Listener` has a failable initializer that returns `nil`
/// unless the hotkey has *both* an app state and a key combination, and only an
/// app state can supply the `HotkeyRegistry` it would register with. So without
/// `performSetup(with:)` the hotkey can never become enabled — which is exactly
/// what makes the rest of the type testable: `enable()` runs end to end and
/// touches nothing global, so every path around it can be driven safely.
///
/// The load-bearing behaviour here is the `keyCombination` `didSet`. It calls
/// `enable()` and then `keyCombinationDidChange?()`, and three owners —
/// `HotkeysSettings`, `MenuBarManager`, and `ProfileManager` — persist the
/// binding from inside that callback. Two properties of it are relied on and
/// otherwise unverified:
///
/// - The value passed to `init` is **not** announced. All three owners set the
///   loaded binding first and install the callback second, precisely so the
///   value just read back off disk is not written straight out again. That
///   ordering is a comment in three files and an assertion in none.
/// - Every later assignment announces **exactly once**, with the new value
///   already stored, including an assignment of `nil`. `HotkeysSettings` reads
///   `hotkey.keyCombination` from inside the callback to decide between writing
///   the binding and deleting the dictionary entry, so a callback that fired
///   before the store, or twice, would either persist the stale binding or
///   leave a dead entry behind.
///
/// Deliberately **not** covered: `performSetup(with:)`, the registration inside
/// `Listener.init`, the action-dispatch closure it installs, and
/// `Listener.invalidate()`. All four need a live `AppState` — and the dispatch
/// closure additionally reaches into `ProfileManager` and `MenuBarManager` — so
/// none can be reached from a unit test. `isEnabled` is therefore asserted only
/// in its `false` state, which is the honest one for a hotkey with no app.
@MainActor
@Suite("Hotkey lifecycle")
struct HotkeyLifecycleTests {
    // MARK: - Helpers

    private static let commandF19 = KeyCombination(key: .f19, modifiers: [.command])
    private static let controlOptionF20 = KeyCombination(key: .f20, modifiers: [.control, .option])
    private static let shiftSpace = KeyCombination(key: .space, modifiers: [.shift])

    /// Records what each announcement saw, so a test can assert the count and
    /// the value the callback would have persisted in one go.
    ///
    /// `KeyCombination` is main-actor isolated like the rest of the app target,
    /// so the recorder is too; the callback only ever runs on the main actor.
    @MainActor
    private final class ChangeRecorder {
        private(set) var observed: [KeyCombination?] = []

        var count: Int { observed.count }

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

        /// Every action has to be bindable; `HotkeysSettings` builds one hotkey
        /// per `settingsActions` entry and `ProfileManager` builds `.profileApply`
        /// hotkeys, so no case may be special-cased out at construction.
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
        /// listener was ever installed, so it has to tolerate being called on a
        /// hotkey that never had one.
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

        #expect(recorder.count == 0)
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

    /// Unbinding is the case that deletes the stored entry rather than
    /// rewriting it, so the clear has to be announced like any other change and
    /// the callback has to see `nil`.
    @Test("Clearing a key combination announces the cleared value")
    func clearingIsAnnounced() {
        let hotkey = Hotkey(action: .enableIceBar, keyCombination: Self.commandF19)
        let recorder = recordChanges(of: hotkey)

        hotkey.keyCombination = nil

        #expect(recorder.observed == [nil])
        #expect(hotkey.keyCombination == nil)
    }

    /// The announcement is an assignment signal, not a change signal: writing
    /// the same binding back announces again. Owners that want change-only
    /// semantics have to compare for themselves.
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

        /// `Hotkey` is a class that compares by value. Two separately built
        /// hotkeys standing for the same binding are the same hotkey.
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
        /// built with — a hotkey rebound by the recorder stops matching its
        /// former twin and starts matching whatever now carries that binding.
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
