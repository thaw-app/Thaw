//
//  SettingsURIHandlerApplyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``SettingsURIHandler``'s *apply* surface — the `set` and `toggle`
/// actions and the notifications they post.
///
/// `SettingsURIHandlerTests` covers the pure side (key tables, `parseBool`,
/// `parseDouble`, `PerDisplayScope`). This suite drives the paths that
/// actually mutate state, which is where the trust boundary lives: these
/// functions run on behalf of a *third-party app* that sent a `thaw://` URL,
/// so a malformed key, an out-of-range double, or a non-finite value has to
/// be refused rather than written through to `Defaults`.
///
/// Every test body runs inside `withScratchDefaults`, so the handler's writes
/// land in a throwaway store rather than the real `com.stonerl.Thaw` domain,
/// and each test starts from an empty store.
@MainActor
@Suite("Settings URI handler apply", .serialized)
struct SettingsURIHandlerApplyTests {
    /// Collects the notifications posted on `name` while `body` runs.
    private func notifications(
        named name: Notification.Name,
        during body: () -> Void
    ) -> [Notification] {
        let box = NotificationBox()
        let token = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { box.append($0) }
        defer { NotificationCenter.default.removeObserver(token) }
        body()
        return box.contents
    }

    /// Notifications are delivered synchronously on the posting thread, but
    /// the observer closure is `@Sendable`, so the collector needs to be a
    /// reference type rather than a captured `var`.
    private final class NotificationBox: @unchecked Sendable {
        private(set) var contents: [Notification] = []
        func append(_ notification: Notification) {
            contents.append(notification)
        }
    }

    // MARK: Key rejection

