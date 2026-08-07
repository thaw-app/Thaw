//
//  DisplaySettingsManagerLookupTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// A display UUID no real display can hold. Seeding `configurations` with it
/// gives every test below one entry whose fate is the same on a laptop, a
/// docked desk, and a headless runner — which is what lets the scope-driven
/// tests assert something even when they also walk `NSScreen`.
private let storedOnlyUUID = "TEST-DISPLAY-UUID-LOOKUP"

/// A display identifier the window server cannot resolve, so
/// `configuration(for:)` has to fall through to the global template.
///
/// The lookup is safe either way: an identifier that unexpectedly *did*
/// resolve would simply have no stored entry and read the template through the
/// other arm, so the assertion holds without depending on what is attached.
private let unresolvableDisplayID = CGDirectDisplayID.max

/// Builds the notification
/// `SettingsURIHandler.postPerDisplaySettingsDidChangeNotification` posts, so
/// the tests drive the same `userInfo` shape production does.
@MainActor
private func perDisplayChange(_ userInfo: [AnyHashable: Any]) -> Notification {
    Notification(name: .perDisplaySettingsDidChangeViaURI, object: nil, userInfo: userInfo)
}

/// Covers the half of ``DisplaySettingsManager`` that its four sibling suites
/// leave alone: what the manager reads out of `Defaults` at construction time,
/// the derived lookups layered on top of `configurations`, and the
/// Settings-URI scope arms the URI suite deliberately skipped.
///
/// Between them the siblings already reach a lot.
/// `DisplaySettingsManagerGlobalFallbackTests` covers `configuration(forUUID:)`
/// and `configurationForActiveDisplay()`; `DisplaySettingsManagerMutationTests`
/// covers `updateConfiguration`, the typed lookups against a *stored* entry,
/// `applyGlobalToAllKnownDisplays`, `allDisplays` ordering and the
/// configuration/global persistence round trips;
/// `DisplaySettingsManagerSpacingGateTests` covers `shouldSkipSpacingApply`;
/// and `DisplaySettingsManagerURINotificationTests` covers `parseScope` plus
/// every `specific:UUID` setter. None of that is repeated here.
///
/// What is left, and what this suite is for:
///
/// - **`loadInitialState`'s failure and side-table branches.** Three separate
///   `do`/`catch` blocks, the empty-name filter over the cached display names,
///   and the two scalar settings (`confirmSpacingRelaunch`,
///   `unconfirmedSpacingProfileScope`) restored at the end. All of it runs from
///   `init`, so every test seeds the scratch store *before* constructing the
///   manager. A decode failure has to leave the property at its default and let
///   the loader carry on to the next key, so each test seeds a second, valid
///   key that the assertion is not about and checks it arrived.
/// - **The derived read surface.** `isIceBarEnabledOnAnyDisplay` and
///   `isAlwaysShowEnabledOnAnyDisplay` read stored entries rather than the
///   template, and the typed per-display lookups fall back to the template for
///   an identifier that resolves to nothing.
/// - **`applyGlobalToAllKnownDisplays`' no-write case.** It only assigns when
///   the new dictionary actually differs, which matters because the assignment
///   is what drives persistence and the spacing re-derivation. Observed by
///   clearing the persisted key and checking it stays cleared.
/// - **The Settings-URI scope arms with no display named.** The URI suite's own
///   doc comment records that it skipped the `active` scope, because a test
///   asserting the resulting mutation would only mean something on a machine
///   with a menu bar. These tests drive those arms and assert what is true
///   either way: the stored-only display is never touched, and any write landed
///   on the active display and nowhere else. The same shape covers the
///   `allEnabled` location broadcast and the `allNonIceBar` toggle, neither of
///   which the URI suite reaches, and every "scope not implemented" arm — each
///   of those paired with a `specific:UUID` control in the same test so
///   "nothing changed" is the scope being refused rather than a dead setter.
///
/// Deliberately **not** covered, because none of it can be driven from a unit
/// test without either a live `AppState` or the machine's own hardware:
/// `performSetup(with:)`, `captureCurrentlyConnectedDisplays`,
/// `seedConfigurationsFromSystemSpacing` (reads `NSStatusItemSpacing` out of
/// the byHost global domain, which no scratch store can redirect),
/// `configureObservers` (a one-second debounce), `applyActiveDisplaySpacing`,
/// and `presentSpacingRelaunchConfirmation` (`NSAlert.runModal`).
///
/// `DisplaySettingsManager.init` reads `Defaults` and its `didSet` observers
/// write back, so every manager here is built inside `withScratchDefaults`.
@MainActor
@Suite("Display settings lookup and loading", .serialized)
struct DisplaySettingsManagerLookupTests {
    // MARK: - Loading persisted state

