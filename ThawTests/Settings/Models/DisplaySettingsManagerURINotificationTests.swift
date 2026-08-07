//
//  DisplaySettingsManagerURINotificationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// A display UUID no real display can hold. Seeding `configurations` with it
/// satisfies the `hasConfig` half of the handler's validation guard, which is
/// what makes the whole `specific:UUID` branch reachable without a second
/// monitor plugged in.
private let offscreenUUID = "TEST-DISPLAY-UUID-A"

/// Builds the notification `SettingsURIHandler.postPerDisplaySettingsDidChangeNotification`
/// posts, so the tests exercise the same `userInfo` shape production does.
@MainActor
private func perDisplayChange(_ userInfo: [AnyHashable: Any]) -> Notification {
    Notification(name: .perDisplaySettingsDidChangeViaURI, object: nil, userInfo: userInfo)
}

/// Covers the Settings-URI side of ``DisplaySettingsManager``: `parseScope`
/// and `handleExternalPerDisplaySettingsChange`.
///
/// Both are internal purely so this suite exists. Driving the handler with a
/// hand-built `Notification` skips `performSetup(with:)`, which needs a live
/// `AppState` and installs a one-second debounced observer — neither is
/// available or deterministic in a unit test.
///
/// The pivot is that a `specific:UUID` scope reaches every setter without ever
/// consulting `NSScreen`, as long as `configurations` already holds that UUID.
/// So every setter, clamp, and parse-failure path is asserted against
/// ``offscreenUUID``, and the result is identical on a laptop, a docked desk,
/// and a headless CI runner.
///
/// Deliberately **not** covered:
///
/// - The `active` scope's write path (`setUseIceBar(_:forActiveDisplay:)` and
///   `toggleIceBarForActiveDisplay`). Both resolve their target through
///   `Bridging.getActiveMenuBarDisplayUUID()`, so a test asserting a mutation
///   would pass only on a machine with a menu bar and would assert nothing
///   about the code under test on one without.
/// - The relaunch/spacing consequences of a change. `configurations`' `didSet`
///   calls `applyActiveDisplaySpacing`, which returns immediately while
///   `appState` is `nil`; `DisplaySettingsManagerSpacingGateTests` covers that
///   gate separately.
///
/// The scope-wide broadcasts (`allEnabled`, `allNonIceBar`) do walk
/// `NSScreen.screens`, so they are asserted two ways: over whatever displays
/// happen to be attached (vacuously true when there are none) and, in every
/// case, that the broadcast never reaches ``offscreenUUID``.
///
/// `DisplaySettingsManager.init` reads `Defaults`, and its `didSet` observers
/// write back, so every manager is built inside `withScratchDefaults`.
@MainActor
@Suite("Display settings URI notifications", .serialized)
struct DisplaySettingsManagerURINotificationTests {
    /// Builds a manager whose only configured display is `uuid`, on top of a
    /// known-default global. Wiping `configurations` matters: it puts every
    /// genuinely connected display back on the global template, so the
    /// scope-wide tests below start from a state the machine cannot vary.
    private func makeManager(
        _ configuration: DisplayIceBarConfiguration = .defaultConfiguration,
        uuid: String = offscreenUUID
    ) -> DisplaySettingsManager {
        let manager = DisplaySettingsManager()
        manager.globalConfiguration = .defaultConfiguration
        manager.configurations = [uuid: configuration]
        return manager
    }

    // MARK: Scope parsing

    /// Asserted as a round-trip through `PerDisplayScope.rawValue`, which is
    /// the encoding `SettingsURIHandler` posts. That ties the parse to the
    /// producer rather than to a hand-copied table that could drift with it.
    @Test("Each plain scope string round-trips to its own case", arguments: [
        "active",
        "allEnabled",
        "allNonIceBar",
    ])
    func plainScopeParsing(raw: String) {
        let (scope, uuid) = DisplaySettingsManager.parseScope(from: raw)

        #expect(scope.rawValue == raw, "the parsed case must be the one that spells itself \(raw)")
        #expect(uuid == nil, "a plain scope names no display")
    }

    /// Matching is exact and case-sensitive, and anything unrecognised is
    /// treated as `active` rather than rejected. That is the part worth
    /// pinning: an unknown scope must not silently become a UUID.
    @Test("An unrecognised scope falls back to the active display", arguments: [
        "",
        "specific",
        "specifi:ABC",
        "ACTIVE",
        "allenabled",
        "allNonIceBarDisplays",
        " active",
        "nonsense",
    ])
    func unrecognisedScopeParsing(raw: String) {
        let (scope, uuid) = DisplaySettingsManager.parseScope(from: raw)

        #expect(scope == .activeDisplay)
        #expect(uuid == nil, "an unrecognised scope must not invent a display UUID")
    }

