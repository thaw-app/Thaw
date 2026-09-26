//
//  SettingsURIHandlerCoverageTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Collects the notifications posted on `name` while `body` runs.
/// File-scoped so the nested suites below share one copy.
@MainActor
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

/// Notifications are delivered synchronously on the posting thread, but the
/// observer closure is `@Sendable`, so the collector has to be a reference type
/// rather than a captured `var`.
private final class NotificationBox: @unchecked Sendable {
    private(set) var contents: [Notification] = []
    func append(_ notification: Notification) {
        contents.append(notification)
    }
}

/// The Boolean keys ``SettingsURIHandler`` publishes as settable and toggleable.
///
/// Copied because `@Test(arguments:)` evaluates its collection outside the
/// main actor and the handler is `@MainActor`. `KeyTableCompleteness`
/// asserts the copies still match the handler's tables.
private let booleanKeys: [String] = [
    "autoRehide",
    "showOnClick",
    "showOnDoubleClick",
    "showOnHover",
    "showOnScroll",
    "useIceBarOnlyOnNotchedDisplay",
    "hideApplicationMenus",
    "hideDockIconWhenToggling",
    "enableAlwaysHiddenSection",
    "useOptionClickToShowAlwaysHiddenSection",
    "useDoubleClickToShowAlwaysHiddenSection",
    "enableSecondaryContextMenu",
    "showAllSectionsOnUserDrag",
    "showMenuBarTooltips",
    "enableDiagnosticLogging",
    "customIceIconIsTemplate",
    "showIceIcon",
    "iceBarLocationOnHotkey",
    "enableMenuBarItemOverflow",
    "useThawBarOnNotchOverflow",
    "searchIncludeVisible",
    "searchIncludeHidden",
    "searchIncludeAlwaysHidden",
    "moveCursorToRevealedItem",
]

/// See ``booleanKeys`` for why these are copies.
private let doubleKeys: [String] = [
    "rehideInterval",
    "showOnHoverDelay",
    "tooltipDelay",
    "iconRefreshInterval",
]

/// See ``booleanKeys`` for why these are copies.
private let enumKeys: [String] = ["rehideStrategy"]

/// See ``booleanKeys`` for why these are copies.
private let perDisplayKeys: [String] = [
    "useIceBar",
    "useThawBarForAlwaysHidden",
    "iceBarLocation",
    "alwaysShowHiddenItems",
    "iceBarLayout",
    "gridColumns",
]

/// The Boolean keys that live in `Defaults` rather than in
/// `DisplaySettingsManager`, and so answer on `.settingsDidChangeViaURI`
/// rather than `.perDisplaySettingsDidChangeViaURI`.
///
/// This is all of ``booleanKeys``, not a filtered subset: the handler keeps
/// the per-display Booleans out of `supportedBooleanKeys` by design, and
/// `localKeyListsMatchTheHandler` pins that the copies here mirror it.
private let globalBooleanKeys: [String] = booleanKeys

/// Every key the `get` action can be asked for that is not a per-display one.
private let globalReadableKeys: [String] = globalBooleanKeys + doubleKeys + enumKeys

/// Covers what the four sibling ``SettingsURIHandler`` suites leave
/// unreached, plus key-table completeness:
///
/// - **The named-display toggle of `alwaysShowHiddenItems`.** Only the
///   `useIceBar` arm of `handleToggle` was driven with a display identifier.
/// - **Reading a per-display key for an unknown display.** The individual-key
///   refusal takes a different arm from the covered `key=display` one.
/// - **A stored `rehideStrategy` raw value outside `0...2`.** A downgrade or a
///   hand-edited `defaults write` produces one; `get` must still answer.
/// - **A callback URL `URLComponents` refuses outright.** The sibling
///   "schemeless" cases parse and fail the scheme check instead.
/// - **The full key tables.** A key in `supportedBooleanKeys` but missing from
///   `keyMapping` is refused at run time with no compile-time error.
/// - **Parser edge inputs.** Whitespace, digit separators, hex floats, and
///   infinity spellings the range check must refuse.
///
/// Not covered: `promptForAuthorization` (modal `NSAlert`), the success path
/// of `sendCallbackResponse` (launches another app), `getAppName`'s
/// bundle-path arm (needs an installed app that is not running), and
/// `verifyCodeSignature` arms that need a team-signed app.
///
/// Every read or write runs inside `withScratchDefaults`.
@MainActor
@Suite("Settings URI handler residue", .serialized)
enum SettingsURIHandlerCoverageTests {
    // MARK: - Key table completeness