    @Test("An unknown key is refused by both actions", arguments: ["", "nope", "showOnHove", "SHOWONHOVER"])
    func unknownKeyIsRefused(_ key: String) throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.handleSet(key: key, value: "true", sender: "test"))
            #expect(!SettingsURIHandler.handleToggle(key: key, sender: "test"))
        }
    }

    // MARK: Boolean set

    @Test("Setting a boolean writes it through to Defaults")
    func booleanSetWritesThrough() throws {
        try withScratchDefaults { _ in
            #expect(SettingsURIHandler.handleSet(key: "showOnHover", value: "true", sender: "test"))
            #expect(Defaults.bool(forKey: .showOnHover))

            #expect(SettingsURIHandler.handleSet(key: "showOnHover", value: "false", sender: "test"))
            #expect(!Defaults.bool(forKey: .showOnHover))
        }
    }

    @Test("Every truthy spelling reaches Defaults", arguments: ["true", "TRUE", "1", "yes", "YES"])
    func truthySpellingsApply(_ value: String) throws {
        try withScratchDefaults { _ in
            Defaults.set(false, forKey: .showOnHover)
            #expect(SettingsURIHandler.handleSet(key: "showOnHover", value: value, sender: "test"))
            #expect(Defaults.bool(forKey: .showOnHover))
        }
    }

    @Test("An unparsable boolean is refused and leaves the value alone")
    func unparsableBooleanIsRefused() throws {
        try withScratchDefaults { _ in
            Defaults.set(true, forKey: .showOnHover)

            #expect(!SettingsURIHandler.handleSet(key: "showOnHover", value: "maybe", sender: "test"))
            #expect(Defaults.bool(forKey: .showOnHover), "a refused set must not disturb the stored value")
        }
    }

    @Test("A boolean set announces its key and value")
    func booleanSetPostsANotification() throws {
        try withScratchDefaults { _ in
            let posted = notifications(named: .settingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: "showOnHover", value: "true", sender: "test")
            }

            #expect(posted.count == 1)
            #expect(posted.first?.userInfo?["key"] as? String == "showOnHover")
            #expect(posted.first?.userInfo?["value"] as? Bool == true)
        }
    }

    @Test("A refused set announces nothing")
    func refusedSetPostsNothing() throws {
        try withScratchDefaults { _ in
            let posted = notifications(named: .settingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: "showOnHover", value: "maybe", sender: "test")
            }

            #expect(posted.isEmpty)
        }
    }

    // MARK: Toggle

    @Test("Toggling flips the stored value")
    func toggleFlipsTheValue() throws {
        try withScratchDefaults { _ in
            Defaults.set(false, forKey: .autoRehide)

            #expect(SettingsURIHandler.handleToggle(key: "autoRehide", sender: "test"))
            #expect(Defaults.bool(forKey: .autoRehide))

            #expect(SettingsURIHandler.handleToggle(key: "autoRehide", sender: "test"))
            #expect(!Defaults.bool(forKey: .autoRehide))
        }
    }

    @Test("A non-boolean key cannot be toggled", arguments: ["rehideInterval", "rehideStrategy", "tooltipDelay"])
    func nonBooleanKeyCannotBeToggled(_ key: String) throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.handleToggle(key: key, sender: "test"))
        }
    }

    @Test("A toggle announces the new value")
    func togglePostsTheNewValue() throws {
        try withScratchDefaults { _ in
            Defaults.set(false, forKey: .autoRehide)

            let posted = notifications(named: .settingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleToggle(key: "autoRehide", sender: "test")
            }

            #expect(posted.first?.userInfo?["key"] as? String == "autoRehide")
            #expect(posted.first?.userInfo?["value"] as? Bool == true)
        }
    }

    // MARK: Double set

    @Test("A double inside its range is stored verbatim")
    func inRangeDoubleIsStored() throws {
        try withScratchDefaults { _ in
            #expect(SettingsURIHandler.handleSet(key: "rehideInterval", value: "42", sender: "test"))
            #expect(Defaults.double(forKey: .rehideInterval) == 42)
        }
    }

    @Test("A double outside its range is clamped to the bound it passed")
    func outOfRangeDoubleIsClamped() throws {
        try withScratchDefaults { _ in
            // rehideInterval is bounded to 1...300.
            #expect(SettingsURIHandler.handleSet(key: "rehideInterval", value: "99999", sender: "test"))
            #expect(Defaults.double(forKey: .rehideInterval) == 300)

            #expect(SettingsURIHandler.handleSet(key: "rehideInterval", value: "-5", sender: "test"))
            #expect(Defaults.double(forKey: .rehideInterval) == 1)
        }
    }

    @Test("Each double key clamps to its own range")
    func eachDoubleKeyHasItsOwnRange() throws {
        try withScratchDefaults { _ in
            #expect(SettingsURIHandler.handleSet(key: "showOnHoverDelay", value: "900", sender: "test"))
            #expect(Defaults.double(forKey: .showOnHoverDelay) == 5)

            #expect(SettingsURIHandler.handleSet(key: "tooltipDelay", value: "-900", sender: "test"))
            #expect(Defaults.double(forKey: .tooltipDelay) == 0)

            #expect(SettingsURIHandler.handleSet(key: "iconRefreshInterval", value: "2.5", sender: "test"))
            #expect(Defaults.double(forKey: .iconRefreshInterval) == 1.0)
        }
    }

    @Test("iconRefreshInterval snaps onto the discrete fps grid before Defaults write")
    func iconRefreshIntervalSnapsOntoFpsGrid() throws {
        try withScratchDefaults { _ in
            // 0.6 s → ~1.67 fps → nearest 2 fps → 0.5 s
            #expect(SettingsURIHandler.handleSet(key: "iconRefreshInterval", value: "0.6", sender: "test"))
            #expect(Defaults.double(forKey: .iconRefreshInterval) == 0.5)

            // Above the 30 fps ceiling → floor interval
            #expect(SettingsURIHandler.handleSet(key: "iconRefreshInterval", value: "0.01", sender: "test"))
            #expect(
                Defaults.double(forKey: .iconRefreshInterval)
                    == MenuBarItemImageCache.minIconRefreshInterval
            )

            // On-grid 10 fps survives
            #expect(SettingsURIHandler.handleSet(key: "iconRefreshInterval", value: "0.1", sender: "test"))
            #expect(Defaults.double(forKey: .iconRefreshInterval) == 0.1)

            #expect(SettingsURIHandler.handleSet(key: "iconRefreshInterval", value: "0", sender: "test"))
            #expect(Defaults.double(forKey: .iconRefreshInterval) == 0)
        }
    }

    @Test("A non-finite double is refused rather than clamped", arguments: ["nan", "inf", "-inf"])
    func nonFiniteDoubleIsRefused(_ value: String) throws {
        try withScratchDefaults { _ in
            Defaults.set(30.0, forKey: .rehideInterval)

            #expect(!SettingsURIHandler.handleSet(key: "rehideInterval", value: value, sender: "test"))
            #expect(Defaults.double(forKey: .rehideInterval) == 30)
        }
    }

    @Test("An unparsable double is refused")
    func unparsableDoubleIsRefused() throws {
        try withScratchDefaults { _ in
            Defaults.set(30.0, forKey: .rehideInterval)

            #expect(!SettingsURIHandler.handleSet(key: "rehideInterval", value: "soon", sender: "test"))
            #expect(Defaults.double(forKey: .rehideInterval) == 30)
        }
    }

    @Test("A double set announces the clamped value, not the requested one")
    func doubleSetAnnouncesTheClampedValue() throws {
        try withScratchDefaults { _ in
            let posted = notifications(named: .settingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: "rehideInterval", value: "99999", sender: "test")
            }

            #expect(posted.first?.userInfo?["key"] as? String == "rehideInterval")
            #expect(posted.first?.userInfo?["doubleValue"] as? Double == 300)
        }
    }

    // MARK: Enum set

    @Test(
        "rehideStrategy accepts its names and raw values",
        arguments: [("smart", 0), ("timed", 1), ("focusedApp", 2), ("0", 0), ("1", 1), ("2", 2)]
    )
    func rehideStrategyIsAccepted(_ pair: (String, Int)) throws {
        try withScratchDefaults { _ in
            let (value, expected) = pair
            #expect(SettingsURIHandler.handleSet(key: "rehideStrategy", value: value, sender: "test"))
            #expect(Defaults.integer(forKey: .rehideStrategy) == expected)
        }
    }

    @Test("An unknown rehideStrategy is refused", arguments: ["", "eventually", "9", "-1", "focused_app"])
    func unknownRehideStrategyIsRefused(_ value: String) throws {
        try withScratchDefaults { _ in
            Defaults.set(1, forKey: .rehideStrategy)

            #expect(!SettingsURIHandler.handleSet(key: "rehideStrategy", value: value, sender: "test"))
            #expect(Defaults.integer(forKey: .rehideStrategy) == 1)
        }
    }

    @Test("An enum set announces its raw value")
    func enumSetAnnouncesItsRawValue() throws {
        try withScratchDefaults { _ in
            let posted = notifications(named: .settingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: "rehideStrategy", value: "timed", sender: "test")
            }

            #expect(posted.first?.userInfo?["key"] as? String == "rehideStrategy")
            #expect(posted.first?.userInfo?["rawEnumValue"] as? Int == 1)
        }
    }

    // MARK: Per-display set

    @Test("A per-display set is announced on the per-display channel")
    func perDisplaySetIsAnnounced() throws {
        try withScratchDefaults { _ in
            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: "useIceBar", value: "true", sender: "test")
            }

            #expect(posted.count == 1)
            #expect(posted.first?.userInfo?["key"] as? String == "useIceBar")
            #expect(posted.first?.userInfo?["value"] as? Bool == true)
            #expect(posted.first?.userInfo?["scope"] as? String == "active")
        }
    }

    @Test("alwaysShowHiddenItems defaults to the non-Thaw-Bar displays")
    func alwaysShowHiddenItemsScope() throws {
        try withScratchDefaults { _ in
            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: "alwaysShowHiddenItems", value: "true", sender: "test")
            }

            #expect(posted.first?.userInfo?["scope"] as? String == "allNonIceBar")
        }
    }

    @Test("A per-display set does not write to Defaults")
    func perDisplaySetDoesNotTouchDefaults() throws {
        try withScratchDefaults { _ in
            // Per-display values live in DisplaySettingsManager, reached by
            // notification; the handler must not shortcut into Defaults.
            let before = Defaults.data(forKey: .displayIceBarConfigurations)
            _ = SettingsURIHandler.handleSet(key: "useIceBar", value: "true", sender: "test")
            #expect(Defaults.data(forKey: .displayIceBarConfigurations) == before)
        }
    }

    @Test("An invalid per-display boolean is refused", arguments: ["useIceBar", "alwaysShowHiddenItems", "useThawBarForAlwaysHidden"])
    func invalidPerDisplayBooleanIsRefused(_ key: String) throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.handleSet(key: key, value: "maybe", sender: "test"))
        }
    }

    @Test(
        "iceBarLocation accepts names and raw values",
        arguments: ["dynamic", "mousePointer", "iceIcon", "leftAligned", "rightAligned", "0", "4"]
    )
    func iceBarLocationIsAccepted(_ value: String) throws {
        try withScratchDefaults { _ in
            #expect(SettingsURIHandler.handleSet(key: "iceBarLocation", value: value, sender: "test"))
        }
    }

    @Test("An unknown iceBarLocation is refused", arguments: ["", "sideways", "99", "DYNAMIC"])
    func unknownIceBarLocationIsRefused(_ value: String) throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.handleSet(key: "iceBarLocation", value: value, sender: "test"))
        }
    }

    @Test("iceBarLayout accepts names and raw values", arguments: ["horizontal", "vertical", "grid", "0", "1", "2"])
    func iceBarLayoutIsAccepted(_ value: String) throws {
        try withScratchDefaults { _ in
            #expect(SettingsURIHandler.handleSet(key: "iceBarLayout", value: value, sender: "test"))
        }
    }

    @Test("An unknown iceBarLayout is refused", arguments: ["", "diagonal", "9", "GRID"])
    func unknownIceBarLayoutIsRefused(_ value: String) throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.handleSet(key: "iceBarLayout", value: value, sender: "test"))
        }
    }

    @Test("A location or layout set targets the displays that have the bar enabled")
    func locationAndLayoutScope() throws {
        try withScratchDefaults { _ in
            for key in ["iceBarLocation", "iceBarLayout"] {
                let value = key == "iceBarLocation" ? "dynamic" : "grid"
                let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                    _ = SettingsURIHandler.handleSet(key: key, value: value, sender: "test")
                }
                #expect(posted.first?.userInfo?["scope"] as? String == "allEnabled", "\(key)")
            }
        }
    }

    @Test("gridColumns is clamped into 2...10 before it is announced")
    func gridColumnsIsClamped() throws {
        try withScratchDefaults { _ in
            for (requested, expected) in [("1", "2"), ("0", "2"), ("-4", "2"), ("11", "10"), ("999", "10"), ("4", "4")] {
                let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                    _ = SettingsURIHandler.handleSet(key: "gridColumns", value: requested, sender: "test")
                }
                #expect(posted.first?.userInfo?["stringValue"] as? String == expected, "gridColumns=\(requested)")
            }
        }
    }

    @Test("A non-numeric gridColumns is refused", arguments: ["many", "", "4.5"])
    func nonNumericGridColumnsIsRefused(_ value: String) throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.handleSet(key: "gridColumns", value: value, sender: "test"))
        }
    }

    // MARK: Specific display targeting

    @Test("A malformed display UUID is refused")
    func malformedDisplayUUIDIsRefused() throws {
        try withScratchDefaults { _ in
            #expect(
                !SettingsURIHandler.handleSet(
                    key: "useIceBar",
                    value: "true",
                    sender: "test",
                    displayUUID: "not-a-uuid"
                )
            )
        }
    }

    @Test("A well-formed but unknown display UUID is refused")
    func unknownDisplayUUIDIsRefused() throws {
        try withScratchDefaults { _ in
            #expect(
                !SettingsURIHandler.handleSet(
                    key: "useIceBar",
                    value: "true",
                    sender: "test",
                    displayUUID: UUID().uuidString
                )
            )
        }
    }

    @Test("A per-display toggle rejects a UUID with no dashes")
    func perDisplayToggleValidatesTheUUIDShape() throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.handleToggle(key: "useIceBar", sender: "test", displayUUID: "nodashes"))
        }
    }

    @Test("A per-display toggle targeting a display announces that scope")
    func perDisplayToggleTargetsTheDisplay() throws {
        try withScratchDefaults { _ in
            // The toggle path requires the display to be known, so persist one.
            let uuid = UUID().uuidString
            let seeded = try JSONEncoder().encode([uuid: DisplayIceBarConfiguration.defaultConfiguration])
            Defaults.set(seeded, forKey: .displayIceBarConfigurations)
            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleToggle(key: "useIceBar", sender: "test", displayUUID: uuid)
            }

            #expect(posted.first?.userInfo?["scope"] as? String == "specific:\(uuid)")
            #expect(posted.first?.userInfo?["toggle"] as? Bool == true)
        }
    }

    @Test("iceBarLocation cannot be toggled, with or without a display")
    func iceBarLocationCannotBeToggled() throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.handleToggle(key: "iceBarLocation", sender: "test"))
            #expect(
                !SettingsURIHandler.handleToggle(
                    key: "iceBarLocation",
                    sender: "test",
                    displayUUID: UUID().uuidString
                )
            )
        }
    }

    @Test("A per-display toggle without a UUID is announced")
    func perDisplayToggleIsAnnounced() throws {
        try withScratchDefaults { _ in
            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleToggle(key: "useIceBar", sender: "test")
            }

            #expect(posted.count == 1)
            #expect(posted.first?.userInfo?["key"] as? String == "useIceBar")
            #expect(posted.first?.userInfo?["toggle"] as? Bool == true)
            #expect(posted.first?.userInfo?["scope"] as? String == "active")
        }
    }

    // MARK: Whitelist

    @Test("A nil bundle identifier is never whitelisted")
    func nilBundleIdentifierIsNotWhitelisted() throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: nil))
        }
    }

    @Test("An unlisted bundle identifier is not whitelisted")
    func unlistedBundleIdentifierIsNotWhitelisted() throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.example.NotListed"))
        }
    }

    @Test("Adding then removing leaves the whitelist as it started")
    func whitelistRoundTrips() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Alpha")
            #expect(SettingsURIHandler.getWhitelist().contains("com.example.Alpha"))

            SettingsURIHandler.removeFromWhitelist(bundleId: "com.example.Alpha")
            #expect(!SettingsURIHandler.getWhitelist().contains("com.example.Alpha"))
        }
    }

    @Test("Adding the same bundle identifier twice does not duplicate it")
    func whitelistDoesNotDuplicate() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Alpha")
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Alpha")

            #expect(SettingsURIHandler.getWhitelist().filter { $0 == "com.example.Alpha" }.count == 1)
        }
    }

    @Test("Removing an entry that was never listed is a no-op")
    func removingAnAbsentEntryIsHarmless() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Alpha")

            SettingsURIHandler.removeFromWhitelist(bundleId: "com.example.Ghost")

            #expect(SettingsURIHandler.getWhitelist() == ["com.example.Alpha"])
        }
    }

    @Test("Adding an entry announces the change")
    func whitelistAdditionIsAnnounced() throws {
        try withScratchDefaults { _ in
            let posted = notifications(named: .settingsURIWhitelistDidChange) {
                SettingsURIHandler.addToWhitelist(bundleId: "com.example.Alpha")
            }

            #expect(!posted.isEmpty)
        }
    }

    // MARK: Enabled gate

    @Test("The URI surface follows its Defaults flag")
    func enabledFlagIsHonored() throws {
        try withScratchDefaults { _ in
            Defaults.set(true, forKey: .settingsURIEnabled)
            #expect(SettingsURIHandler.isEnabled())

            Defaults.set(false, forKey: .settingsURIEnabled)
            #expect(!SettingsURIHandler.isEnabled())
        }
    }
}