    @MainActor
    @Suite("Loading persisted state")
    struct LoadingPersistedState {
        /// A per-display table that cannot be decoded must not take the loader
        /// down with it: the global template is read from a different key and
        /// still has to arrive.
        @Test("Unreadable per-display configurations leave the table empty and the load continuing")
        func unreadableConfigurationsAreSurvived() throws {
            try withScratchDefaults { _ in
                Defaults.set(Data("this is not JSON".utf8), forKey: .displayIceBarConfigurations)
                let global = DisplayIceBarConfiguration.defaultConfiguration.withGridColumns(9)
                let globalData = try JSONEncoder().encode(global)
                Defaults.set(globalData, forKey: .globalDisplayConfiguration)

                let manager = DisplaySettingsManager()

                #expect(manager.configurations.isEmpty)
                #expect(manager.globalConfiguration.gridColumns == 9, "the loader must carry on past the failure")
            }
        }

        /// A template that cannot be decoded leaves the hardcoded default in
        /// place. The per-display table is seeded first so the assertion is
        /// about the template rather than about the loader having run at all.
        @Test("An unreadable global template falls back to the hardcoded default")
        func unreadableGlobalTemplateFallsBackToTheDefault() throws {
            try withScratchDefaults { _ in
                let stored = DisplayIceBarConfiguration.defaultConfiguration.withGridColumns(7)
                let storedData = try JSONEncoder().encode([storedOnlyUUID: stored])
                Defaults.set(storedData, forKey: .displayIceBarConfigurations)
                Defaults.set(Data([0x00, 0x01, 0x02]), forKey: .globalDisplayConfiguration)

                let manager = DisplaySettingsManager()

                #expect(manager.configurations[storedOnlyUUID]?.gridColumns == 7, "the loader must have run")
                #expect(manager.globalConfiguration == .defaultConfiguration)
            }
        }

        /// The cache of previously-seen display names is the third and last
        /// decoded key. Its failure has to be as quiet as the other two.
        @Test("An unreadable known-display cache leaves the cache empty")
        func unreadableKnownDisplayCacheIsSurvived() throws {
            try withScratchDefaults { _ in
                let stored = DisplayIceBarConfiguration.defaultConfiguration.withGridColumns(5)
                let storedData = try JSONEncoder().encode([storedOnlyUUID: stored])
                Defaults.set(storedData, forKey: .displayIceBarConfigurations)
                Defaults.set(Data("{ not a cache".utf8), forKey: .knownDisplays)

                let manager = DisplaySettingsManager()

                #expect(manager.knownDisplays.isEmpty)
                #expect(manager.configurations[storedOnlyUUID]?.gridColumns == 5, "the loader must have run")
            }
        }

        @Test("A readable known-display cache is restored entry for entry")
        func knownDisplayCacheRoundTripsThroughTheLoader() throws {
            try withScratchDefaults { _ in
                let cached = [
                    "UUID-Notched": KnownDisplay(name: "Built-in Display", hasNotch: true),
                    "UUID-Plain": KnownDisplay(name: "External Display", hasNotch: false),
                ]
                let cachedData = try JSONEncoder().encode(cached)
                Defaults.set(cachedData, forKey: .knownDisplays)

                let manager = DisplaySettingsManager()

                #expect(manager.knownDisplays.count == 2)
                #expect(manager.knownDisplays["UUID-Notched"] == KnownDisplay(name: "Built-in Display", hasNotch: true))
                #expect(manager.knownDisplays["UUID-Plain"] == KnownDisplay(name: "External Display", hasNotch: false))
            }
        }