    /// Everything after the first `specific:` is the UUID, verbatim — the
    /// prefix is stripped by length, not split on `:`. A UUID that itself
    /// contains a colon therefore survives intact.
    @Test("A specific scope carries everything after the prefix as the UUID", arguments: [
        ("specific:ABC-123", "ABC-123"),
        ("specific:", ""),
        ("specific:AB:CD", "AB:CD"),
        ("specific:specific:X", "specific:X"),
        ("specific: ", " "),
    ])
    func specificScopeParsing(raw: String, expected: String) {
        let (scope, uuid) = DisplaySettingsManager.parseScope(from: raw)

        #expect(uuid == expected)
        #expect(
            scope == .activeDisplay,
            "the returned case is a placeholder for a specific scope; the UUID picks the target"
        )
    }

    // MARK: Notification guards

    @Test("A notification with no userInfo changes nothing")
    func notificationWithoutUserInfoIsIgnored() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            let before = manager.configurations

            manager.handleExternalPerDisplaySettingsChange(
                Notification(name: .perDisplaySettingsDidChangeViaURI)
            )

            #expect(manager.configurations == before)
        }
    }

    @Test("A notification without a key changes nothing")
    func notificationWithoutKeyIsIgnored() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            let before = manager.configurations

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "scope": "specific:\(offscreenUUID)",
                "value": true,
            ]))

            #expect(manager.configurations == before)
        }
    }

    @Test("A notification without a scope changes nothing")
    func notificationWithoutScopeIsIgnored() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            let before = manager.configurations

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useIceBar",
                "value": true,
            ]))

            #expect(manager.configurations == before)
        }
    }

    /// `userInfo` is `[AnyHashable: Any]`, so a sender can put anything under
    /// `key` or `scope`. Both are read with `as? String` and must bail rather
    /// than trap.
    @Test("A key or scope of the wrong type changes nothing")
    func notificationWithMistypedFieldsIsIgnored() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            let before = manager.configurations

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": 7,
                "scope": "specific:\(offscreenUUID)",
                "value": true,
            ]))
            #expect(manager.configurations == before, "a non-string key")

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useIceBar",
                "scope": 7,
                "value": true,
            ]))
            #expect(manager.configurations == before, "a non-string scope")
        }
    }

    /// `autoRehide` is a real setting, just not a per-display one, so it
    /// reaches the switch and falls through to `default`.
    @Test("A key that is not a per-display setting changes nothing", arguments: [
        "autoRehide",
        "itemSpacingOffset",
        "",
        "USEICEBAR",
    ])
    func unrecognisedKeyIsIgnored(key: String) throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            let before = manager.configurations

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": key,
                "scope": "specific:\(offscreenUUID)",
                "value": true,
                "stringValue": "3",
            ]))

            #expect(manager.configurations == before)
        }
    }

    /// The defence-in-depth guard: a UUID that is neither attached nor already
    /// configured is dropped, so a stray URI cannot conjure configuration
    /// entries for displays that do not exist.
    @Test("A specific scope for an unknown display changes nothing", arguments: [
        "TEST-DISPLAY-UUID-UNKNOWN",
        "",
        " ",
    ])
    func unknownSpecificUUIDIsRejected(uuid: String) throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            let before = manager.configurations

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useIceBar",
                "scope": "specific:\(uuid)",
                "value": true,
            ]))

            #expect(manager.configurations == before)
            #expect(manager.configurations[uuid] == nil, "no entry may be created for an unknown display")
        }
    }

    /// A colon inside the UUID must not split the target: the entry keyed
    /// `AB:CD` is the one that changes.
    @Test("A UUID containing a colon still resolves to its own entry")
    func specificUUIDContainingAColonResolves() throws {
        try withScratchDefaults { _ in
            let manager = makeManager(uuid: "AB:CD")

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useIceBar",
                "scope": "specific:AB:CD",
                "value": true,
            ]))

            #expect(manager.configurations["AB:CD"]?.useIceBar == true)
            #expect(manager.configurations["AB"] == nil)
        }
    }

    // MARK: useIceBar

    @Test("A useIceBar value is written to the named display", arguments: [true, false])
    func useIceBarValueIsApplied(value: Bool) throws {
        try withScratchDefaults { _ in
            let manager = makeManager(.defaultConfiguration.withUseIceBar(!value))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useIceBar",
                "scope": "specific:\(offscreenUUID)",
                "value": value,
            ]))

            #expect(manager.configurations[offscreenUUID]?.useIceBar == value)
        }
    }

    @Test("A useIceBar toggle flips the named display", arguments: [true, false])
    func useIceBarToggleFlipsTheDisplay(initial: Bool) throws {
        try withScratchDefaults { _ in
            let manager = makeManager(.defaultConfiguration.withUseIceBar(initial))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useIceBar",
                "scope": "specific:\(offscreenUUID)",
                "toggle": true,
            ]))

            #expect(manager.configurations[offscreenUUID]?.useIceBar == !initial)
        }
    }

    /// The handler branches on `toggle == true`, not on `toggle` being
    /// present. A sender that spells out `toggle: false` alongside a value
    /// must get the value, not a flip.
    @Test("A false toggle alongside a value applies the value, not a flip", arguments: [true, false])
    func falseToggleFallsThroughToTheValue(value: Bool) throws {
        try withScratchDefaults { _ in
            // Seeding with the value being sent makes the two branches
            // distinguishable: applying the value is a no-op here, whereas
            // taking the toggle branch would invert it.
            let manager = makeManager(.defaultConfiguration.withUseIceBar(value))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useIceBar",
                "scope": "specific:\(offscreenUUID)",
                "toggle": false,
                "value": value,
            ]))

            #expect(manager.configurations[offscreenUUID]?.useIceBar == value)
        }
    }

    @Test("A useIceBar notification with neither a toggle nor a Bool value changes nothing")
    func useIceBarWithoutAUsablePayloadIsIgnored() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            let before = manager.configurations

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useIceBar",
                "scope": "specific:\(offscreenUUID)",
            ]))
            #expect(manager.configurations == before, "no payload at all")

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useIceBar",
                "scope": "specific:\(offscreenUUID)",
                "value": "true",
            ]))
            #expect(manager.configurations == before, "a stringly-typed value")
        }
    }

    // MARK: useThawBarForAlwaysHidden

    @Test("A useThawBarForAlwaysHidden value is written to the named display", arguments: [true, false])
    func useThawBarForAlwaysHiddenValueIsApplied(value: Bool) throws {
        try withScratchDefaults { _ in
            let manager = makeManager(.defaultConfiguration.withUseThawBarForAlwaysHidden(!value))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useThawBarForAlwaysHidden",
                "scope": "specific:\(offscreenUUID)",
                "value": value,
            ]))

            #expect(manager.configurations[offscreenUUID]?.useThawBarForAlwaysHidden == value)
        }
    }

    @Test("A useThawBarForAlwaysHidden toggle flips the named display", arguments: [true, false])
    func useThawBarForAlwaysHiddenToggleFlipsTheDisplay(initial: Bool) throws {
        try withScratchDefaults { _ in
            let manager = makeManager(.defaultConfiguration.withUseThawBarForAlwaysHidden(initial))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useThawBarForAlwaysHidden",
                "scope": "specific:\(offscreenUUID)",
                "toggle": true,
            ]))

            #expect(manager.configurations[offscreenUUID]?.useThawBarForAlwaysHidden == !initial)
        }
    }

    @Test("A useThawBarForAlwaysHidden notification with no usable payload changes nothing")
    func useThawBarForAlwaysHiddenWithoutAUsablePayloadIsIgnored() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            let before = manager.configurations

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useThawBarForAlwaysHidden",
                "scope": "specific:\(offscreenUUID)",
            ]))
            #expect(manager.configurations == before, "no payload at all")

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "useThawBarForAlwaysHidden",
                "scope": "specific:\(offscreenUUID)",
                "value": "true",
            ]))
            #expect(manager.configurations == before, "a stringly-typed value")
        }
    }

    // MARK: alwaysShowHiddenItems

    @Test("An alwaysShowHiddenItems value is written to the named display", arguments: [true, false])
    func alwaysShowHiddenItemsValueIsApplied(value: Bool) throws {
        try withScratchDefaults { _ in
            let manager = makeManager(.defaultConfiguration.withAlwaysShowHiddenItems(!value))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "alwaysShowHiddenItems",
                "scope": "specific:\(offscreenUUID)",
                "value": value,
            ]))

            #expect(manager.configurations[offscreenUUID]?.alwaysShowHiddenItems == value)
        }
    }

    @Test("An alwaysShowHiddenItems toggle flips the named display", arguments: [true, false])
    func alwaysShowHiddenItemsToggleFlipsTheDisplay(initial: Bool) throws {
        try withScratchDefaults { _ in
            let manager = makeManager(.defaultConfiguration.withAlwaysShowHiddenItems(initial))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "alwaysShowHiddenItems",
                "scope": "specific:\(offscreenUUID)",
                "toggle": true,
            ]))

            #expect(manager.configurations[offscreenUUID]?.alwaysShowHiddenItems == !initial)
        }
    }

    @Test("An alwaysShowHiddenItems notification with no usable payload changes nothing")
    func alwaysShowHiddenItemsWithoutAUsablePayloadIsIgnored() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            let before = manager.configurations

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "alwaysShowHiddenItems",
                "scope": "specific:\(offscreenUUID)",
            ]))
            #expect(manager.configurations == before, "no payload at all")

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "alwaysShowHiddenItems",
                "scope": "specific:\(offscreenUUID)",
                "value": "true",
            ]))
            #expect(manager.configurations == before, "a stringly-typed value")
        }
    }

    // MARK: iceBarLocation

    /// The handler reads `stringValue` as an `Int` raw value, which is exactly
    /// what `SettingsURIHandler` posts — it normalises a name like
    /// `mousePointer` to `String(location.rawValue)` before posting.
    @Test("An iceBarLocation raw value is written to the named display", arguments: [
        ("0", IceBarLocation.dynamic),
        ("1", IceBarLocation.mousePointer),
        ("2", IceBarLocation.iceIcon),
        ("3", IceBarLocation.leftAligned),
        ("4", IceBarLocation.rightAligned),
    ])
    func iceBarLocationRawValueIsApplied(raw: String, expected: IceBarLocation) throws {
        try withScratchDefaults { _ in
            // Seed a location the notification is not asking for, so no case
            // in this table can pass by starting where it wants to end up.
            let seed: IceBarLocation = expected == .dynamic ? .rightAligned : .dynamic
            let manager = makeManager(.defaultConfiguration.withIceBarLocation(seed))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "iceBarLocation",
                "scope": "specific:\(offscreenUUID)",
                "stringValue": raw,
            ]))

            #expect(manager.configurations[offscreenUUID]?.iceBarLocation == expected)
        }
    }

    /// Only the normalised raw value is accepted here. A case name, an
    /// out-of-range number, or a missing payload leaves the display alone
    /// rather than falling back to `dynamic`.
    @Test("An iceBarLocation the handler cannot parse changes nothing", arguments: [
        "mousePointer",
        "dynamic",
        "5",
        "-1",
        "1.0",
        "",
    ])
    func unparsableIceBarLocationIsIgnored(raw: String) throws {
        try withScratchDefaults { _ in
            let seeded = DisplayIceBarConfiguration.defaultConfiguration.withIceBarLocation(.leftAligned)
            let manager = makeManager(seeded)

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "iceBarLocation",
                "scope": "specific:\(offscreenUUID)",
                "stringValue": raw,
            ]))

            #expect(manager.configurations[offscreenUUID] == seeded)
        }
    }

    /// Location is carried in `stringValue`; a sender that puts the raw value
    /// under `value` instead is a no-op, not a reset.
    @Test("An iceBarLocation notification with no stringValue changes nothing")
    func iceBarLocationWithoutStringValueIsIgnored() throws {
        try withScratchDefaults { _ in
            let seeded = DisplayIceBarConfiguration.defaultConfiguration.withIceBarLocation(.iceIcon)
            let manager = makeManager(seeded)

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "iceBarLocation",
                "scope": "specific:\(offscreenUUID)",
                "value": "2",
            ]))

            #expect(manager.configurations[offscreenUUID] == seeded)
        }
    }

    // MARK: iceBarLayout

    /// Unlike `iceBarLocation`, layout goes through `IceBarLayout.fromString`,
    /// so it accepts both the case name and the raw value.
    @Test("An iceBarLayout is written to the named display", arguments: [
        ("horizontal", IceBarLayout.horizontal),
        ("0", IceBarLayout.horizontal),
        ("vertical", IceBarLayout.vertical),
        ("1", IceBarLayout.vertical),
        ("grid", IceBarLayout.grid),
        ("2", IceBarLayout.grid),
    ])
    func iceBarLayoutIsApplied(raw: String, expected: IceBarLayout) throws {
        try withScratchDefaults { _ in
            let seed: IceBarLayout = expected == .horizontal ? .grid : .horizontal
            let manager = makeManager(.defaultConfiguration.withIceBarLayout(seed))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "iceBarLayout",
                "scope": "specific:\(offscreenUUID)",
                "stringValue": raw,
            ]))

            #expect(manager.configurations[offscreenUUID]?.iceBarLayout == expected)
        }
    }

    @Test("An iceBarLayout the handler cannot parse changes nothing", arguments: [
        "diagonal",
        "3",
        "-1",
        "Grid",
        "",
    ])
    func unparsableIceBarLayoutIsIgnored(raw: String) throws {
        try withScratchDefaults { _ in
            let seeded = DisplayIceBarConfiguration.defaultConfiguration.withIceBarLayout(.vertical)
            let manager = makeManager(seeded)

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "iceBarLayout",
                "scope": "specific:\(offscreenUUID)",
                "stringValue": raw,
            ]))

            #expect(manager.configurations[offscreenUUID] == seeded)
        }
    }

    // MARK: gridColumns

    /// The handler clamps to 2...10 before it reaches
    /// `DisplayIceBarConfiguration.withGridColumns`, which clamps again. Both
    /// ends of the range are asserted here because a URI is an untrusted
    /// input path.
    @Test("A gridColumns value is clamped into range and written", arguments: [
        ("2", 2),
        ("3", 3),
        ("7", 7),
        ("10", 10),
        ("1", 2),
        ("0", 2),
        ("-5", 2),
        ("11", 10),
        ("99", 10),
    ])
    func gridColumnsIsClampedAndApplied(raw: String, expected: Int) throws {
        try withScratchDefaults { _ in
            // The seed is 4, which is not in the expectation column, so every
            // case has to actually move the value.
            let manager = makeManager(.defaultConfiguration.withGridColumns(4))

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "gridColumns",
                "scope": "specific:\(offscreenUUID)",
                "stringValue": raw,
            ]))

            #expect(manager.configurations[offscreenUUID]?.gridColumns == expected)
        }
    }

    @Test("A gridColumns value that is not an integer changes nothing", arguments: [
        "abc",
        "3.5",
        "",
        " 3",
        "0x3",
    ])
    func nonIntegerGridColumnsIsIgnored(raw: String) throws {
        try withScratchDefaults { _ in
            let seeded = DisplayIceBarConfiguration.defaultConfiguration.withGridColumns(9)
            let manager = makeManager(seeded)

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "gridColumns",
                "scope": "specific:\(offscreenUUID)",
                "stringValue": raw,
            ]))

            #expect(manager.configurations[offscreenUUID] == seeded)
        }
    }

    // MARK: Blast radius

    /// Every setter goes through `updateConfiguration`, which rebuilds the
    /// configuration from the current one. A URI that sets one field must not
    /// reset the rest to `defaultConfiguration`.
    @Test("A change to one field leaves the display's other fields alone")
    func aChangeIsScopedToItsField() throws {
        try withScratchDefaults { _ in
            let seeded = DisplayIceBarConfiguration.defaultConfiguration
                .withUseIceBar(true)
                .withIceBarLocation(.leftAligned)
                .withAlwaysShowHiddenItems(true)
                .withIceBarLayout(.grid)
                .withGridColumns(9)
                .withItemSpacingOffset(-5)
            let manager = makeManager(seeded)

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "gridColumns",
                "scope": "specific:\(offscreenUUID)",
                "stringValue": "3",
            ]))

            let result = try #require(manager.configurations[offscreenUUID])
            #expect(result.gridColumns == 3)
            #expect(result == seeded.withGridColumns(3), "only gridColumns may have moved")
        }
    }

    @Test("A change to one display leaves every other display alone")
    func aChangeIsScopedToItsDisplay() throws {
        try withScratchDefaults { _ in
            let neighbour = DisplayIceBarConfiguration.defaultConfiguration.withGridColumns(7)
            let manager = makeManager()
            manager.configurations = [
                offscreenUUID: .defaultConfiguration,
                "TEST-DISPLAY-UUID-B": neighbour,
            ]

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "gridColumns",
                "scope": "specific:\(offscreenUUID)",
                "stringValue": "3",
            ]))

            #expect(manager.configurations[offscreenUUID]?.gridColumns == 3)
            #expect(manager.configurations["TEST-DISPLAY-UUID-B"] == neighbour)
        }
    }

    /// A scope-wide change only ever walks `NSScreen.screens`, so a display
    /// that is configured but not attached must sit it out. This is the case
    /// a user hits after unplugging a monitor: a broadcast must not silently
    /// rewrite the settings they saved for it.
    @Test("A scope-wide change never reaches a display that is not connected", arguments: [
        "active",
        "allEnabled",
        "allNonIceBar",
        "nonsense",
    ])
    func scopeWideChangesSkipDisconnectedDisplays(scopeRaw: String) throws {
        try withScratchDefaults { _ in
            let seeded = DisplayIceBarConfiguration.defaultConfiguration.withGridColumns(9)
            let manager = makeManager(seeded)

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "gridColumns",
                "scope": scopeRaw,
                "stringValue": "3",
            ]))

            #expect(manager.configurations[offscreenUUID] == seeded)
        }
    }

    /// The `allNonIceBar` broadcast. `makeManager` leaves every attached
    /// display on the global template, whose `useIceBar` is `false`, so every
    /// one of them is in scope. Vacuously true with no displays attached; the
    /// assertion about ``offscreenUUID`` holds either way.
    @Test("An allNonIceBar broadcast reaches the attached displays but not a stored one")
    func allNonIceBarBroadcastReachesAttachedDisplays() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "alwaysShowHiddenItems",
                "scope": "allNonIceBar",
                "value": true,
            ]))

            for display in manager.connectedDisplays() {
                #expect(manager.configuration(forUUID: display.id).alwaysShowHiddenItems, "\(display.id)")
            }
            #expect(
                manager.configurations[offscreenUUID]?.alwaysShowHiddenItems == false,
                "a stored but unattached display must not be swept up"
            )
        }
    }

    /// The `allEnabled` broadcast, which filters on `useIceBar`. The attached
    /// displays are opted in first so the filter has something to match.
    @Test("An allEnabled broadcast reaches the attached displays but not a stored one")
    func allEnabledBroadcastReachesAttachedDisplays() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()
            for display in manager.connectedDisplays() {
                manager.updateConfiguration(forDisplayUUID: display.id) { $0.withUseIceBar(true) }
            }

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "iceBarLayout",
                "scope": "allEnabled",
                "stringValue": "grid",
            ]))

            for display in manager.connectedDisplays() {
                #expect(manager.configuration(forUUID: display.id).iceBarLayout == .grid, "\(display.id)")
            }
            #expect(
                manager.configurations[offscreenUUID]?.iceBarLayout == .horizontal,
                "a stored but unattached display must not be swept up"
            )
        }
    }

    /// The other half of the validation guard: an attached display with no
    /// stored entry passes on `connectedUUIDs.contains`, not on `hasConfig`.
    /// Vacuously true with no displays attached.
    @Test("An attached display with no stored entry can still be targeted by UUID")
    func attachedDisplayWithoutAnEntryIsAccepted() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()

            for display in manager.connectedDisplays() {
                #expect(manager.configurations[display.id] == nil, "\(display.id)")

                manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                    "key": "useIceBar",
                    "scope": "specific:\(display.id)",
                    "value": true,
                ]))

                #expect(manager.configurations[display.id]?.useIceBar == true, "\(display.id)")
            }
        }
    }

    // MARK: Persistence

    /// The URI path writes through the same `didSet` the settings UI does, so
    /// an external change has to survive a relaunch rather than living only in
    /// memory until the next write.
    @Test("An external change is persisted")
    func anExternalChangeIsPersisted() throws {
        try withScratchDefaults { _ in
            let manager = makeManager()

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "gridColumns",
                "scope": "specific:\(offscreenUUID)",
                "stringValue": "8",
            ]))

            let data = try #require(Defaults.data(forKey: .displayIceBarConfigurations))
            let decoded = try JSONDecoder().decode([String: DisplayIceBarConfiguration].self, from: data)
            #expect(decoded[offscreenUUID]?.gridColumns == 8)
        }
    }

    /// A rejected notification must not write either. Without this, the guard
    /// could be "ignored the change but persisted the dictionary anyway".
    @Test("A rejected change leaves the stored configurations untouched")
    func aRejectedChangeIsNotPersisted() throws {
        try withScratchDefaults { _ in
            let manager = makeManager(.defaultConfiguration.withGridColumns(5))
            let before = Defaults.data(forKey: .displayIceBarConfigurations)

            manager.handleExternalPerDisplaySettingsChange(perDisplayChange([
                "key": "gridColumns",
                "scope": "specific:TEST-DISPLAY-UUID-UNKNOWN",
                "stringValue": "8",
            ]))

            #expect(Defaults.data(forKey: .displayIceBarConfigurations) == before)
        }
    }
}