    @MainActor
    @Suite("Key table completeness")
    struct KeyTableCompleteness {
        /// Guards the copies at the top of this file against drift. Without it
        /// a key added to production would silently escape every test below.
        @Test("The key lists this suite drives still match the handler's own tables")
        func localKeyListsMatchTheHandler() {
            #expect(Set(booleanKeys) == Set(SettingsURIHandler.supportedBooleanKeys))
            #expect(Set(doubleKeys) == Set(SettingsURIHandler.doubleKeys))
            #expect(Set(enumKeys) == Set(SettingsURIHandler.enumKeys))
            #expect(Set(perDisplayKeys) == Set(SettingsURIHandler.perDisplayKeys))
            #expect(booleanKeys.count == SettingsURIHandler.supportedBooleanKeys.count, "no duplicates on either side")
        }

        /// A key in `supportedBooleanKeys` with no `keyMapping` entry is
        /// refused at run time and announces nothing. Asserting the
        /// notification rather than the return value catches that even for the
        /// per-display keys, which answer on the other channel.
        @Test("Every Boolean key the handler publishes can be set and says so", arguments: booleanKeys)
        func everyBooleanKeyIsSettable(_ key: String) throws {
            try withScratchDefaults { _ in
                let channel: Notification.Name = perDisplayKeys.contains(key)
                    ? .perDisplaySettingsDidChangeViaURI
                    : .settingsDidChangeViaURI

                let posted = notifications(named: channel) {
                    _ = SettingsURIHandler.handleSet(key: key, value: "true", sender: "test")
                }

                #expect(posted.count == 1, "\(key)")
                #expect(posted.first?.userInfo?["key"] as? String == key, "\(key)")
                #expect(posted.first?.userInfo?["value"] as? Bool == true, "\(key)")
            }
        }

        /// Toggling twice has to announce two opposite values: that is only
        /// true if the handler is reading back what it just wrote, through a
        /// mapping that actually exists.
        @Test("Every global Boolean key toggles against its own stored value", arguments: globalBooleanKeys)
        func everyGlobalBooleanKeyToggles(_ key: String) throws {
            try withScratchDefaults { _ in
                let posted = notifications(named: .settingsDidChangeViaURI) {
                    _ = SettingsURIHandler.handleToggle(key: key, sender: "test")
                    _ = SettingsURIHandler.handleToggle(key: key, sender: "test")
                }

                #expect(posted.count == 2, "\(key)")
                let first = posted.first?.userInfo?["value"] as? Bool
                let second = posted.last?.userInfo?["value"] as? Bool
                #expect(first != nil, "\(key)")
                #expect(first != second, "\(key) must toggle away from what it just stored")
            }
        }

        @Test("Every key the handler publishes is readable", arguments: globalReadableKeys)
        func everyGlobalKeyIsReadable(_ key: String) throws {
            try withScratchDefaults { _ in
                #expect(
                    SettingsURIHandler.handleGet(
                        key: key,
                        displayUUID: nil,
                        callback: nil,
                        broadcast: true,
                        requestId: "req-read-\(key)"
                    ),
                    "\(key)"
                )
            }
        }

