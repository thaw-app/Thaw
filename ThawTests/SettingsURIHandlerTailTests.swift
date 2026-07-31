//
//  SettingsURIHandlerTailTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Testing
@testable import Thaw

/// Collects the notifications posted on `name` while `body` runs.
///
/// The three sibling suites each carry a private copy of this; it lives at file
/// scope here so the nested suites below can share one.
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

/// The tail of ``SettingsURIHandler`` that the three existing suites leave
/// alone.
///
/// Between them, `SettingsURIHandlerTests` (key tables, `parseBool`,
/// `parseDouble`, `PerDisplayScope`), `SettingsURIHandlerApplyTests` (`set` and
/// `toggle`, clamping, whitelist add/remove) and `SettingsURIHandlerGetTests`
/// (`get`, callback-scheme refusals, code-signature verification) already reach
/// most of the type. What is left is genuinely a tail, and it is grouped here
/// by what makes each part unreached rather than by API surface:
///
/// - **The empty-string display identifier.** Both `handlePerDisplaySet` and
///   `handlePerDisplayToggle` open with `if let uuid = displayUUID,
///   !uuid.isEmpty`. The sibling suites pass either `nil` or a real UUID, so
///   the `!uuid.isEmpty` half has never been the thing that decided the branch.
///   It matters because a `thaw://` URL carrying `display=` with nothing after
///   it produces exactly that, and it must scope the change the same way as
///   omitting the parameter entirely rather than addressing a display named "".
/// - **The `userInfo` a per-display change carries.** The posting helper builds
///   its payload from three independent `if let`/`if` arms, and
///   `DisplaySettingsManager` reads `value`, `stringValue` and `toggle` to
///   decide what kind of change it was handed. Sibling tests assert the key
///   that *is* present; nothing asserts that the other two are absent, so a
///   payload that carried all three would pass every existing test and leave
///   the reader picking whichever arm it checks first.
/// - **The per-display keys that cannot be toggled.** Only `iceBarLocation` is
///   currently asserted; `iceBarLayout` and `gridColumns` reach the same
///   refusal and are equally not Booleans.
/// - **`TeamIdentifierLookup.teamIdentifier` and `getAppIcon(for:)`**, which are
///   only ever called from `promptForAuthorization` — an `NSAlert.runModal`, so
///   unreachable from a test through its caller.
/// - **Removal purging the stored signing identity.** `removeFromWhitelist`
///   deletes both the whitelist entry and the identity; the sibling round-trip
///   test only observes the entry, so a removal that left the identity behind
///   would still pass it, and the stale identity would then be verified against
///   on the next authorization.
///
/// Deliberately **not** covered: `promptForAuthorization` (runs a modal
/// `NSAlert`), the success path of `sendCallbackResponse` (opens a URL through
/// `NSWorkspace`, which launches another app), and the display-enumerating
/// halves of `getAllSettings`/`getAllDisplays`, whose answers depend on the
/// monitors attached to the machine running the suite.
///
/// Every test that reads or writes a setting runs inside `withScratchDefaults`,
/// so the suite never touches the developer's real `com.stonerl.Thaw` domain —
/// which also means it starts from a known-empty whitelist rather than from
/// whatever the developer has authorized.
@MainActor
@Suite("Settings URI handler tail", .serialized)
struct SettingsURIHandlerTailTests {
    // MARK: - Signing identity lookups

    @MainActor
    @Suite("Signing identity lookups")
    struct SigningIdentityLookups {
        /// The accessor exists so `promptForAuthorization` can show the team in
        /// the alert. Both "no team" answers have to read as absent, and only
        /// the third has to hand a team back.
        @Test("Only a lookup that named a team reports one")
        func onlyATeamLookupReportsATeamIdentifier() {
            #expect(SettingsURIHandler.TeamIdentifierLookup.team("ABCDE12345").teamIdentifier == "ABCDE12345")
            #expect(SettingsURIHandler.TeamIdentifierLookup.noTeamIdentifier.teamIdentifier == nil)
            #expect(SettingsURIHandler.TeamIdentifierLookup.unavailable.teamIdentifier == nil)
        }

