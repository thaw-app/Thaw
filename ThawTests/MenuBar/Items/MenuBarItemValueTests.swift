//
//  MenuBarItemValueTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Thaw

// MARK: - Fixtures

/// The name ``MenuBarItem/autoDetectedName`` derives from a source process,
/// computed for the process running the tests.
///
/// Every test that needs a *resolvable* source application passes the test
/// runner's own pid. `NSRunningApplication(processIdentifier:)` answers for it
/// on any machine, which no other pid can promise: a hard-coded pid may be
/// unused on one machine and a running app on the next.
private var testRunnerSourceName: String? {
    let app = NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
    return app?.localizedName ?? app?.bundleIdentifier
}

/// The pid of the process running the tests.
private var testRunnerPID: pid_t {
    ProcessInfo.processInfo.processIdentifier
}

private func appTag(
    _ title: String = "Status",
    instanceIndex: Int = 0,
    windowID: CGWindowID? = nil
) -> MenuBarItemTag {
    MenuBarItemTag.appItem(
        bundleID: "com.example.app",
        title: title,
        instanceIndex: instanceIndex,
        windowID: windowID
    )
}

private func namespacedTag(_ namespace: MenuBarItemTag.Namespace, _ title: String) -> MenuBarItemTag {
    MenuBarItemTag(namespace: namespace, title: title)
}

/// A fully specified item whose every stored field differs from the fixture
/// defaults, so a test that flips one field cannot accidentally flip it onto
/// the value it already had.
private func baseItem(
    tag: MenuBarItemTag = appTag(),
    windowID: CGWindowID = 501,
    ownerPID: pid_t = 4321,
    sourcePID: pid_t? = 8765,
    bounds: CGRect = CGRect(x: 100, y: 0, width: 24, height: 22),
    title: String? = "Status",
    isOnScreen: Bool = true
) -> MenuBarItem {
    MenuBarItem.fixture(
        tag: tag,
        windowID: windowID,
        bounds: bounds,
        sourcePID: sourcePID,
        ownerPID: ownerPID,
        title: title,
        isOnScreen: isOnScreen
    )
}

// MARK: - MenuBarItem Value Tests

/// Covers the value surface of ``MenuBarItem``: the capability flags it layers
/// on top of its tag, its identity (equality, hashing, `uniqueIdentifier`), its
/// textual forms, the name-detection pipeline, and the `Defaults`-backed custom
/// name.
///
/// Everything here is built from the memberwise initializer, so no window
/// server, display, or foreign process is involved. The window-derived half of
/// the file — `getMenuBarItemWindows`, `getMenuBarItems`, and the
/// `init(uncheckedItemWindow:)` chain — is deliberately out of reach: it needs
/// `Bridging`/CGS window lists and the XPC source-pid service.
@Suite("Menu bar item values")
struct MenuBarItemValueTests {
    // MARK: - Capability Flags

    /// The item-level flags are not pass-throughs of the tag: two of them are
    /// gated on whether the source process ever resolved.
    @Suite("Capability flags")
    struct CapabilityFlags {
        @Test("Resolving the source process of a generic Control Center slot trades hideability for movability")
        func genericControlCenterSlotFlipsWithSourceResolution() {
            let tag = namespacedTag(.controlCenter, "Item-13")
            let unresolved = MenuBarItem.fixture(tag: tag, windowID: 13, sourcePID: nil)
            let resolved = MenuBarItem.fixture(tag: tag, windowID: 13, sourcePID: 1234)

            // An unresolved slot is a system-owned placeholder: dragging it
            // times out, but nothing stops Thaw from hiding it.
            #expect(!unresolved.isMovable)
            #expect(unresolved.canBeHidden)
            #expect(!unresolved.isTransientControlCenterItem)

            // A resolved slot is a real transient module (Live Activities and
            // friends), which must not be swept into a hidden section.
            #expect(resolved.isMovable)
            #expect(!resolved.canBeHidden)
            #expect(resolved.isTransientControlCenterItem)
        }

        @Test("A named Control Center item is never transient")
        func namedControlCenterItemIsNotTransient() {
            let item = MenuBarItem.fixture(
                tag: namespacedTag(.controlCenter, "WiFi"),
                windowID: 14,
                sourcePID: 1234
            )

            #expect(!item.isTransientControlCenterItem)
            #expect(item.canBeHidden)
        }