        /// Reading is never destructive: a `get` of every publishable key must
        /// leave the store exactly as it found it. Three keys are seeded with
        /// distinctive values so a read that wrote a default back is caught,
        /// and one is left unset so a read that materialised a default is too.
        @Test("Reading every key leaves the stored values alone")
        func readingDoesNotWriteBack() throws {
            try withScratchDefaults { _ in
                Defaults.set(true, forKey: .showOnHover)
                Defaults.set(123.0, forKey: .rehideInterval)
                Defaults.set(RehideStrategy.focusedApp.rawValue, forKey: .rehideStrategy)
                Defaults.removeObject(forKey: .tooltipDelay)

                for key in globalReadableKeys {
                    _ = SettingsURIHandler.handleGet(
                        key: key,
                        displayUUID: nil,
                        callback: nil,
                        broadcast: true,
                        requestId: "req-readonly-\(key)"
                    )
                }

                #expect(Defaults.bool(forKey: .showOnHover))
                #expect(Defaults.double(forKey: .rehideInterval) == 123)
                #expect(Defaults.integer(forKey: .rehideStrategy) == RehideStrategy.focusedApp.rawValue)
                #expect(
                    Defaults.object(forKey: .tooltipDelay) == nil,
                    "reading an unset key must not write a default into the store"
                )
            }
        }
    }

    // MARK: - Toggling a named display

    @MainActor
    @Suite("Toggling a named display")
    struct TogglingANamedDisplay {
        /// The Boolean per-display keys reach separate arms of
        /// `handlePerDisplayToggle`. All must behave identically: a toggle carries
        /// the flag and no value, since the reader flips whatever it holds.
        @Test(
            "Any Boolean per-display key can be toggled on a named display",
            arguments: ["useIceBar", "alwaysShowHiddenItems", "useThawBarForAlwaysHidden"]
        )
        func namedDisplayToggleWorksForBothBooleanKeys(_ key: String) throws {
            try withScratchDefaults { _ in
                // The toggle path requires the display to be known, so persist one.
                let uuid = UUID().uuidString
                let seeded = try JSONEncoder().encode([uuid: DisplayIceBarConfiguration.defaultConfiguration])
                Defaults.set(seeded, forKey: .displayIceBarConfigurations)
                var accepted = false

                let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                    accepted = SettingsURIHandler.handleToggle(key: key, sender: "test", displayUUID: uuid)
                }

                #expect(accepted, "\(key)")
                #expect(posted.count == 1, "\(key)")
                let userInfo = try #require(posted.first?.userInfo, "\(key)")
                #expect(userInfo["key"] as? String == key, "\(key)")
                #expect(userInfo["scope"] as? String == "specific:\(uuid)", "\(key)")
                #expect(userInfo["toggle"] as? Bool == true, "\(key)")
                #expect(userInfo["value"] == nil, "\(key)")
                #expect(userInfo["stringValue"] == nil, "\(key)")
            }
        }

        /// Toggle and set validate a named display identically: it must parse as
        /// a UUID and be connected or persisted. Toggle used to check only for a
        /// hyphen and reported success for displays that did not exist.
        @Test(
            "A named-display toggle refuses an unknown display, like the set path",
            arguments: ["useIceBar", "alwaysShowHiddenItems", "useThawBarForAlwaysHidden"]
        )
        func namedDisplayToggleRefusesAnUnknownDisplay(_ key: String) throws {
            try withScratchDefaults { _ in
                // Never persisted or attached, so refused.
                #expect(!SettingsURIHandler.handleToggle(key: key, sender: "test", displayUUID: UUID().uuidString), "\(key)")
                #expect(!SettingsURIHandler.handleToggle(key: key, sender: "test", displayUUID: "nodashes"), "\(key)")

                // The set path is the stricter one, for the same identifier.
                #expect(
                    !SettingsURIHandler.handleSet(
                        key: key,
                        value: "true",
                        sender: "test",
                        displayUUID: UUID().uuidString
                    ),
                    "\(key)"
                )
            }
        }
    }

    // MARK: - Setting a named display

    @MainActor
    @Suite("Setting a named display")
    struct SettingANamedDisplay {
        /// The Boolean per-display keys reach separate arms of
        /// `handlePerDisplaySetForSpecificDisplay`, so each has to be driven
        /// with a display identifier: a set carries the parsed value and no
        /// toggle flag, and a value the arm cannot parse is refused before
        /// anything is posted.
        @Test(
            "Any Boolean per-display key can be set on a named display",
            arguments: ["useIceBar", "alwaysShowHiddenItems", "useThawBarForAlwaysHidden"]
        )
        func namedDisplaySetWorksForBooleanKeys(_ key: String) throws {
            try withScratchDefaults { _ in
                // The set path requires the display to be known, so persist a
                // configuration for it.
                let uuid = UUID().uuidString
                let seeded = try JSONEncoder().encode([uuid: DisplayIceBarConfiguration.defaultConfiguration])
                Defaults.set(seeded, forKey: .displayIceBarConfigurations)
                var accepted = false

                let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                    accepted = SettingsURIHandler.handleSet(key: key, value: "true", sender: "test", displayUUID: uuid)
                }

                #expect(accepted, "\(key)")
                #expect(posted.count == 1, "\(key)")
                let userInfo = try #require(posted.first?.userInfo, "\(key)")
                #expect(userInfo["key"] as? String == key, "\(key)")
                #expect(userInfo["scope"] as? String == "specific:\(uuid)", "\(key)")
                #expect(userInfo["value"] as? Bool == true, "\(key)")
                #expect(userInfo["toggle"] == nil, "\(key)")

                // The same arm refuses a value it cannot parse as a Boolean.
                #expect(!SettingsURIHandler.handleSet(key: key, value: "maybe", sender: "test", displayUUID: uuid), "\(key)")
            }
        }
    }

    // MARK: - Reading a display that is not there

    @MainActor
    @Suite("Reading a display that is not there")
    struct ReadingAnAbsentDisplay {
        /// The individual-key read resolves the display before it looks at the
        /// key at all, and reports a missing setting when it cannot. Every test
        /// here persists a *different* display first, so the refusal is the
        /// named identifier being unknown rather than the store being empty.
        @Test("A per-display read for a display that is not there is refused", arguments: perDisplayKeys)
        func perDisplayReadForAnAbsentDisplayIsRefused(_ key: String) throws {
            try withScratchDefaults { _ in
                let known = UUID().uuidString
                let absent = UUID().uuidString
                let data = try JSONEncoder().encode([known: DisplayIceBarConfiguration.defaultConfiguration])
                Defaults.set(data, forKey: .displayIceBarConfigurations)

                // Control: the same key against a display the store knows is
                // answered, so the refusal below is about the identifier.
                #expect(
                    SettingsURIHandler.handleGet(
                        key: key,
                        displayUUID: known,
                        callback: nil,
                        broadcast: true,
                        requestId: "req-known-\(key)"
                    ),
                    "\(key)"
                )
                #expect(
                    !SettingsURIHandler.handleGet(
                        key: key,
                        displayUUID: absent,
                        callback: nil,
                        broadcast: true,
                        requestId: "req-absent-\(key)"
                    ),
                    "\(key)"
                )
            }
        }

        /// A malformed identifier takes the same route out, unlike `set`, which
        /// rejects it earlier on its `UUID(uuidString:)` check.
        @Test("A per-display read with a malformed identifier is refused", arguments: perDisplayKeys)
        func perDisplayReadWithAMalformedIdentifierIsRefused(_ key: String) throws {
            try withScratchDefaults { _ in
                #expect(
                    !SettingsURIHandler.handleGet(
                        key: key,
                        displayUUID: "not-a-display",
                        callback: nil,
                        broadcast: true,
                        requestId: "req-malformed-\(key)"
                    ),
                    "\(key)"
                )
            }
        }

        /// A global key is not per-display, so the same unknown identifier that
        /// fails a per-display read has to be ignored here rather than turning
        /// a perfectly good read into a failure.
        @Test("An unknown display identifier on a global read is ignored, not refused")
        func absentDisplayIdentifierOnAGlobalReadIsIgnored() throws {
            try withScratchDefaults { _ in
                #expect(
                    SettingsURIHandler.handleGet(
                        key: "showOnHover",
                        displayUUID: UUID().uuidString,
                        callback: nil,
                        broadcast: true,
                        requestId: "req-global-with-display"
                    )
                )
            }
        }
    }

    // MARK: - A stored value the enumeration cannot name

    @MainActor
    @Suite("A stored value the enumeration cannot name")
    struct UnnamedEnumerationValue {
        /// A downgrade or a hand-written `defaults write` can leave a raw value
        /// outside the enumeration. The read must answer with it rather than
        /// report "Setting not found", or the caller could never see or fix it.
        @Test("A rehideStrategy the enumeration cannot name is still answered", arguments: [99, -1, 3])
        func outOfRangeRehideStrategyIsStillAnswered(_ raw: Int) throws {
            try withScratchDefaults { _ in
                Defaults.set(raw, forKey: .rehideStrategy)

                #expect(
                    SettingsURIHandler.handleGet(
                        key: "rehideStrategy",
                        displayUUID: nil,
                        callback: nil,
                        broadcast: true,
                        requestId: "req-strategy-\(raw)"
                    ),
                    "rehideStrategy=\(raw)"
                )
                #expect(Defaults.integer(forKey: .rehideStrategy) == raw, "a read must not repair the stored value")
            }
        }

        /// The contrast: a value the enumeration *can* name is answered too, so
        /// the test above is not simply asserting that reads always succeed.
        @Test("A rehideStrategy the enumeration can name is answered as well")
        func inRangeRehideStrategyIsAnswered() throws {
            try withScratchDefaults { _ in
                for strategy in RehideStrategy.allCases {
                    Defaults.set(strategy.rawValue, forKey: .rehideStrategy)
                    #expect(
                        SettingsURIHandler.handleGet(
                            key: "rehideStrategy",
                            displayUUID: nil,
                            callback: nil,
                            broadcast: true,
                            requestId: "req-strategy-\(strategy.rawValue)"
                        ),
                        "\(strategy)"
                    )
                }
            }
        }

        /// A value the enumeration cannot name must not become writable by
        /// accident either: `set` still refuses it, so the only way to reach
        /// that stored state is from outside Thaw.
        @Test("A rehideStrategy the enumeration cannot name is still refused on write", arguments: ["99", "-1", "3"])
        func outOfRangeRehideStrategyIsRefusedOnWrite(_ value: String) throws {
            try withScratchDefaults { _ in
                Defaults.set(RehideStrategy.timed.rawValue, forKey: .rehideStrategy)

                #expect(!SettingsURIHandler.handleSet(key: "rehideStrategy", value: value, sender: "test"), "\(value)")
                #expect(Defaults.integer(forKey: .rehideStrategy) == RehideStrategy.timed.rawValue)
            }
        }
    }

    // MARK: - Callback URLs that will not parse

    @MainActor
    @Suite("Callback URLs that will not parse")
    struct UnparsableCallbackURLs {
        /// The sibling "schemeless" cases parse and fail the scheme check. These
        /// do not parse at all, a different branch, so each case asserts that first.
        @Test("A callback URL the parser cannot read at all is refused", arguments: [
            "https://exa mple.com/callback",
            "ht^tp://callback",
            "http://[::1",
            "http://%%",
            "thaw-callback://ho st/path",
        ])
        func unparsableCallbackIsRefused(_ callback: String) throws {
            try withScratchDefaults { _ in
                #expect(URLComponents(string: callback) == nil, "\(callback) must be unparsable for this test to mean anything")
                #expect(
                    !SettingsURIHandler.handleGet(
                        key: "version",
                        displayUUID: nil,
                        callback: callback,
                        broadcast: false,
                        requestId: "req-unparsable"
                    ),
                    "\(callback)"
                )
            }
        }

        /// A callback the handler will not open fails the whole request even
        /// when the caller also asked for a broadcast, for an unparsable URL
        /// exactly as for a dangerous scheme.
        @Test("An unparsable callback is not quietly downgraded to a broadcast")
        func unparsableCallbackIsNotDowngraded() throws {
            try withScratchDefaults { _ in
                #expect(
                    !SettingsURIHandler.handleGet(
                        key: "all",
                        displayUUID: nil,
                        callback: "https://exa mple.com/callback",
                        broadcast: true,
                        requestId: "req-unparsable-both"
                    )
                )
            }
        }
    }

    // MARK: - Parser inputs at the edges

    @MainActor
    @Suite("Parser inputs at the edges")
    struct ParserEdges {
        /// A `thaw://` URL is assembled by whoever sends it, and a stray space
        /// around the value is the easiest mistake to make. It has to be
        /// refused rather than trimmed, so the sender learns about it.
        @Test("A Boolean with surrounding whitespace is refused", arguments: [
            " true",
            "true ",
            "\ttrue",
            "yes\n",
            " 1",
            "0 ",
        ])
        func paddedBooleansAreRefused(_ value: String) throws {
            #expect(SettingsURIHandler.parseBool(value) == nil, "\(value.debugDescription)")

            try withScratchDefaults { _ in
                Defaults.set(true, forKey: .showOnHover)
                #expect(!SettingsURIHandler.handleSet(key: "showOnHover", value: value, sender: "test"))
                #expect(Defaults.bool(forKey: .showOnHover), "a refused set must not disturb the stored value")
            }
        }

        @Test("A double with whitespace or digit separators is refused", arguments: [
            " 1.5",
            "1.5 ",
            "1_000",
            "1,5",
            "1 000",
        ])
        func paddedOrSeparatedDoublesAreRefused(_ value: String) throws {
            #expect(SettingsURIHandler.parseDouble(value) == nil, "\(value.debugDescription)")

            try withScratchDefaults { _ in
                Defaults.set(42.0, forKey: .rehideInterval)
                #expect(!SettingsURIHandler.handleSet(key: "rehideInterval", value: value, sender: "test"))
                #expect(Defaults.double(forKey: .rehideInterval) == 42)
            }
        }

        /// `parseDouble` is `Double.init(String:)`, so it accepts every spelling
        /// Swift does, including hex floats, a leading plus, and a bare leading or
        /// trailing point.
        @Test("Every spelling Swift accepts parses to its value", arguments: [
            ("0x1p3", 8.0),
            ("+2.5", 2.5),
            (".5", 0.5),
            ("5.", 5.0),
            ("2e1", 20.0),
            ("-0", -0.0),
        ])
        func swiftDoubleSpellingsParse(_ pair: (String, Double)) {
            let (value, expected) = pair
            #expect(SettingsURIHandler.parseDouble(value) == expected, "\(value)")
        }

        /// And they reach `Defaults` unaltered when they land inside the key's
        /// range, so an unusual spelling is not quietly treated as malformed.
        @Test("An unusual spelling inside the range is stored verbatim", arguments: [
            ("0x1p3", 8.0),
            ("+2.5", 2.5),
            ("5.", 5.0),
            ("2e1", 20.0),
        ])
        func unusualSpellingsInsideTheRangeAreStored(_ pair: (String, Double)) throws {
            let (value, expected) = pair

            try withScratchDefaults { _ in
                // rehideInterval is bounded to 1...300, and every value here
                // sits inside it, so nothing is clamped on the way in.
                Defaults.set(42.0, forKey: .rehideInterval)
                #expect(SettingsURIHandler.handleSet(key: "rehideInterval", value: value, sender: "test"), "\(value)")
                #expect(Defaults.double(forKey: .rehideInterval) == expected, "\(value)")
            }
        }

        /// An unusual spelling gets no special treatment at the range check
        /// either: `.5` is below `rehideInterval`'s floor and is clamped to it,
        /// exactly as `0.5` would be.
        @Test("An unusual spelling below the range is clamped like any other", arguments: [".5", "+0.25", "0x1p-2"])
        func unusualSpellingsBelowTheRangeAreClamped(_ value: String) throws {
            try withScratchDefaults { _ in
                #expect(SettingsURIHandler.handleSet(key: "rehideInterval", value: value, sender: "test"), "\(value)")
                #expect(Defaults.double(forKey: .rehideInterval) == 1, "\(value)")
            }
        }

        /// The infinities `Double.init` produces, spelled out or from exponent
        /// overflow, must be caught by the finiteness check rather than clamped to
        /// the top of the range.
        @Test("Every infinity the parser produces is refused rather than clamped", arguments: [
            "infinity",
            "INFINITY",
            "Inf",
            "1e400",
            "-1e400",
            "-infinity",
        ])
        func infinitiesAreRefused(_ value: String) throws {
            let parsed = try #require(SettingsURIHandler.parseDouble(value), "\(value) must parse for this test to mean anything")
            #expect(!parsed.isFinite, "\(value)")

            try withScratchDefaults { _ in
                Defaults.set(42.0, forKey: .rehideInterval)
                #expect(!SettingsURIHandler.handleSet(key: "rehideInterval", value: value, sender: "test"), "\(value)")
                #expect(Defaults.double(forKey: .rehideInterval) == 42, "\(value) must not be clamped to the range bound")
            }
        }

        /// The same finiteness rule has to hold on every double key, not just
        /// the one with the widest range.
        @Test("Infinity is refused on every double key", arguments: doubleKeys)
        func infinityIsRefusedOnEveryDoubleKey(_ key: String) throws {
            try withScratchDefaults { _ in
                #expect(!SettingsURIHandler.handleSet(key: key, value: "infinity", sender: "test"), "\(key)")
                #expect(!SettingsURIHandler.handleSet(key: key, value: "nan", sender: "test"), "\(key)")
            }
        }
    }
}
