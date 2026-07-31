//
//  GeneralSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``GeneralSettings``' setup surface: the `Defaults` load performed by
/// `performSetup(with:)` and the Settings-URI notification it subscribes to.
///
/// Both halves are trust boundaries of a sort. The load reads whatever is in
/// `UserDefaults` — possibly written by an older build, a hand-edited plist, or
/// a partially failed import — so an unrecognized enum raw value or undecodable
/// icon payload has to leave the shipped default standing rather than crash or
/// blank the icon. The notification arrives on behalf of a *third-party app*
/// that sent a `thaw://` URL, so a key this model does not own, or a payload of
/// the wrong type, must be dropped.
///
/// `SettingsURIHandlerApplyTests` covers the sending side of the same
/// notification; the two suites have to agree on the `userInfo` shape.
///
/// The model persists through `didSet` and `Defaults` is hardcoded to
/// `.standard`, so the suite snapshots the keys it touches and restores them
/// afterwards.
///
/// Snapshotting the *keys* rather than the whole persistent domain is
/// deliberate: suites run concurrently, so a whole-domain snapshot taken while
/// another suite holds scratch values captures them, and restoring it writes
/// them back over the developer's own settings. Restoring one model's keys
/// cannot reach anything this suite did not write.
@MainActor
@Suite("General settings", .serialized)
final class GeneralSettingsTests {
    /// The keys this suite reads and writes.
    private static let touchedKeys: [Defaults.Key] = [
        .showIceIcon,
        .iceIcon,
        .customIceIconIsTemplate,
        .useIceBar,
        .useIceBarOnlyOnNotchedDisplay,
        .iceBarLocation,
        .iceBarLocationOnHotkey,
        .showOnClick,
        .showOnDoubleClick,
        .showOnHover,
        .showOnScroll,
        .autoRehide,
        .rehideStrategy,
        .rehideInterval,
    ]

    private let savedDefaults: [Defaults.Key: Any?]

    init() {
        savedDefaults = Dictionary(
            uniqueKeysWithValues: Self.touchedKeys.map { ($0, Defaults.object(forKey: $0)) }
        )
    }

    /// Isolated so the non-Sendable snapshot is reachable here; the suite is
    /// already `@MainActor`.
    @MainActor
    deinit {
        for (key, value) in savedDefaults {
            if let value {
                Defaults.set(value, forKey: key)
            } else {
                Defaults.removeObject(forKey: key)
            }
        }
    }

    /// Returns a model that has run its setup against the current `Defaults`.
    ///
    /// The app state is unused by this model, so setup runs without one.
    private func makeSettings() -> GeneralSettings {
        let settings = GeneralSettings()
        settings.performSetup()
        return settings
    }

    /// Removes every key the model loads, so a test starts from the state of a
    /// first launch rather than from the developer's own settings.
    private func clearStoredSettings() {
        for key in Self.touchedKeys {
            Defaults.removeObject(forKey: key)
        }
    }