        @Test("A generic title outside the Control Center namespace is never transient")
        func genericTitleInAnotherNamespaceIsNotTransient() {
            // "Item-0" is a common title; only Control Center's copies of it
            // are the dynamic modules.
            let item = MenuBarItem.fixture(tag: appTag("Item-0"), windowID: 15, sourcePID: 1234)

            #expect(!item.isTransientControlCenterItem)
            #expect(item.canBeHidden)
        }

        @Test("An item the tag refuses to hide stays unhideable even with a source process")
        func tagLevelHidingRefusalSurvives() {
            let item = MenuBarItem.fixture(tag: .faceTime, windowID: 16, sourcePID: 1234)

            #expect(!item.canBeHidden)
            #expect(!item.isTransientControlCenterItem)
        }

        @Test("An item macOS pins in place is not movable")
        func immovableTagIsNotMovable() {
            let item = MenuBarItem.fixture(tag: .clock, windowID: 17, sourcePID: 1234)

            #expect(!item.isMovable)
        }

        @Test("An ordinary app item is both movable and hideable")
        func ordinaryItemIsMovableAndHideable() {
            let item = MenuBarItem.fixture(tag: appTag(), windowID: 18, sourcePID: 1234)

            #expect(item.isMovable)
            #expect(item.canBeHidden)
        }

        @Test("A control item identifies itself as one")
        func controlItemIsRecognized() {
            let item = MenuBarItem.fixture(tag: .hiddenControlItem, windowID: 19, sourcePID: nil)

            #expect(item.isControlItem)
        }

        @Test("A spacer window counts as a control item")
        func spacerIsAControlItem() {
            let item = MenuBarItem.fixture(tag: appTag("Thaw.Spacer.1"), windowID: 20, sourcePID: nil)

            #expect(item.isControlItem)
        }

        @Test("An ordinary app item is not a control item")
        func ordinaryItemIsNotAControlItem() {
            #expect(!MenuBarItem.fixture(tag: appTag(), windowID: 21, sourcePID: 1234).isControlItem)
        }

        @Test("Control Center's BentoBox items are recognized")
        func bentoBoxIsRecognized() {
            let bento = MenuBarItem.fixture(tag: namespacedTag(.controlCenter, "BentoBox-1"), windowID: 22, sourcePID: 1234)
            let notBento = MenuBarItem.fixture(tag: namespacedTag(.controlCenter, "WiFi"), windowID: 23, sourcePID: 1234)
            // The prefix alone is not enough: an app is free to name a status
            // item "BentoBox-1" without being Control Center's.
            let impostor = MenuBarItem.fixture(tag: appTag("BentoBox-1"), windowID: 24, sourcePID: 1234)

            #expect(bento.isBentoBox)
            #expect(!notBento.isBentoBox)
            #expect(!impostor.isBentoBox)
        }

        @Test("A system status item clone is recognized whatever namespace it lands in")
        func systemCloneIsRecognizedInAnyNamespace() {
            // The WindowServer's clone windows resolve to a UUID namespace, the
            // owning process name, or even a real bundle id, so the title is
            // the only stable signal.
            let uuidClone = MenuBarItem.fixture(
                tag: namespacedTag(.uuid(UUID()), "System Status Item Clone"),
                windowID: 25,
                sourcePID: nil
            )
            let bundleClone = MenuBarItem.fixture(
                tag: appTag("System Status Item Clone"),
                windowID: 26,
                sourcePID: 1234
            )

            #expect(uuidClone.isSystemClone)
            #expect(bundleClone.isSystemClone)
        }

        @Test("An ordinary item is not a system clone")
        func ordinaryItemIsNotASystemClone() {
            #expect(!MenuBarItem.fixture(tag: appTag(), windowID: 27, sourcePID: 1234).isSystemClone)
        }
    }

    // MARK: - Identity