        /// A mirrored slave or a display caught mid-sleep can be cached with a
        /// blank name. Those entries would render as anonymous rows in the
        /// Displays pane, so the loader drops them — and only them.
        @Test("Cached entries with a blank name are dropped as the cache is loaded")
        func blankNamedCacheEntriesAreDroppedOnLoad() throws {
            try withScratchDefaults { _ in
                let cached = [
                    "UUID-Empty": KnownDisplay(name: "", hasNotch: false),
                    "UUID-Spaces": KnownDisplay(name: "   ", hasNotch: true),
                    "UUID-Named": KnownDisplay(name: "External Display", hasNotch: false),
                ]
                let cachedData = try JSONEncoder().encode(cached)
                Defaults.set(cachedData, forKey: .knownDisplays)

                let manager = DisplaySettingsManager()

                #expect(Set(manager.knownDisplays.keys) == ["UUID-Named"])
                #expect(manager.knownDisplays["UUID-Named"]?.name == "External Display")
            }
        }

        @Test("An absent relaunch-confirmation setting keeps the shipped default")
        func absentConfirmSpacingRelaunchKeepsTheDefault() throws {
            try withScratchDefaults { _ in
                #expect(DisplaySettingsManager().confirmSpacingRelaunch == Defaults.DefaultValue.confirmSpacingRelaunch)
            }
        }

        @Test("A persisted relaunch-confirmation setting is restored", arguments: [true, false])
        func persistedConfirmSpacingRelaunchIsRestored(_ value: Bool) throws {
            try withScratchDefaults { _ in
                Defaults.set(value, forKey: .confirmSpacingRelaunch)

                #expect(DisplaySettingsManager().confirmSpacingRelaunch == value)
            }
        }

        @Test("A persisted spacing profile scope is restored", arguments: ["activeProfile", "allProfiles"])
        func persistedSpacingProfileScopeIsRestored(_ raw: String) throws {
            try withScratchDefaults { _ in
                Defaults.set(raw, forKey: .unconfirmedSpacingProfileScope)

                #expect(DisplaySettingsManager().unconfirmedSpacingProfileScope.rawValue == raw)
            }
        }

        /// A stored scope string the enumeration cannot name is ignored rather
        /// than allowed to leave the property in some in-between state. The
        /// relaunch-confirmation flag is seeded alongside it so the assertion
        /// cannot pass merely because nothing was loaded at all.
        @Test("A spacing profile scope the enumeration cannot name is ignored", arguments: ["", "everyProfile", "ACTIVEPROFILE"])
        func unrecognisedSpacingProfileScopeIsIgnored(_ raw: String) throws {
            try withScratchDefaults { _ in
                Defaults.set(raw, forKey: .unconfirmedSpacingProfileScope)
                Defaults.set(false, forKey: .confirmSpacingRelaunch)

                let manager = DisplaySettingsManager()

                #expect(manager.unconfirmedSpacingProfileScope == Defaults.DefaultValue.unconfirmedSpacingProfileScope)
                #expect(!manager.confirmSpacingRelaunch, "the rest of the load must still have happened")
            }
        }
    }

    // MARK: - Persisting the scalar settings

    @MainActor
    @Suite("Persisting the scalar settings")
    struct PersistingScalarSettings {
        @Test("The relaunch-confirmation flag is written through and survives a reload")
        func confirmSpacingRelaunchRoundTrips() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.confirmSpacingRelaunch = false