        /// "Signed by nobody" and "could not be read at all" are the two cases
        /// the type exists to keep apart, so they must not compare equal.
        @Test("An unsigned app and an unreadable one are different answers")
        func unsignedAndUnreadableAreDistinct() {
            #expect(SettingsURIHandler.TeamIdentifierLookup.noTeamIdentifier != .unavailable)
            #expect(SettingsURIHandler.TeamIdentifierLookup.team("ABCDE12345") != .noTeamIdentifier)
            #expect(SettingsURIHandler.TeamIdentifierLookup.team("ABCDE12345") != .unavailable)
            #expect(SettingsURIHandler.TeamIdentifierLookup.team("ABCDE12345") != .team("FGHIJ67890"))
            #expect(SettingsURIHandler.TeamIdentifierLookup.team("ABCDE12345") == .team("ABCDE12345"))
        }
    }

    // MARK: - App identity

    @MainActor
    @Suite("App identity")
    struct AppIdentity {
        @Test("An unknown bundle identifier has no icon")
        func unknownBundleIdentifierHasNoIcon() {
            #expect(SettingsURIHandler.getAppIcon(for: "com.example.NotInstalledAnywhere") == nil)
        }

        /// Finder ships with the system, so it resolves on any machine that can
        /// run this suite at all. The sibling suite already leans on that for
        /// `getAppName`.
        @Test("An installed app resolves to an icon")
        func installedAppResolvesToAnIcon() {
            #expect(SettingsURIHandler.getAppIcon(for: "com.apple.finder") != nil)
        }
    }

    // MARK: - An empty display identifier

    @MainActor
    @Suite("An empty display identifier")
    struct EmptyDisplayIdentifier {
        /// `display=` with nothing after it is not a display named "": it is a
        /// request that named no display, and has to be scoped like one.
        @Test(
            "An empty display identifier scopes a set the same way omitting it does",
            arguments: ["useIceBar", "alwaysShowHiddenItems", "iceBarLocation", "iceBarLayout", "gridColumns"]
        )
        func emptyDisplayIdentifierFallsBackToTheDefaultScopeOnSet(_ key: String) {
            let value: String = switch key {
            case "iceBarLocation": "dynamic"
            case "iceBarLayout": "grid"
            case "gridColumns": "4"
            default: "true"
            }
            let expectedScope: String = switch key {
            case "useIceBar": "active"
            case "alwaysShowHiddenItems": "allNonIceBar"
            default: "allEnabled"
            }

            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: key, value: value, sender: "test", displayUUID: "")
            }

