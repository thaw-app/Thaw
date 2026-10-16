//
//  SettingsURIHandlerGetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``SettingsURIHandler``'s `get` action, how it answers, and the
/// per-display lookups shared with `set` and `toggle`.
///
/// A callback URL would otherwise go to `NSWorkspace`, so every malformed or
/// dangerous one must be refused before it is opened. No test supplies a
/// callback the handler would accept, so nothing opens a URL or launches an app.
///
/// Response bodies are not observable here: the payload travels down a
/// callback URL, and the `distnoted` broadcast does not deliver back into the
/// test host. Tests assert the returned Boolean (a broadcast request succeeds
/// only when it produced data, like a callback request) or the per-display
/// notification's `userInfo`. The `iceBarLocation valid values` test calls
/// `getSettingValue` directly instead.
///
/// Every test runs inside `withScratchDefaults`.
@MainActor
@Suite("Settings URI handler get", .serialized)
struct SettingsURIHandlerGetTests {
    // MARK: Helpers

    /// Persists a configuration for `uuid` so the handler accepts it as a
    /// known display. A test cannot attach a screen, so this is the only way
    /// into the specific-display paths.
    private func persistConfiguration(
        _ configuration: DisplayIceBarConfiguration,
        forUUID uuid: String
    ) throws {
        let data = try JSONEncoder().encode([uuid: configuration])
        Defaults.set(data, forKey: .displayIceBarConfigurations)
    }

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

    // MARK: Response mechanism