    /// `uniqueIdentifier`, equality, hashing and `logString` — the parts other
    /// subsystems key persisted state on.
    @Suite("Identity")
    struct Identity {
        @Test("An item without an instance index is identified by namespace and title")
        func uniqueIdentifierHasTwoComponents() {
            let item = baseItem(tag: appTag("Status"))

            #expect(item.uniqueIdentifier == "com.example.app:Status")
        }

        @Test("An item with an instance index appends it")
        func uniqueIdentifierHasThreeComponents() {
            let item = baseItem(tag: appTag("Status", instanceIndex: 2))

            #expect(item.uniqueIdentifier == "com.example.app:Status:2")
        }

        @Test("The window identifier is excluded from the unique identifier")
        func uniqueIdentifierIgnoresWindowIdentifiers() {
            // Window ids do not survive an app restart. If they leaked into the
            // identifier, every persisted custom name would be lost on relaunch.
            let first = baseItem(tag: appTag("Status", windowID: 77), windowID: 77)
            let second = baseItem(tag: appTag("Status", windowID: 91), windowID: 91)

            #expect(first.uniqueIdentifier == second.uniqueIdentifier)
        }

        @Test("Two items built from the same values are equal and hash alike")
        func identicalItemsAreEqual() {
            let first = baseItem()
            let second = baseItem()

            #expect(first == second)
            #expect(first.hashValue == second.hashValue)
            #expect(Set([first, second]).count == 1)
        }

        @Test("A different tag breaks equality")
        func tagParticipatesInEquality() {
            #expect(baseItem() != baseItem(tag: appTag("Other")))
        }

        @Test("A different window identifier breaks equality")
        func windowIDParticipatesInEquality() {
            #expect(baseItem() != baseItem(windowID: 502))
        }

        @Test("A different owner pid breaks equality")
        func ownerPIDParticipatesInEquality() {
            #expect(baseItem() != baseItem(ownerPID: 4322))
        }

        @Test("A different source pid breaks equality")
        func sourcePIDParticipatesInEquality() {
            #expect(baseItem() != baseItem(sourcePID: nil))
        }

        @Test("Different bounds break equality")
        func boundsParticipateInEquality() {
            #expect(baseItem() != baseItem(bounds: CGRect(x: 100, y: 0, width: 25, height: 22)))
        }

        @Test("A different window title breaks equality")
        func titleParticipatesInEquality() {
            #expect(baseItem() != baseItem(title: "Other"))
        }

        @Test("A different on-screen state breaks equality")
        func isOnScreenParticipatesInEquality() {
            #expect(baseItem() != baseItem(isOnScreen: false))
        }

        @Test("Every stored field is hashed, so single-field variants never collapse in a set")
        func hashingSeesEveryField() {
            // Hashing is what `Set<MenuBarItem>` and the item caches rely on;
            // a field missing from `hash(into:)` would still compare unequal
            // here, so the set count is the assertion that matters.
            let items: [MenuBarItem] = [
                baseItem(),
                baseItem(tag: appTag("Other")),
                baseItem(windowID: 502),
                baseItem(ownerPID: 4322),
                baseItem(sourcePID: nil),
                baseItem(bounds: CGRect(x: 101, y: 0, width: 24, height: 22)),
                baseItem(bounds: CGRect(x: 100, y: 1, width: 24, height: 22)),
                baseItem(bounds: CGRect(x: 100, y: 0, width: 25, height: 22)),
                baseItem(bounds: CGRect(x: 100, y: 0, width: 24, height: 23)),
                baseItem(title: "Other"),
                baseItem(isOnScreen: false),
            ]

            #expect(Set(items).count == items.count)
        }

        @Test("The log string pairs the tag with the live window identifier")
        func logStringCarriesTagAndWindowID() {
            // The tag's own window id is optional and often absent; the log
            // string has to report the window the item actually is.
            let item = baseItem(tag: appTag("Status"), windowID: 501)

            #expect(item.logString == "<com.example.app:Status (windowID: 501)>")
        }

        @Test("The log string reports the item's window even when the tag hides its own")
        func logStringReportsTheItemWindow() {
            // A system tag leaves the window id out of its own description
            // because it is not part of its identity. The log line still has
            // to say which window was actually seen.
            let item = baseItem(
                tag: MenuBarItemTag(namespace: .controlCenter, title: "WiFi", windowID: 77),
                windowID: 501
            )

            #expect(item.logString == "<com.apple.controlcenter:WiFi (windowID: 501)>")
        }
    }