            #expect(posted.count == 1, "\(key)")
            #expect(posted.first?.userInfo?["scope"] as? String == expectedScope, "\(key)")
        }

        @Test(
            "An empty display identifier scopes a toggle the same way omitting it does",
            arguments: [("useIceBar", "active"), ("alwaysShowHiddenItems", "allNonIceBar")]
        )
        func emptyDisplayIdentifierFallsBackToTheDefaultScopeOnToggle(_ pair: (String, String)) {
            let (key, expectedScope) = pair

            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleToggle(key: key, sender: "test", displayUUID: "")
            }

            #expect(posted.count == 1, "\(key)")
            #expect(posted.first?.userInfo?["scope"] as? String == expectedScope, "\(key)")
        }

        /// The empty identifier must not be mistaken for a malformed one
        /// either: a set that fell into the specific-display arm would be
        /// refused outright, and the caller would see a failure instead of a
        /// change applied to the default scope.
        @Test("An empty display identifier is not treated as a malformed one")
        func emptyDisplayIdentifierIsNotAMalformedOne() {
            #expect(
                SettingsURIHandler.handleSet(
                    key: "useIceBar",
                    value: "true",
                    sender: "test",
                    displayUUID: ""
                )
            )
            #expect(
                !SettingsURIHandler.handleSet(
                    key: "useIceBar",
                    value: "true",
                    sender: "test",
                    displayUUID: " "
                )
            )
        }
    }

    // MARK: - Toggles the per-display surface refuses

    @MainActor
    @Suite("Toggles the per-display surface refuses")
    struct UnsupportedPerDisplayToggles {
        /// Only the two Boolean per-display settings can be flipped without a
        /// value. A layout and a column count have nothing to flip to, so both
        /// have to be refused rather than quietly announced with no payload.
        @Test(
            "A per-display key that is not a Boolean cannot be toggled",
            arguments: ["iceBarLayout", "gridColumns"]
        )
        func nonBooleanPerDisplayKeyCannotBeToggled(_ key: String) {
            #expect(!SettingsURIHandler.handleToggle(key: key, sender: "test"))
            #expect(
                !SettingsURIHandler.handleToggle(
                    key: key,
                    sender: "test",
                    displayUUID: UUID().uuidString
                )
            )
        }

        /// A refusal has to be silent as well as false; a listener that acted on
        /// the notification would apply a change the handler declined to make.
        @Test("A refused per-display toggle announces nothing")
        func refusedPerDisplayToggleAnnouncesNothing() {
            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleToggle(key: "gridColumns", sender: "test")
                _ = SettingsURIHandler.handleToggle(key: "iceBarLayout", sender: "test")
            }

            #expect(posted.isEmpty)
        }
    }

    // MARK: - The shape of a per-display announcement

    @MainActor
    @Suite("The shape of a per-display announcement")
    struct AnnouncementPayloads {
        /// `DisplaySettingsManager` decides what kind of change it was handed by
        /// looking for these keys, so exactly one of the three has to be there.
        @Test("A Boolean change carries a value and neither of the other two")
        func booleanChangeCarriesOnlyItsValue() throws {
            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: "useIceBar", value: "true", sender: "test")
            }
            let userInfo = try #require(posted.first?.userInfo)

            #expect(userInfo["key"] as? String == "useIceBar")
            #expect(userInfo["value"] as? Bool == true)
            #expect(userInfo["stringValue"] == nil)
            #expect(userInfo["toggle"] == nil)
        }

        @Test("An enumeration change carries a string value and no Boolean")
        func enumerationChangeCarriesOnlyItsStringValue() throws {
            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: "iceBarLocation", value: "mousePointer", sender: "test")
            }
            let userInfo = try #require(posted.first?.userInfo)

            #expect(userInfo["key"] as? String == "iceBarLocation")
            #expect(userInfo["stringValue"] as? String != nil)
            #expect(userInfo["value"] == nil)
            #expect(userInfo["toggle"] == nil)
        }

        /// A toggle carries no value at all — the reader is being told to flip
        /// whatever it currently holds, not to store something.
        @Test("A toggle carries the toggle flag and no value")
        func toggleCarriesOnlyItsFlag() throws {
            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleToggle(key: "alwaysShowHiddenItems", sender: "test")
            }
            let userInfo = try #require(posted.first?.userInfo)

            #expect(userInfo["toggle"] as? Bool == true)
            #expect(userInfo["value"] == nil)
            #expect(userInfo["stringValue"] == nil)
        }

        /// The scope is the only routing information a reader gets, so it is
        /// always present, whichever arm built the payload.
        @Test("Every per-display announcement names a scope and a key")
        func everyAnnouncementNamesAScopeAndAKey() {
            let posted = notifications(named: .perDisplaySettingsDidChangeViaURI) {
                _ = SettingsURIHandler.handleSet(key: "useIceBar", value: "false", sender: "test")
                _ = SettingsURIHandler.handleSet(key: "gridColumns", value: "6", sender: "test")
                _ = SettingsURIHandler.handleToggle(key: "useIceBar", sender: "test")
            }

            #expect(posted.count == 3)
            for notification in posted {
                #expect(notification.userInfo?["scope"] as? String != nil)
                #expect(notification.userInfo?["key"] as? String != nil)
            }
        }
    }

    // MARK: - Whitelist bookkeeping

    @MainActor
    @Suite("Whitelist bookkeeping")
    struct WhitelistBookkeeping {
        /// Removal has to forget the recorded team as well as the entry. If it
        /// did not, re-authorizing the app afterwards would still be verified
        /// against the team it used to be authorized with — so an app that has
        /// since changed, or lost, its signature would be refused even though
        /// the user just approved it again.
        @Test("Removing an app forgets the signing identity it was authorized with")
        func removalForgetsTheSigningIdentity() throws {
            try withScratchDefaults { _ in
                // Finder resolves and names no team, so authorizing it *with* a
                // team is a mismatch the verifier refuses.
                SettingsURIHandler.addToWhitelist(bundleId: "com.apple.finder", teamIdentifier: "ABCDE12345")
                #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.apple.finder"))

                SettingsURIHandler.removeFromWhitelist(bundleId: "com.apple.finder")
                #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.apple.finder"))

                // Re-authorizing with no team is only accepted if the stale team
                // went away with the entry.
                SettingsURIHandler.addToWhitelist(bundleId: "com.apple.finder")
                #expect(SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.apple.finder"))
            }
        }

        @Test("Removing an app announces the change")
        func removalIsAnnounced() throws {
            try withScratchDefaults { _ in
                SettingsURIHandler.addToWhitelist(bundleId: "com.example.Alpha")

                let posted = notifications(named: .settingsURIWhitelistDidChange) {
                    SettingsURIHandler.removeFromWhitelist(bundleId: "com.example.Alpha")
                }

                #expect(!posted.isEmpty)
                #expect(SettingsURIHandler.getWhitelist().isEmpty)
            }
        }

        /// A store that was never written to has to read as "nobody is
        /// authorized and the feature is off", not as a missing value some
        /// caller has to interpret.
        @Test("An untouched store authorizes nobody and leaves the feature off")
        func untouchedStoreAuthorizesNobody() throws {
            try withScratchDefaults { _ in
                #expect(SettingsURIHandler.getWhitelist().isEmpty)
                #expect(!SettingsURIHandler.isEnabled())
                #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.apple.finder"))
            }
        }
    }

    // MARK: - Parameters the handler ignores or refuses

    @MainActor
    @Suite("Parameters the handler ignores or refuses")
    struct StrayParameters {
        /// The sender is only ever logged. A URL that arrived without an
        /// identifiable sender has already passed, or failed, the whitelist
        /// check by this point, so it must not fail a second time here.
        @Test("A request with no sender is still applied")
        func requestWithoutASenderIsApplied() throws {
            try withScratchDefaults { _ in
                #expect(SettingsURIHandler.handleSet(key: "showOnHover", value: "true", sender: nil))
                #expect(Defaults.bool(forKey: .showOnHover))

                #expect(SettingsURIHandler.handleToggle(key: "showOnHover", sender: nil))
                #expect(!Defaults.bool(forKey: .showOnHover))
            }
        }

        /// A display identifier on a global setting is meaningless rather than
        /// wrong: the setting has one value for the whole app, so the parameter
        /// is dropped instead of turning the request into a failure.
        @Test("A display identifier on a global setting is ignored, not refused")
        func displayIdentifierOnAGlobalSettingIsIgnored() throws {
            try withScratchDefaults { _ in
                #expect(
                    SettingsURIHandler.handleSet(
                        key: "showOnHover",
                        value: "true",
                        sender: "test",
                        displayUUID: UUID().uuidString
                    )
                )
                #expect(Defaults.bool(forKey: .showOnHover))
            }
        }

        /// `display=` with nothing after it names no display, and no attached
        /// screen can answer to it, so the request has to fail rather than fall
        /// back to the active display.
        @Test("A display get with an empty display identifier is refused")
        func displayGetWithAnEmptyIdentifierIsRefused() throws {
            try withScratchDefaults { _ in
                #expect(
                    !SettingsURIHandler.handleGet(
                        key: "display",
                        displayUUID: "",
                        callback: nil,
                        broadcast: true,
                        requestId: "req-empty-display"
                    )
                )
            }
        }
    }
}