                #expect(Defaults.object(forKey: .confirmSpacingRelaunch) as? Bool == false)
                #expect(!DisplaySettingsManager().confirmSpacingRelaunch)
            }
        }

        @Test("The spacing profile scope is written through and survives a reload")
        func unconfirmedSpacingProfileScopeRoundTrips() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.unconfirmedSpacingProfileScope = .allProfiles

                #expect(Defaults.string(forKey: .unconfirmedSpacingProfileScope) == "allProfiles")
                #expect(DisplaySettingsManager().unconfirmedSpacingProfileScope == .allProfiles)
            }
        }

        /// Re-assigning the value a property already holds must not persist
        /// again. Observed by clearing the key underneath and checking the
        /// redundant assignment does not put it back.
        @Test("Re-assigning the same scalar value does not write again")
        func redundantScalarAssignmentDoesNotPersist() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.unconfirmedSpacingProfileScope = .allProfiles
                manager.confirmSpacingRelaunch = false
                #expect(Defaults.string(forKey: .unconfirmedSpacingProfileScope) == "allProfiles")

                Defaults.removeObject(forKey: .unconfirmedSpacingProfileScope)
                Defaults.removeObject(forKey: .confirmSpacingRelaunch)
                manager.unconfirmedSpacingProfileScope = .allProfiles
                manager.confirmSpacingRelaunch = false

                #expect(Defaults.string(forKey: .unconfirmedSpacingProfileScope) == nil)
                #expect(Defaults.object(forKey: .confirmSpacingRelaunch) as? Bool == nil)
            }
        }

        @Test("The known-display cache is written through and survives a reload")
        func knownDisplaysRoundTrip() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.knownDisplays = ["UUID-Alpha": KnownDisplay(name: "Alpha", hasNotch: true)]

                let data = try #require(Defaults.data(forKey: .knownDisplays))
                let decoded = try JSONDecoder().decode([String: KnownDisplay].self, from: data)
                #expect(decoded["UUID-Alpha"] == KnownDisplay(name: "Alpha", hasNotch: true))
                #expect(DisplaySettingsManager().knownDisplays["UUID-Alpha"]?.hasNotch == true)
            }
        }

        @Test("Re-assigning the same known-display cache does not write again")
        func redundantKnownDisplaysAssignmentDoesNotPersist() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                let cache = ["UUID-Alpha": KnownDisplay(name: "Alpha", hasNotch: false)]
                manager.knownDisplays = cache
                #expect(Defaults.data(forKey: .knownDisplays) != nil)

                Defaults.removeObject(forKey: .knownDisplays)
                manager.knownDisplays = cache

                #expect(Defaults.data(forKey: .knownDisplays) == nil)
            }
        }
    }

    // MARK: - Derived lookups

    @MainActor
    @Suite("Derived lookups")
    struct DerivedLookups {
        /// The two predicates answer for the *stored* displays. A template that
        /// says yes to both is seeded first, so a predicate that read the
        /// template instead would answer yes here and fail.
        @Test("An empty configuration table enables nothing, whatever the template says")
        func emptyConfigurationsEnableNothing() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.globalConfiguration = .defaultConfiguration
                    .withUseIceBar(true)
                    .withAlwaysShowHiddenItems(true)
                manager.configurations = [:]

                #expect(!manager.isIceBarEnabledOnAnyDisplay)
                #expect(!manager.isAlwaysShowEnabledOnAnyDisplay)
            }
        }

        /// Each predicate reads its own field, so the display that turns one of
        /// them on must leave the other off.
        @Test("One display with the Thaw Bar on answers for the whole set")
        func oneBarEnabledDisplayIsEnough() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.globalConfiguration = .defaultConfiguration
                manager.configurations = [
                    "UUID-A": .defaultConfiguration,
                    "UUID-B": .defaultConfiguration.withUseIceBar(true),
                    "UUID-C": .defaultConfiguration,
                ]

                #expect(manager.isIceBarEnabledOnAnyDisplay)
                #expect(!manager.isAlwaysShowEnabledOnAnyDisplay, "the two predicates read different fields")
            }
        }

        @Test("One display always showing hidden items answers for the whole set")
        func oneAlwaysShowDisplayIsEnough() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.globalConfiguration = .defaultConfiguration
                manager.configurations = [
                    "UUID-A": .defaultConfiguration,
                    "UUID-B": .defaultConfiguration.withAlwaysShowHiddenItems(true),
                    "UUID-C": .defaultConfiguration,
                ]

                #expect(manager.isAlwaysShowEnabledOnAnyDisplay)
                #expect(!manager.isIceBarEnabledOnAnyDisplay, "the two predicates read different fields")
            }
        }

        /// Stored entries that differ from the default in every *other* field
        /// still have to answer no, so the predicates cannot be passing on the
        /// mere presence of an entry.
        @Test("Displays that turn neither setting on answer no")
        func configuredButUninterestingDisplaysAnswerNo() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.globalConfiguration = .defaultConfiguration
                manager.configurations = [
                    "UUID-A": .defaultConfiguration.withIceBarLayout(.grid).withGridColumns(8),
                    "UUID-B": .defaultConfiguration.withIceBarLocation(.rightAligned).withItemSpacingOffset(-9),
                ]

                #expect(!manager.isIceBarEnabledOnAnyDisplay)
                #expect(!manager.isAlwaysShowEnabledOnAnyDisplay)
            }
        }

        /// Every field of the template differs from `.defaultConfiguration`, so
        /// a lookup that quietly returned the hardcoded default rather than the
        /// user's template would fail on all six.
        @Test("Every typed lookup falls back to the template for an unresolvable display")
        func typedLookupsFallBackToTheTemplate() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.globalConfiguration = .defaultConfiguration
                    .withUseIceBar(true)
                    .withIceBarLocation(.rightAligned)
                    .withAlwaysShowHiddenItems(true)
                    .withUseThawBarForAlwaysHidden(true)
                    .withIceBarLayout(.grid)
                    .withGridColumns(9)
                manager.configurations = [:]

                #expect(manager.useIceBar(for: unresolvableDisplayID))
                #expect(manager.iceBarLocation(for: unresolvableDisplayID) == .rightAligned)
                #expect(manager.alwaysShowHiddenItems(for: unresolvableDisplayID))
                #expect(manager.useThawBarForAlwaysHidden(for: unresolvableDisplayID))
                #expect(manager.iceBarLayout(for: unresolvableDisplayID) == .grid)
                #expect(manager.gridColumns(for: unresolvableDisplayID) == 9)
            }
        }

        @Test("An unresolvable display reads the whole template, not the shipped default")
        func unresolvableDisplayReadsTheTemplate() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                let template = DisplayIceBarConfiguration.defaultConfiguration.withItemSpacingOffset(-11)
                manager.globalConfiguration = template
                manager.configurations = [storedOnlyUUID: .defaultConfiguration.withItemSpacingOffset(4)]

                #expect(manager.configuration(for: unresolvableDisplayID) == template)
                #expect(manager.configuration(for: unresolvableDisplayID).itemSpacingOffset == -11)
            }
        }

        /// The property exists so views can decide whether a spacing edit will
        /// fire the relaunch wave. It has to read the window server rather than
        /// the last-applied bookkeeping field, which is seeded here with a
        /// value that could never be a real display UUID.
        @Test("The active display identifier comes from the window server, not the last-applied field")
        func activeDisplayUUIDComesFromTheWindowServer() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.lastAppliedActiveDisplayUUID = "UUID-SENTINEL-NEVER-ACTIVE"

                #expect(manager.activeMenuBarDisplayUUID == Bridging.getActiveMenuBarDisplayUUID())
                #expect(manager.activeMenuBarDisplayUUID != "UUID-SENTINEL-NEVER-ACTIVE")
            }
        }
    }

    // MARK: - Broadcasting the template

    @MainActor
    @Suite("Broadcasting the template")
    struct BroadcastingTheTemplate {
        /// The assignment to `configurations` is what drives persistence and
        /// the spacing re-derivation, so a broadcast that would change nothing
        /// has to skip it. Observed by clearing the persisted key first: if the
        /// broadcast assigned, the `didSet` would put it straight back.
        @Test("A broadcast that would change nothing does not write")
        func redundantBroadcastDoesNotWrite() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.globalConfiguration = .defaultConfiguration.withGridColumns(6).withItemSpacingOffset(-7)
                manager.knownDisplays = ["UUID-Alpha": KnownDisplay(name: "Alpha", hasNotch: false)]

                var alreadyMatching: [String: DisplayIceBarConfiguration] = [:]
                for display in manager.allDisplays() {
                    alreadyMatching[display.id] = manager.globalConfiguration
                }
                manager.configurations = alreadyMatching
                Defaults.removeObject(forKey: .displayIceBarConfigurations)

                let targets = manager.applyGlobalToAllKnownDisplays()

                #expect(targets.contains("UUID-Alpha"), "the display is still reported as a target")
                #expect(manager.configurations == alreadyMatching)
                #expect(
                    Defaults.data(forKey: .displayIceBarConfigurations) == nil,
                    "a broadcast that changes nothing must not re-persist"
                )
            }
        }

        /// The contrast case, so the test above cannot be passing because the
        /// broadcast never writes at all.
        @Test("A broadcast that does change something writes once")
        func changingBroadcastWrites() throws {
            try withScratchDefaults { _ in
                let manager = DisplaySettingsManager()
                manager.globalConfiguration = .defaultConfiguration.withGridColumns(6).withItemSpacingOffset(-7)
                manager.knownDisplays = ["UUID-Alpha": KnownDisplay(name: "Alpha", hasNotch: false)]
                manager.configurations = ["UUID-Alpha": .defaultConfiguration]
                Defaults.removeObject(forKey: .displayIceBarConfigurations)

                let targets = manager.applyGlobalToAllKnownDisplays()

                #expect(targets.contains("UUID-Alpha"))
                #expect(manager.configurations["UUID-Alpha"] == manager.globalConfiguration)
                let data = try #require(Defaults.data(forKey: .displayIceBarConfigurations))
                let decoded = try JSONDecoder().decode([String: DisplayIceBarConfiguration].self, from: data)
                #expect(decoded["UUID-Alpha"]?.gridColumns == 6)
            }
        }
    }

    // MARK: - Settings-URI changes that name no display

    /// The arms `DisplaySettingsManagerURINotificationTests` records as
    /// deliberately skipped, driven here in a way that does not depend on what
    /// is plugged in.
    ///
    /// Two invariants make that possible. First, ``storedOnlyUUID`` is in
    /// `configurations` but can never be attached, so "the request did not
    /// reach it" is the same claim on every machine. Second, the manager's own
    /// `activeMenuBarDisplayUUID` says whether there is an active display at
    /// all, which lets each test state the right expectation for the machine it
    /// is running on rather than assuming one.
    @MainActor
    @Suite("Settings-URI changes that name no display")
    struct ChangesThatNameNoDisplay {
        private func makeManager(
            global: DisplayIceBarConfiguration,
            stored: DisplayIceBarConfiguration
        ) -> DisplaySettingsManager {
            let manager = DisplaySettingsManager()
            manager.globalConfiguration = global
            manager.configurations = [storedOnlyUUID: stored]
            return manager
        }

        @Test("A useIceBar set that names no display reaches the active display and nothing else")
        func activeScopeUseIceBarSet() throws {
            try withScratchDefaults { _ in
                let manager = makeManager(global: .defaultConfiguration, stored: .defaultConfiguration)
                let activeUUID = manager.activeMenuBarDisplayUUID

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(["key": "useIceBar", "scope": "active", "value": true])
                )

                #expect(
                    manager.configurations[storedOnlyUUID] == .defaultConfiguration,
                    "a stored display the request did not name must not be written"
                )
                if let activeUUID {
                    #expect(manager.configurations[activeUUID]?.useIceBar == true)
                    #expect(Set(manager.configurations.keys) == [storedOnlyUUID, activeUUID])
                } else {
                    #expect(Set(manager.configurations.keys) == [storedOnlyUUID])
                }
            }
        }

        /// The toggle arm resolves its target the same way, and flips whatever
        /// the display currently reads — which, with no stored entry, is the
        /// template. Seeding the template with the bar off makes the expected
        /// result unambiguous.
        @Test("A useIceBar toggle that names no display reaches the active display and nothing else")
        func activeScopeUseIceBarToggle() throws {
            try withScratchDefaults { _ in
                let manager = makeManager(
                    global: .defaultConfiguration.withUseIceBar(false),
                    stored: .defaultConfiguration.withUseIceBar(false)
                )
                let activeUUID = manager.activeMenuBarDisplayUUID

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(["key": "useIceBar", "scope": "active", "toggle": true])
                )

                #expect(manager.configurations[storedOnlyUUID]?.useIceBar == false)
                if let activeUUID {
                    #expect(manager.configurations[activeUUID]?.useIceBar == true)
                    #expect(Set(manager.configurations.keys) == [storedOnlyUUID, activeUUID])
                } else {
                    #expect(Set(manager.configurations.keys) == [storedOnlyUUID])
                }
            }
        }

        /// The location broadcast walks the attached screens, not the stored
        /// table. The stored-only display is given the bar *on* here, so it
        /// would qualify if the walk went through `configurations` — which is
        /// exactly the mistake the assertion catches.
        @Test("A location broadcast reaches the attached displays but never a stored-only one")
        func allEnabledScopeLocationBroadcast() throws {
            try withScratchDefaults { _ in
                let manager = makeManager(
                    global: .defaultConfiguration.withUseIceBar(true),
                    stored: .defaultConfiguration.withUseIceBar(true)
                )
                let connected = manager.connectedDisplays().map(\.id)

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange([
                        "key": "iceBarLocation",
                        "scope": "allEnabled",
                        "stringValue": String(IceBarLocation.mousePointer.rawValue),
                    ])
                )

                #expect(
                    manager.configurations[storedOnlyUUID]?.iceBarLocation == .dynamic,
                    "the broadcast walks attached screens, so a stored-only display is out of reach"
                )
                for uuid in connected {
                    #expect(manager.configurations[uuid]?.iceBarLocation == .mousePointer, "\(uuid)")
                }
            }
        }

        /// The "always show" toggle broadcast is the mirror image: it walks the
        /// attached screens and picks the ones *without* the bar. The
        /// stored-only display has the bar off, so it too would qualify if the
        /// walk read the stored table.
        @Test("An always-show toggle broadcast reaches the attached displays but never a stored-only one")
        func allNonIceBarScopeAlwaysShowToggle() throws {
            try withScratchDefaults { _ in
                let manager = makeManager(global: .defaultConfiguration, stored: .defaultConfiguration)
                let connected = manager.connectedDisplays().map(\.id)

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(["key": "alwaysShowHiddenItems", "scope": "allNonIceBar", "toggle": true])
                )

                #expect(manager.configurations[storedOnlyUUID]?.alwaysShowHiddenItems == false)
                for uuid in connected {
                    #expect(manager.configurations[uuid]?.alwaysShowHiddenItems == true, "\(uuid)")
                }
            }
        }

        @Test("A location change under a scope the setter does not implement changes nothing")
        func locationIgnoresUnimplementedScopes() throws {
            try withScratchDefaults { _ in
                let manager = makeManager(
                    global: .defaultConfiguration.withUseIceBar(true),
                    stored: .defaultConfiguration.withUseIceBar(true)
                )
                let before = manager.configurations
                let payload: [AnyHashable: Any] = [
                    "key": "iceBarLocation",
                    "stringValue": String(IceBarLocation.rightAligned.rawValue),
                ]

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "active"]) { _, new in new })
                )
                #expect(manager.configurations == before)

                // Control: the same payload does land when the request names a
                // display, so "nothing changed" above is the scope being
                // refused rather than a setter that never works.
                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "specific:\(storedOnlyUUID)"]) { _, new in new })
                )
                #expect(manager.configurations[storedOnlyUUID]?.iceBarLocation == .rightAligned)
            }
        }

        @Test("A layout change under a scope the setter does not implement changes nothing")
        func layoutIgnoresUnimplementedScopes() throws {
            try withScratchDefaults { _ in
                let manager = makeManager(
                    global: .defaultConfiguration.withUseIceBar(true),
                    stored: .defaultConfiguration.withUseIceBar(true)
                )
                let before = manager.configurations
                let payload: [AnyHashable: Any] = ["key": "iceBarLayout", "stringValue": "vertical"]

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "active"]) { _, new in new })
                )
                #expect(manager.configurations == before)

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "specific:\(storedOnlyUUID)"]) { _, new in new })
                )
                #expect(manager.configurations[storedOnlyUUID]?.iceBarLayout == .vertical)
            }
        }

        @Test("A column-count change under a scope the setter does not implement changes nothing")
        func gridColumnsIgnoresUnimplementedScopes() throws {
            try withScratchDefaults { _ in
                let manager = makeManager(
                    global: .defaultConfiguration.withUseIceBar(true),
                    stored: .defaultConfiguration.withUseIceBar(true)
                )
                let before = manager.configurations
                let payload: [AnyHashable: Any] = ["key": "gridColumns", "stringValue": "7"]

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "active"]) { _, new in new })
                )
                #expect(manager.configurations == before)

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "specific:\(storedOnlyUUID)"]) { _, new in new })
                )
                #expect(manager.configurations[storedOnlyUUID]?.gridColumns == 7)
            }
        }

        @Test("An always-show set under a scope the setter does not implement changes nothing")
        func alwaysShowSetIgnoresUnimplementedScopes() throws {
            try withScratchDefaults { _ in
                let manager = makeManager(global: .defaultConfiguration, stored: .defaultConfiguration)
                let before = manager.configurations
                let payload: [AnyHashable: Any] = ["key": "alwaysShowHiddenItems", "value": true]

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "active"]) { _, new in new })
                )
                #expect(manager.configurations == before)

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "specific:\(storedOnlyUUID)"]) { _, new in new })
                )
                #expect(manager.configurations[storedOnlyUUID]?.alwaysShowHiddenItems == true)
            }
        }

        @Test("An always-show toggle under a scope the toggler does not implement changes nothing")
        func alwaysShowToggleIgnoresUnimplementedScopes() throws {
            try withScratchDefaults { _ in
                let manager = makeManager(global: .defaultConfiguration, stored: .defaultConfiguration)
                let before = manager.configurations
                let payload: [AnyHashable: Any] = ["key": "alwaysShowHiddenItems", "toggle": true]

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "active"]) { _, new in new })
                )
                #expect(manager.configurations == before)

                manager.handleExternalPerDisplaySettingsChange(
                    perDisplayChange(payload.merging(["scope": "specific:\(storedOnlyUUID)"]) { _, new in new })
                )
                #expect(manager.configurations[storedOnlyUUID]?.alwaysShowHiddenItems == true)
            }
        }
    }

    // MARK: - Codable round trips

    @MainActor
    @Suite("Codable round trips")
    struct CodableRoundTrips {
        /// The cache is what keeps a disconnected display editable in the
        /// Displays pane, so both fields have to survive the round trip — the
        /// notch flag especially, since it decides how the pane renders.
        @Test("A cached display survives a round trip through JSON")
        func knownDisplayRoundTrips() throws {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            for original in [
                KnownDisplay(name: "Built-in Retina Display", hasNotch: true),
                KnownDisplay(name: "External Display", hasNotch: false),
            ] {
                let decoded = try decoder.decode(KnownDisplay.self, from: encoder.encode(original))
                #expect(decoded == original)
                #expect(decoded.name == original.name)
                #expect(decoded.hasNotch == original.hasNotch)
            }
        }

        @Test("Two cached displays differing only in the notch flag are not equal")
        func knownDisplayEqualityReadsBothFields() {
            #expect(KnownDisplay(name: "Alpha", hasNotch: true) != KnownDisplay(name: "Alpha", hasNotch: false))
            #expect(KnownDisplay(name: "Alpha", hasNotch: true) != KnownDisplay(name: "Beta", hasNotch: true))
            #expect(KnownDisplay(name: "Alpha", hasNotch: true) == KnownDisplay(name: "Alpha", hasNotch: true))
        }

        /// The scope is persisted as its raw string, so the encoded form is
        /// part of the on-disk contract and not just an implementation detail.
        @Test("Every spacing profile scope survives a round trip through JSON")
        func spacingProfileSaveScopeRoundTrips() throws {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            for original in SpacingProfileSaveScope.allCases {
                let data = try encoder.encode(original)
                let decoded = try decoder.decode(SpacingProfileSaveScope.self, from: data)
                #expect(String(data: data, encoding: .utf8) == "\"\(original.rawValue)\"")
                #expect(decoded == original)
            }
        }

        @Test("The spacing profile scope names exactly the two destinations it offers")
        func spacingProfileSaveScopeNamesBothDestinations() {
            #expect(SpacingProfileSaveScope.allCases.map(\.rawValue) == ["activeProfile", "allProfiles"])
            #expect(SpacingProfileSaveScope(rawValue: "activeProfile") == .activeProfile)
            #expect(SpacingProfileSaveScope(rawValue: "allProfiles") == .allProfiles)
            #expect(SpacingProfileSaveScope(rawValue: "everyProfile") == nil)
        }
    }
}