    /// Posts external settings changes and waits for the model to handle them.
    ///
    /// `observeSettingsChangesViaURI` delivers on `DispatchQueue.main`, so the
    /// handlers have only been enqueued by the time the posts return. They are
    /// enqueued in order, so a block queued after the last post lands behind
    /// every one of them — a deterministic wait rather than a sleep.
    ///
    /// Changes are posted as a batch so that a test suspends once rather than
    /// once per change: every suspension is a window in which another suite can
    /// run while this one's scratch values sit in `Defaults`.
    ///
    /// The model listens on `NotificationCenter.default`, so a suite that posts
    /// its own changes — `SettingsURIHandlerApplyTests` does — reaches this
    /// model too. Assertions after a post therefore stick to keys no other
    /// suite writes, except where the setting under test is the only one of its
    /// kind.
    private func postExternalChanges(_ changes: [[String: Any]]) async {
        for change in changes {
            NotificationCenter.default.post(
                name: .settingsDidChangeViaURI,
                object: nil,
                userInfo: change
            )
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    /// Posts a single external settings change and waits for the model.
    private func postExternalChange(_ change: [String: Any]) async {
        await postExternalChanges([change])
    }

    // MARK: Initial load

    @Test("Stored values are loaded into the model")
    func storedValuesAreLoaded() {
        clearStoredSettings()
        Defaults.set(false, forKey: .showIceIcon)
        Defaults.set(true, forKey: .customIceIconIsTemplate)
        Defaults.set(true, forKey: .useIceBar)
        Defaults.set(true, forKey: .useIceBarOnlyOnNotchedDisplay)
        Defaults.set(true, forKey: .iceBarLocationOnHotkey)
        Defaults.set(false, forKey: .showOnClick)
        Defaults.set(false, forKey: .showOnDoubleClick)
        Defaults.set(true, forKey: .showOnHover)
        Defaults.set(false, forKey: .showOnScroll)
        Defaults.set(false, forKey: .autoRehide)
        Defaults.set(42.5, forKey: .rehideInterval)

        let settings = makeSettings()

        #expect(!settings.showIceIcon)
        #expect(settings.customIceIconIsTemplate)
        #expect(settings.useIceBar)
        #expect(settings.useIceBarOnlyOnNotchedDisplay)
        #expect(settings.iceBarLocationOnHotkey)
        #expect(!settings.showOnClick)
        #expect(!settings.showOnDoubleClick)
        #expect(settings.showOnHover)
        #expect(!settings.showOnScroll)
        #expect(!settings.autoRehide)
        #expect(settings.rehideInterval == 42.5)
    }

    @Test("Absent keys leave the shipped defaults in place")
    func absentKeysLeaveTheDefaults() {
        clearStoredSettings()

        let settings = makeSettings()

        #expect(settings.showIceIcon == Defaults.DefaultValue.showIceIcon)
        #expect(settings.iceIcon == Defaults.DefaultValue.iceIcon)
        #expect(settings.customIceIconIsTemplate == Defaults.DefaultValue.customIceIconIsTemplate)
        #expect(settings.useIceBar == Defaults.DefaultValue.useIceBar)
        #expect(settings.iceBarLocation == Defaults.DefaultValue.iceBarLocation)
        #expect(settings.showOnHover == Defaults.DefaultValue.showOnHover)
        #expect(settings.autoRehide == Defaults.DefaultValue.autoRehide)
        #expect(settings.rehideStrategy == Defaults.DefaultValue.rehideStrategy)
        #expect(settings.rehideInterval == Defaults.DefaultValue.rehideInterval)
        #expect(settings.lastCustomIceIcon == nil)
    }

    @Test("Stored enum raw values are loaded")
    func storedEnumRawValuesAreLoaded() {
        clearStoredSettings()
        Defaults.set(IceBarLocation.leftAligned.rawValue, forKey: .iceBarLocation)
        Defaults.set(RehideStrategy.focusedApp.rawValue, forKey: .rehideStrategy)

        let settings = makeSettings()

        #expect(settings.iceBarLocation == .leftAligned)
        #expect(settings.rehideStrategy == .focusedApp)
    }

    @Test("An unrecognized enum raw value leaves the default in place")
    func unrecognizedEnumRawValueIsIgnored() {
        clearStoredSettings()
        Defaults.set(99, forKey: .iceBarLocation)
        Defaults.set(-1, forKey: .rehideStrategy)

        let settings = makeSettings()

        #expect(settings.iceBarLocation == Defaults.DefaultValue.iceBarLocation)
        #expect(settings.rehideStrategy == Defaults.DefaultValue.rehideStrategy)
    }

    @Test("A stored custom icon is loaded and remembered as the last custom icon")
    func storedCustomIconIsLoaded() throws {
        clearStoredSettings()
        let custom = ControlItemImageSet(name: .custom, image: .symbol("star"))
        let data = try JSONEncoder().encode(custom)
        Defaults.set(data, forKey: .iceIcon)

        let settings = makeSettings()

        #expect(settings.iceIcon == custom)
        #expect(settings.lastCustomIceIcon == custom)
    }

    @Test("A stored built-in icon is loaded without becoming the last custom icon")
    func storedBuiltInIconIsNotRemembered() throws {
        clearStoredSettings()
        let builtIn = ControlItemImageSet(name: .dot, image: .symbol("circle.fill"))
        let data = try JSONEncoder().encode(builtIn)
        Defaults.set(data, forKey: .iceIcon)

        let settings = makeSettings()

        #expect(settings.iceIcon == builtIn)
        #expect(settings.lastCustomIceIcon == nil)
    }

    @Test("Undecodable icon data leaves the default icon in place")
    func undecodableIconDataIsIgnored() {
        clearStoredSettings()
        Defaults.set(Data("not an icon".utf8), forKey: .iceIcon)

        let settings = makeSettings()

        #expect(settings.iceIcon == Defaults.DefaultValue.iceIcon)
        #expect(settings.lastCustomIceIcon == nil)
    }

    // MARK: Persistence

    @Test("A property change is written straight through to Defaults")
    func propertyChangesArePersisted() {
        clearStoredSettings()
        let settings = makeSettings()

        settings.customIceIconIsTemplate = true
        settings.rehideInterval = 77
        settings.rehideStrategy = .timed
        settings.iceBarLocation = .mousePointer

        #expect(Defaults.bool(forKey: .customIceIconIsTemplate))
        #expect(Defaults.double(forKey: .rehideInterval) == 77)
        #expect(Defaults.integer(forKey: .rehideStrategy) == RehideStrategy.timed.rawValue)
        #expect(Defaults.integer(forKey: .iceBarLocation) == IceBarLocation.mousePointer.rawValue)
    }

    @Test("Stored values survive a reload")
    func storedValuesRoundTrip() {
        clearStoredSettings()
        let settings = makeSettings()
        settings.customIceIconIsTemplate = true
        settings.rehideStrategy = .timed

        let reloaded = makeSettings()

        #expect(reloaded.customIceIconIsTemplate)
        #expect(reloaded.rehideStrategy == .timed)
    }

    // MARK: External changes

    @Test("An external boolean change updates the matching property")
    func externalBooleanChangeIsApplied() async {
        clearStoredSettings()
        let settings = makeSettings()

        await postExternalChanges([
            ["key": "showIceIcon", "value": false],
            ["key": "customIceIconIsTemplate", "value": true],
            ["key": "showOnScroll", "value": false],
            ["key": "showOnClick", "value": false],
            ["key": "showOnDoubleClick", "value": false],
            ["key": "useIceBar", "value": true],
            ["key": "useIceBarOnlyOnNotchedDisplay", "value": true],
            ["key": "iceBarLocationOnHotkey", "value": true],
        ])

        #expect(!settings.showIceIcon)
        #expect(settings.customIceIconIsTemplate)
        #expect(!settings.showOnScroll)
        #expect(!settings.showOnClick)
        #expect(!settings.showOnDoubleClick)
        #expect(settings.useIceBar)
        #expect(settings.useIceBarOnlyOnNotchedDisplay)
        #expect(settings.iceBarLocationOnHotkey)
    }

    @Test("An external double change updates the rehide interval")
    func externalDoubleChangeIsApplied() async {
        clearStoredSettings()
        let settings = makeSettings()

        await postExternalChange(["key": "rehideInterval", "doubleValue": 123.5])

        // Only the model is asserted, not `Defaults`: a suite that restores a
        // whole persistent domain can land during the suspension above and
        // wipe the write this model just made. Persistence itself is covered
        // synchronously by `propertyChangesArePersisted`.
        #expect(settings.rehideInterval == 123.5)
    }

    @Test("An external enum change updates the rehide strategy")
    func externalEnumChangeIsApplied() async {
        clearStoredSettings()
        let settings = makeSettings()

        await postExternalChange(["key": "rehideStrategy", "rawEnumValue": RehideStrategy.timed.rawValue])

        #expect(settings.rehideStrategy == .timed)
    }

    @Test(
        "An external change to an unknown key is ignored",
        arguments: ["", "nope", "showIceIco", "SHOWICEICON"]
    )
    func externalChangeToUnknownKeyIsIgnored(_ key: String) async {
        clearStoredSettings()
        let settings = makeSettings()

        await postExternalChange(["key": key, "value": false])

        #expect(
            settings.showIceIcon == Defaults.DefaultValue.showIceIcon,
            "\(key) must not reach any property"
        )
    }

    @Test("An external change to another model's key is ignored")
    func externalChangeToAnotherModelsKeyIsIgnored() async {
        clearStoredSettings()
        let settings = makeSettings()

        // `alwaysShowHiddenItems` is a per-display setting owned by
        // DisplaySettingsManager. This model sees every change posted on this
        // channel and has to let the ones it does not own by.
        await postExternalChange(["key": "alwaysShowHiddenItems", "value": true])

        #expect(settings.showIceIcon == Defaults.DefaultValue.showIceIcon)
        #expect(settings.showOnClick == Defaults.DefaultValue.showOnClick)
    }

    @Test("A numeric payload for a boolean setting is ignored")
    func wronglyTypedNumericPayloadIsIgnored() async {
        clearStoredSettings()
        let settings = makeSettings()

        await postExternalChange(["key": "showOnClick", "doubleValue": 0])

        #expect(settings.showOnClick == Defaults.DefaultValue.showOnClick)
    }

    @Test("A boolean payload for a numeric setting is ignored")
    func wronglyTypedBooleanPayloadIsIgnored() async {
        clearStoredSettings()
        let settings = makeSettings()

        await postExternalChanges([
            ["key": "rehideInterval", "value": true],
            ["key": "rehideStrategy", "value": true],
        ])

        #expect(settings.rehideInterval == Defaults.DefaultValue.rehideInterval)
        #expect(settings.rehideStrategy == Defaults.DefaultValue.rehideStrategy)
    }

    @Test("A string payload reaches no property")
    func stringPayloadIsIgnored() async {
        clearStoredSettings()
        let settings = makeSettings()

        await postExternalChange(["key": "showIceIcon", "value": "false"])

        #expect(settings.showIceIcon == Defaults.DefaultValue.showIceIcon)
    }

    @Test("An unrecognized rehide strategy raw value is ignored")
    func unrecognizedExternalEnumRawValueIsIgnored() async {
        clearStoredSettings()
        let settings = makeSettings()
        settings.rehideStrategy = .focusedApp

        await postExternalChange(["key": "rehideStrategy", "rawEnumValue": 99])

        #expect(settings.rehideStrategy == .focusedApp)
    }

    @Test("A change with no key is dropped before it reaches the model")
    func changeWithoutAKeyIsDropped() async {
        clearStoredSettings()
        let settings = makeSettings()

        await postExternalChange(["value": false])

        #expect(settings.showIceIcon == Defaults.DefaultValue.showIceIcon)
    }

    @Test("An external change that matches the current value is a no-op")
    func redundantExternalChangeIsHarmless() async {
        clearStoredSettings()
        let settings = makeSettings()
        settings.customIceIconIsTemplate = true

        await postExternalChange(["key": "customIceIconIsTemplate", "value": true])

        #expect(settings.customIceIconIsTemplate)
    }
}