    // MARK: - Auto-Detected Name

    /// The name-detection pipeline: the control-item short circuit, the two
    /// fallbacks, the per-namespace transforms, and the UUID rescue.
    ///
    /// Tests that need a resolvable source application use the test runner's
    /// own pid, so the result never depends on which apps happen to be running.
    @Suite("Auto-detected name")
    struct AutoDetectedName {
        @Test("A control item is named after the app, not after its internal title")
        func controlItemShortCircuits() {
            let item = MenuBarItem.fixture(tag: .hiddenControlItem, windowID: 30, sourcePID: testRunnerPID)

            #expect(item.autoDetectedName == Constants.displayName)
            #expect(item.autoDetectedName != MenuBarItemTag.hiddenControlItem.title)
        }

        @Test("A spacer is named after the app too")
        func spacerShortCircuits() {
            let item = MenuBarItem.fixture(tag: appTag("Thaw.Spacer.1"), windowID: 31, sourcePID: testRunnerPID)

            #expect(item.autoDetectedName == Constants.displayName)
        }

        @Test("An item whose source process never resolved falls back to a generic name")
        func unresolvedSourceFallsBack() {
            let item = MenuBarItem.fixture(tag: appTag("Status"), windowID: 32, sourcePID: nil)

            #expect(item.autoDetectedName == "Menu Bar Item")
        }

        @Test("An item without a window title falls back to the source application's name")
        func missingTitleFallsBackToSourceName() throws {
            let sourceName = try #require(testRunnerSourceName)
            // `MenuBarItem.fixture` substitutes the tag's title for a nil one,
            // so this branch needs the memberwise initializer directly.
            let item = MenuBarItem(
                tag: appTag("Status"),
                windowID: 33,
                ownerPID: 4321,
                sourcePID: testRunnerPID,
                bounds: CGRect(x: 0, y: 0, width: 24, height: 22),
                title: nil,
                isOnScreen: true
            )

            #expect(item.autoDetectedName == sourceName)
        }

        @Test("An ordinary app item is named after its application, not its window title")
        func ordinaryItemPrefersTheApplicationName() throws {
            let sourceName = try #require(testRunnerSourceName)
            let item = MenuBarItem.fixture(
                tag: appTag("StatusItemWindow"),
                windowID: 34,
                sourcePID: testRunnerPID
            )

            #expect(item.autoDetectedName == sourceName)
            #expect(item.autoDetectedName != "StatusItemWindow")
        }

        @Test("A Control Center item is named from its window title, title-cased")
        func controlCenterTitleIsTitleCased() {
            let item = MenuBarItem.fixture(
                tag: namespacedTag(.controlCenter, "BatteryStatus"),
                windowID: 35,
                sourcePID: testRunnerPID
            )

            #expect(item.autoDetectedName == "Battery Status")
        }

        @Test("Title casing leaves a single lowercase letter before a capital alone")
        func titleCasingKeepsWiFiIntact() {
            // The regex demands two lowercase letters before the capital
            // precisely so "WiFi" does not become "Wi Fi".
            let item = MenuBarItem.fixture(
                tag: namespacedTag(.controlCenter, "WiFi"),
                windowID: 36,
                sourcePID: testRunnerPID
            )

            #expect(item.autoDetectedName == "WiFi")
        }

        @Test("A Control Center hearing item is trimmed to its prefix")
        func controlCenterHearingIsTrimmedToPrefix() {
            // Without the prefix rule this would title-case into "Hearing Aids".
            let item = MenuBarItem.fixture(
                tag: namespacedTag(.controlCenter, "HearingAids"),
                windowID: 37,
                sourcePID: testRunnerPID
            )

            #expect(item.autoDetectedName == "Hearing")
        }

        @Test("A SystemUIServer Time Machine item is reduced to \"Time Machine\"")
        func systemUIServerTimeMachineIsExtracted() {
            let item = MenuBarItem.fixture(tag: .timeMachine, windowID: 38, sourcePID: testRunnerPID)

            #expect(item.autoDetectedName == "Time Machine")
        }