    @Test("A get that names no way to answer is refused")
    func getWithoutResponseMechanismIsRefused() throws {
        try withScratchDefaults { _ in
            #expect(
                !SettingsURIHandler.handleGet(
                    key: "all",
                    displayUUID: nil,
                    callback: nil,
                    broadcast: false,
                    requestId: "req-no-mechanism"
                )
            )
        }
    }

    @Test("A keyless get that names no way to answer is refused too")
    func keylessGetWithoutResponseMechanismIsRefused() throws {
        try withScratchDefaults { _ in
            // The missing response mechanism is checked before the missing key, so
            // this must not be mistaken for the "no key specified" error path.
            #expect(
                !SettingsURIHandler.handleGet(
                    key: nil,
                    displayUUID: nil,
                    callback: nil,
                    broadcast: false,
                    requestId: nil
                )
            )
        }
    }

    // MARK: Callback URL refusal

    @Test("A callback URL with a dangerous scheme is refused before it is opened", arguments: [
        "file:///tmp/thaw-callback",
        "javascript:alert(1)",
        "data:text/plain;base64,aGVsbG8=",
        "about:blank",
        "blob:https://example.com/1234",
        "x-apple-systempreferences:com.example",
        "x-apple-helpbasic:anything",
    ])
    func dangerousCallbackSchemeIsRefused(_ callback: String) throws {
        try withScratchDefaults { _ in
            #expect(
                !SettingsURIHandler.handleGet(
                    key: "version",
                    displayUUID: nil,
                    callback: callback,
                    broadcast: false,
                    requestId: "req-dangerous-scheme"
                )
            )
        }
    }

    @Test("A dangerous callback scheme is refused whatever its casing", arguments: [
        "FILE:///tmp/thaw-callback",
        "JavaScript:alert(1)",
        "DATA:text/plain,hi",
        "AbOuT:blank",
        "X-Apple-SystemPreferences:com.example",
    ])
    func dangerousCallbackSchemeIsRefusedCaseInsensitively(_ callback: String) throws {
        try withScratchDefaults { _ in
            #expect(
                !SettingsURIHandler.handleGet(
                    key: "version",
                    displayUUID: nil,
                    callback: callback,
                    broadcast: false,
                    requestId: "req-dangerous-scheme-case"
                )
            )
        }
    }

    @Test("A callback URL without a usable scheme is refused", arguments: [
        "",
        "callback",
        "not a url at all",
        "/var/tmp/thaw-callback",
        "//example.com/thaw-callback",
        "://nope",
    ])
    func schemelessCallbackIsRefused(_ callback: String) throws {
        try withScratchDefaults { _ in
            // Whether the string fails to parse or parses without a scheme, the
            // handler has no app to hand it to and must refuse either way.
            #expect(
                !SettingsURIHandler.handleGet(
                    key: "version",
                    displayUUID: nil,
                    callback: callback,
                    broadcast: false,
                    requestId: "req-schemeless"
                )
            )
        }
    }

    @Test("A refused callback is refused for every readable key", arguments: [
        "all",
        "displays",
        "display",
        "version",
        "showOnHover",
        "rehideInterval",
        "rehideStrategy",
        "useIceBar",
    ])
    func refusedCallbackIsRefusedForEveryKey(_ key: String) throws {
        try withScratchDefaults { _ in
            // The response is built before the callback is validated, so this also
            // pins that no key's response shape can talk its way past the check.
            #expect(
                !SettingsURIHandler.handleGet(
                    key: key,
                    displayUUID: nil,
                    callback: "javascript:alert(1)",
                    broadcast: false,
                    requestId: "req-\(key)"
                )
            )
        }
    }

    @Test("A refused callback is not quietly retried as a broadcast")
    func refusedCallbackIsNotRetriedAsABroadcast() throws {
        try withScratchDefaults { _ in
            // The callback wins whenever both are given, so a callback the handler
            // will not open fails the whole request instead of downgrading to the
            // broadcast the caller also asked for.
            #expect(
                !SettingsURIHandler.handleGet(
                    key: "all",
                    displayUUID: nil,
                    callback: "file:///tmp/thaw-callback",
                    broadcast: true,
                    requestId: "req-both"
                )
            )
        }
    }

    /// Unlike most schemeless cases, these do not parse at all, a different
    /// branch, so each case asserts that first.
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

    // MARK: Broadcast response

    @Test("A broadcast get is answered")
    func broadcastGetIsAnswered() throws {
        try withScratchDefaults { _ in
            #expect(
                SettingsURIHandler.handleGet(
                    key: "all",
                    displayUUID: nil,
                    callback: nil,
                    broadcast: true,
                    requestId: "req-ack"
                )
            )
        }
    }

    @Test("A get without a request id is answered all the same")
    func getWithoutARequestIdIsAnswered() throws {
        try withScratchDefaults { _ in
            // The handler mints a UUID when the caller omits one, so a missing
            // request id must not be mistaken for a malformed request.
            #expect(
                SettingsURIHandler.handleGet(
                    key: "version",
                    displayUUID: nil,
                    callback: nil,
                    broadcast: true,
                    requestId: nil
                )
            )
        }
    }

    @Test("An unknown key is refused over the broadcast channel", arguments: [
        "definitelyNotASetting",
        "",
        "SHOWONHOVER",
        "showOnHove",
    ])
    func unknownKeyIsRefusedOverBroadcast(_ key: String) throws {
        try withScratchDefaults { _ in
            // The acknowledgement goes out unchanged, since integrators read its fixed
            // shape, but the handler reports the failure to its caller, as the callback
            // path does.
            #expect(
                !SettingsURIHandler.handleGet(
                    key: key,
                    displayUUID: nil,
                    callback: nil,
                    broadcast: true,
                    requestId: "req-unknown-key"
                ),
                "key=\(key)"
            )
        }
    }

    @Test("A keyless broadcast get reports the error it built")
    func keylessBroadcastGetIsRefused() throws {
        try withScratchDefaults { _ in
            // Same shape as an unknown key: the "No key specified" response is not
            // deliverable over the broadcast channel, so the request fails.
            #expect(
                !SettingsURIHandler.handleGet(
                    key: nil,
                    displayUUID: nil,
                    callback: nil,
                    broadcast: true,
                    requestId: "req-no-key"
                )
            )
        }
    }

    @Test("Every readable key is answered over the broadcast channel", arguments: [
        "all",
        "displays",
        "version",
        "showOnHover",
        "autoRehide",
        "rehideInterval",
        "showOnHoverDelay",
        "rehideStrategy",
        "useIceBar",
        "iceBarLocation",
        "alwaysShowHiddenItems",
        "iceBarLayout",
        "gridColumns",
    ])
    func everyReadableKeyIsAnswered(_ key: String) throws {
        try withScratchDefaults { _ in
            // Reading a key must never fail the request: `all` walks every setting
            // and every attached screen, and the per-display keys resolve against
            // the active display when no UUID is given.
            #expect(
                SettingsURIHandler.handleGet(
                    key: key,
                    displayUUID: nil,
                    callback: nil,
                    broadcast: true,
                    requestId: "req-read-\(key)"
                )
            )
        }
    }

    @Test("A display get for a known display is answered")
    func displayGetForAKnownDisplayIsAnswered() throws {
        try withScratchDefaults { _ in
            let knownUUID = UUID().uuidString
            try persistConfiguration(.defaultConfiguration, forUUID: knownUUID)

            #expect(
                SettingsURIHandler.handleGet(
                    key: "display",
                    displayUUID: knownUUID,
                    callback: nil,
                    broadcast: true,
                    requestId: "req-display-known"
                )
            )
        }
    }

    @Test("A display get that names no known display is refused", arguments: [
        "unknown",
        "malformed",
        "missing",
    ])
    func displayGetWithoutAKnownUUIDIsRefused(_ variant: String) throws {
        try withScratchDefaults { _ in
            try persistConfiguration(.defaultConfiguration, forUUID: UUID().uuidString)

            let displayUUID: String? = switch variant {
            case "unknown": UUID().uuidString
            case "malformed": "not-a-uuid"
            default: nil
            }

            // A "Display not found" response cannot travel over the broadcast
            // channel, so the failure has to reach the caller through the return
            // value instead of being masked by the acknowledgement.
            #expect(
                !SettingsURIHandler.handleGet(
                    key: "display",
                    displayUUID: displayUUID,
                    callback: nil,
                    broadcast: true,
                    requestId: "req-display-\(variant)"
                ),
                "display=\(variant)"
            )
        }
    }

    @Test("A per-display key is readable for a display that only exists in persisted configuration")
    func perDisplayKeyIsReadableForAPersistedDisplay() throws {
        try withScratchDefaults { _ in
            let uuid = UUID().uuidString
            try persistConfiguration(.defaultConfiguration.withGridColumns(7), forUUID: uuid)

            for key in SettingsURIHandler.perDisplayKeys {
                #expect(
                    SettingsURIHandler.handleGet(
                        key: key,
                        displayUUID: uuid,
                        callback: nil,
                        broadcast: true,
                        requestId: "req-persisted-\(key)"
                    ),
                    "\(key)"
                )
            }
        }
    }

    @Test("Every key the handler publishes is readable", arguments: SettingsURIKeyTable.globalReadableKeys)
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

            for key in SettingsURIKeyTable.globalReadableKeys {
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

    /// The individual-key read resolves the display before it looks at the
    /// key at all, and reports a missing setting when it cannot. Every test
    /// here persists a *different* display first, so the refusal is the
    /// named identifier being unknown rather than the store being empty.
    @Test("A per-display read for a display that is not there is refused", arguments: SettingsURIKeyTable.perDisplayKeys)
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
    @Test("A per-display read with a malformed identifier is refused", arguments: SettingsURIKeyTable.perDisplayKeys)
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

    // MARK: Stored values the enumeration cannot name

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

    // MARK: iceBarLocation valid values

    @Test("iceBarLocation advertises every IceBarLocation case, including leftAligned and rightAligned")
    func iceBarLocationGetListsAllValidValues() throws {
        try withScratchDefaults { _ in
            let uuid = UUID().uuidString
            try persistConfiguration(.defaultConfiguration, forUUID: uuid)

            // validValues drifted to three entries when IceBarLocation grew to five
            // cases, hiding leftAligned and rightAligned from thaw://get. Derive the
            // expectation from IceBarLocation so no future case can drop out.
            let value = try #require(
                SettingsURIHandler.getSettingValue(key: "iceBarLocation", displayUUID: uuid)
            )
            let validValues = try #require(value["validValues"] as? [String: Int])

            #expect(validValues.count == IceBarLocation.allCases.count)
            for location in IceBarLocation.allCases {
                #expect(validValues[String(describing: location)] == location.rawValue, "\(location)")
            }

            // Pin the two cases that were missing before the fix in plain terms.
            #expect(validValues["leftAligned"] == 3)
            #expect(validValues["rightAligned"] == 4)
        }
    }

    // MARK: Per-display writes to a specific display

    @Test("A set for a specific display is announced with that display's scope")
    func specificDisplaySetIsAnnouncedWithItsScope() throws {
        try withScratchDefaults { _ in
            let uuid = UUID().uuidString
            try persistConfiguration(.defaultConfiguration, forUUID: uuid)

            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(
                    key: "useIceBar",
                    value: "true",
                    sender: "test",
                    displayUUID: uuid
                )
            }

            #expect(posted.count == 1)
            #expect(posted.first?.userInfo?["key"] as? String == "useIceBar")
            #expect(posted.first?.userInfo?["value"] as? Bool == true)
            #expect(posted.first?.userInfo?["scope"] as? String == "specific:\(uuid)")
        }
    }

    @Test("Every per-display key can be set on a specific display")
    func everyPerDisplayKeyIsSettableOnASpecificDisplay() throws {
        try withScratchDefaults { _ in
            let uuid = UUID().uuidString
            try persistConfiguration(.defaultConfiguration, forUUID: uuid)

            let cases = [
                ("useIceBar", "true"),
                ("alwaysShowHiddenItems", "true"),
                ("iceBarLocation", "mousePointer"),
                ("iceBarLayout", "grid"),
                ("gridColumns", "6"),
            ]

            for (key, value) in cases {
                let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                    _ = SettingsURIHandler.handleSet(
                        key: key,
                        value: value,
                        sender: "test",
                        displayUUID: uuid
                    )
                }
                #expect(posted.first?.userInfo?["scope"] as? String == "specific:\(uuid)", "\(key)")
            }
        }
    }

    @Test("A set for a known display still refuses an unparsable value")
    func specificDisplaySetStillValidatesTheValue() throws {
        try withScratchDefaults { _ in
            let uuid = UUID().uuidString
            try persistConfiguration(.defaultConfiguration, forUUID: uuid)

            let cases = [
                ("useIceBar", "maybe"),
                ("alwaysShowHiddenItems", "sometimes"),
                ("iceBarLocation", "sideways"),
                ("iceBarLayout", "diagonal"),
                ("gridColumns", "several"),
            ]

            for (key, value) in cases {
                #expect(
                    !SettingsURIHandler.handleSet(
                        key: key,
                        value: value,
                        sender: "test",
                        displayUUID: uuid
                    ),
                    "\(key)=\(value)"
                )
            }
        }
    }

    @Test("gridColumns is clamped into 2...10 for a specific display too")
    func gridColumnsIsClampedForASpecificDisplay() throws {
        try withScratchDefaults { _ in
            let uuid = UUID().uuidString
            try persistConfiguration(.defaultConfiguration, forUUID: uuid)

            for (requested, expected) in [("0", "2"), ("1", "2"), ("-7", "2"), ("11", "10"), ("400", "10"), ("5", "5")] {
                let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                    _ = SettingsURIHandler.handleSet(
                        key: "gridColumns",
                        value: requested,
                        sender: "test",
                        displayUUID: uuid
                    )
                }
                #expect(posted.first?.userInfo?["stringValue"] as? String == expected, "gridColumns=\(requested)")
            }
        }
    }

    @Test("A display known only by a persisted configuration is still checked for UUID shape")
    func specificDisplaySetChecksTheUUIDShapeFirst() throws {
        try withScratchDefaults { _ in
            let uuid = UUID().uuidString
            try persistConfiguration(.defaultConfiguration, forUUID: uuid)

            // A well-formed but unlisted UUID and a malformed one are both refused,
            // so persisting one configuration does not open the door to any other.
            #expect(
                !SettingsURIHandler.handleSet(
                    key: "useIceBar",
                    value: "true",
                    sender: "test",
                    displayUUID: UUID().uuidString
                )
            )
            #expect(
                !SettingsURIHandler.handleSet(
                    key: "useIceBar",
                    value: "true",
                    sender: "test",
                    displayUUID: "\(uuid)-extra"
                )
            )
        }
    }

    // MARK: Code-signature verification

    @Test("An empty bundle identifier is refused before any signature check")
    func emptyBundleIdentifierIsRefused() throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: ""))
        }
    }

    @Test("An app authorized with a team identifier fails verification once it is gone")
    func storedTeamIdentifierFailsWhenTheAppIsGone() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Ghost", teamIdentifier: "ABCDE12345")

            // Nothing on disk answers to that bundle ID, so no current team
            // identifier can be read and the stored one cannot be matched.
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.example.Ghost"))
        }
    }

    @Test("An app authorized without a team identifier fails once it cannot be located")
    func missingTeamIdentifierFailsForAnUnresolvableApp() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Ghost")

            // An entry with no stored team identifier is only accepted when the app
            // is there to read and genuinely names no team. A bundle ID that
            // resolves to nothing tells us nothing, and anything can claim one.
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.example.Ghost"))
        }
    }

    @Test("An app authorized without a team identifier still passes while it can be read")
    func missingTeamIdentifierPassesForAResolvableApp() throws {
        try withScratchDefaults { _ in
            // Finder is a platform binary: it resolves, and its signature reads back
            // without a team identifier. That is the case a legacy entry was made
            // for, and it must keep working.
            SettingsURIHandler.addToWhitelist(bundleId: "com.apple.finder")

            #expect(SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.apple.finder"))
        }
    }

    @Test("An app that names no team reads differently from one that cannot be located")
    func teamIdentifierLookupSeparatesUnsignedFromUnreadable() {
        #expect(SettingsURIHandler.lookUpTeamIdentifier(for: "com.apple.finder") == .noTeamIdentifier)
        #expect(SettingsURIHandler.lookUpTeamIdentifier(for: "com.example.NotInstalledAnywhere") == .unavailable)
    }

    @Test("Re-authorizing an app already on the whitelist records its signing identity")
    func reauthorizingRecordsTheSigningIdentity() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.apple.finder")
            #expect(SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.apple.finder"))

            // The identity must be recorded even though the bundle ID is already
            // listed. The entry is then verified against it instead of the
            // unsigned-legacy rule, and Finder does not carry that team.
            SettingsURIHandler.addToWhitelist(bundleId: "com.apple.finder", teamIdentifier: "ABCDE12345")

            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.apple.finder"))
            #expect(SettingsURIHandler.getWhitelist().filter { $0 == "com.apple.finder" }.count == 1)
        }
    }

    @Test("Recording a signing identity for a listed app announces the change")
    func recordingASigningIdentityIsAnnounced() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Ghost")

            let posted = notifications(named: .settingsURIWhitelistDidChange) {
                SettingsURIHandler.addToWhitelist(bundleId: "com.example.Ghost", teamIdentifier: "ABCDE12345")
            }

            #expect(!posted.isEmpty)
        }
    }

    @Test("Re-adding a listed app with nothing new to store announces nothing")
    func redundantReauthorizationIsSilent() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Ghost", teamIdentifier: "ABCDE12345")

            let posted = notifications(named: .settingsURIWhitelistDidChange) {
                SettingsURIHandler.addToWhitelist(bundleId: "com.example.Ghost", teamIdentifier: "ABCDE12345")
            }

            #expect(posted.isEmpty)
        }
    }

    // MARK: App identity

    @Test("An unknown bundle identifier has no display name")
    func unknownBundleIdentifierHasNoDisplayName() {
        #expect(SettingsURIHandler.getAppName(for: "com.example.NotInstalledAnywhere") == nil)
    }

    @Test("An installed app resolves to a display name")
    func installedAppResolvesToADisplayName() throws {
        let name = try #require(SettingsURIHandler.getAppName(for: "com.apple.finder"))
        #expect(!name.isEmpty)
    }
}