        @Test("Another SystemUIServer item is title-cased whole")
        func systemUIServerOtherTitleIsTitleCased() {
            let item = MenuBarItem.fixture(
                tag: namespacedTag(.systemUIServer, "VolumeControl"),
                windowID: 39,
                sourcePID: testRunnerPID
            )

            #expect(item.autoDetectedName == "Volume Control")
        }

        @Test(
            "A menu-agent namespace names the item after its application, never its title",
            arguments: [
                MenuBarItemTag.Namespace.passwords,
                MenuBarItemTag.Namespace.weather,
                MenuBarItemTag.Namespace.textInputMenuAgent,
            ]
        )
        func menuAgentNamespacesIgnoreTheTitle(namespace: MenuBarItemTag.Namespace) {
            let first = MenuBarItem.fixture(
                tag: namespacedTag(namespace, "PasswordsMenuBarExtra"),
                windowID: 40,
                sourcePID: testRunnerPID
            )
            let second = MenuBarItem.fixture(
                tag: namespacedTag(namespace, "SomethingElseEntirely"),
                windowID: 41,
                sourcePID: testRunnerPID
            )

            #expect(first.autoDetectedName == second.autoDetectedName)
            // These agents name themselves "<Feature>MenuBarExtra"; the
            // "Menu..." tail is stripped rather than shown to the user.
            #expect(!first.autoDetectedName.contains("Menu"))
            #expect(!first.autoDetectedName.isEmpty)
        }

        @Test("The Control Center BentoBox is named after Control Center itself")
        func controlCenterBentoBoxUsesTheApplicationName() throws {
            let sourceName = try #require(testRunnerSourceName)
            let item = MenuBarItem.fixture(
                tag: namespacedTag(.controlCenter, "BentoBox-0"),
                windowID: 42,
                sourcePID: testRunnerPID
            )

            #expect(item.autoDetectedName == sourceName)
            #expect(item.autoDetectedName != "BentoBox-0")
        }

        @Test("Any other BentoBox shows its raw window title")
        func otherBentoBoxesShowTheWindowTitle() {
            // The tag's title decides that this is a BentoBox; the *window*
            // title is what gets shown.
            let item = MenuBarItem.fixture(
                tag: namespacedTag(.controlCenter, "BentoBox-1"),
                windowID: 43,
                sourcePID: testRunnerPID,
                title: "BentoBox-7"
            )

            #expect(item.autoDetectedName == "BentoBox-7")
        }

        @Test("An item whose detected name is a bare UUID is qualified with its application")
        func uuidNamesAreQualified() throws {
            let sourceName = try #require(testRunnerSourceName)
            let uuid = UUID()
            let item = MenuBarItem.fixture(
                tag: namespacedTag(.controlCenter, uuid.uuidString),
                windowID: 44,
                sourcePID: testRunnerPID
            )

            // A raw UUID tells the user nothing, so the owning app is prepended.
            #expect(item.autoDetectedName == "\(sourceName) (\(uuid.uuidString))")
        }

        @Test("A name that merely contains a UUID is left alone")
        func namesContainingAUUIDAreNotQualified() {
            let uuid = UUID()
            let item = MenuBarItem.fixture(
                tag: namespacedTag(.controlCenter, "Widget-\(uuid.uuidString)"),
                windowID: 45,
                sourcePID: testRunnerPID
            )

            #expect(item.autoDetectedName == "Widget-\(uuid.uuidString)")
        }
    }

    // MARK: - Custom Names

    /// The `Defaults`-backed custom name and the display/description surface
    /// layered on it.
    ///
    /// `withScratchDefaults` swaps the process-wide `Defaults.store`, so this
    /// suite is `.serialized` as `ScratchDefaults.swift` requires. Without the
    /// scratch store these tests would both read and rewrite the running
    /// user's real custom names.
    @Suite("Custom names", .serialized)
    struct CustomNames {
        @Test("An item with nothing stored has no custom name")
        func customNameStartsEmpty() throws {
            try withScratchDefaults { _ in
                let item = baseItem(sourcePID: nil)

                #expect(item.customName == nil)
                #expect(item.displayName == item.autoDetectedName)
            }
        }

        @Test("A custom name is stored under the item's unique identifier")
        func customNameIsStoredUnderTheUniqueIdentifier() throws {
            try withScratchDefaults { _ in
                var item = baseItem(sourcePID: nil)
                item.customName = "Renamed"

                let stored = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
                #expect(stored["com.example.app:Status"] == "Renamed")
                #expect(item.customName == "Renamed")
            }
        }

        @Test("Clearing a custom name removes its entry instead of blanking it")
        func clearingACustomNameRemovesTheEntry() throws {
            try withScratchDefaults { _ in
                var item = baseItem(sourcePID: nil)
                item.customName = "Renamed"
                item.customName = nil

                let stored = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
                #expect(stored["com.example.app:Status"] == nil)
                #expect(item.customName == nil)
            }
        }

        @Test("A whitespace-only custom name is refused")
        func whitespaceOnlyCustomNameIsRefused() throws {
            try withScratchDefaults { _ in
                var item = baseItem(sourcePID: nil)
                item.customName = "Renamed"
                item.customName = "   "

                let stored = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
                #expect(stored["com.example.app:Status"] == nil)
                #expect(item.customName == nil)
            }
        }

        @Test("Renaming one item does not rename an unrelated one")
        func customNamesAreScopedToTheirIdentifier() throws {
            try withScratchDefaults { _ in
                var renamed = baseItem(tag: appTag("Status"), sourcePID: nil)
                let other = baseItem(tag: appTag("Other"), sourcePID: nil)
                renamed.customName = "Renamed"

                #expect(other.customName == nil)
            }
        }

        @Test("A custom name survives the item getting a new window identifier")
        func customNameIsSharedAcrossWindowIdentifiers() throws {
            try withScratchDefaults { _ in
                // This is the point of leaving the window id out of the
                // identifier: after a restart the same status item comes back
                // with a different window and must keep its name.
                var beforeRestart = baseItem(tag: appTag("Status", windowID: 77), windowID: 77, sourcePID: nil)
                let afterRestart = baseItem(tag: appTag("Status", windowID: 910), windowID: 910, sourcePID: nil)
                beforeRestart.customName = "Renamed"

                #expect(afterRestart.customName == "Renamed")
            }
        }

        @Test("Two instances of the same item are named separately")
        func instancesGetTheirOwnCustomNames() throws {
            try withScratchDefaults { _ in
                let first = baseItem(tag: appTag("Status", instanceIndex: 0), sourcePID: nil)
                var second = baseItem(tag: appTag("Status", instanceIndex: 1), sourcePID: nil)
                second.customName = "Work Account"

                #expect(first.customName == nil)
                #expect(second.customName == "Work Account")
            }
        }

        @Test("A custom name wins over the auto-detected one")
        func customNameTakesPrecedence() throws {
            try withScratchDefaults { _ in
                var item = baseItem(sourcePID: nil)
                item.customName = "Renamed"

                #expect(item.autoDetectedName == "Menu Bar Item")
                #expect(item.displayName == "Renamed")
            }
        }

        @Test("A blank stored name is ignored when displaying")
        func blankStoredNameIsIgnoredForDisplay() throws {
            try withScratchDefaults { _ in
                // Written straight to the store: the setter would have refused
                // this value, but a hand-edited plist or an imported profile
                // can still deliver it.
                Defaults.set(["com.example.app:Status": "   "], forKey: .menuBarItemCustomNames)
                let item = baseItem(sourcePID: nil)

                #expect(item.customName == "   ")
                #expect(item.displayName == item.autoDetectedName)
            }
        }

        @Test("The description pairs the display name with the tag")
        func descriptionUsesTheDisplayName() throws {
            try withScratchDefaults { _ in
                var item = baseItem(tag: appTag("Status"), sourcePID: nil)
                item.customName = "Renamed"

                #expect(item.description == "Renamed (com.example.app:Status)")
            }
        }

        @Test("The description falls back to the auto-detected name")
        func descriptionFallsBackToTheAutoDetectedName() throws {
            try withScratchDefaults { _ in
                let item = baseItem(tag: appTag("Status", windowID: 77), sourcePID: nil)

                #expect(item.description == "Menu Bar Item (com.example.app:Status (windowID: 77))")
            }
        }
    }
}
