//
//  AdvancedSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``AdvancedSettings``' setup surface: the `Defaults` load performed by
/// `performSetup(with:)` and the Settings-URI notification it subscribes to.
///
/// The load reads whatever is in `UserDefaults` — possibly written by an older
/// build, a hand-edited plist, or a partially failed import — so an
/// unrecognized divider style or a search-section order that is short,
/// duplicated, or full of unknown names has to resolve to something usable
/// rather than leave the search panel with a missing or repeated section.
/// The notification arrives on behalf of a *third-party app* that sent a
/// `thaw://` URL, so a key this model does not own, or a payload of the wrong
/// type, must be dropped.
///
/// `SettingsURIHandlerApplyTests` covers the sending side of the same
/// notification; the two suites have to agree on the `userInfo` shape.
///
/// The model persists through `didSet`, so every test body runs inside
/// `withScratchDefaults`: writes land in a throwaway store rather than the
/// developer's own settings, and each test starts from the empty store of a
/// first launch. That also keeps `enableDiagnosticLogging` at its compiled-in
/// default, so the model never runs the `didSet` that reaches into the shared
/// ``DiagnosticLogger``.
@MainActor
@Suite("Advanced settings", .serialized)
struct AdvancedSettingsTests {
    /// Returns a model that has run its setup against the current `Defaults`.
    ///
    /// The app state is unused by this model, so setup runs without one.
    private func makeSettings() -> AdvancedSettings {
        let settings = AdvancedSettings()
        settings.performSetup()
        return settings
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
    /// run while this one's scratch store is installed.
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
    func storedValuesAreLoaded() throws {
        try withScratchDefaults { _ in
            Defaults.set(true, forKey: .enableAlwaysHiddenSection)
            Defaults.set(true, forKey: .useOptionClickToShowAlwaysHiddenSection)
            Defaults.set(true, forKey: .useDoubleClickToShowAlwaysHiddenSection)
            Defaults.set(false, forKey: .showAllSectionsOnUserDrag)
            Defaults.set(false, forKey: .hideApplicationMenus)
            Defaults.set(false, forKey: .enableSecondaryContextMenu)
            Defaults.set(true, forKey: .enableSecondaryContextMenuQuit)
            Defaults.set(1.5, forKey: .showOnHoverDelay)
            Defaults.set(2.5, forKey: .tooltipDelay)
            Defaults.set(3.5, forKey: .iconRefreshInterval)
            Defaults.set(true, forKey: .showMenuBarTooltips)
            Defaults.set(false, forKey: .enableMenuBarItemOverflow)
            Defaults.set(false, forKey: .useThawBarOnNotchOverflow)
            Defaults.set(true, forKey: .useAXClickDelivery)
            Defaults.set(false, forKey: .searchIncludeVisible)
            Defaults.set(false, forKey: .searchIncludeHidden)
            Defaults.set(false, forKey: .searchIncludeAlwaysHidden)
            Defaults.set(true, forKey: .moveCursorToRevealedItem)

            let settings = makeSettings()

            #expect(settings.enableAlwaysHiddenSection)
            #expect(settings.useOptionClickToShowAlwaysHiddenSection)
            #expect(settings.useDoubleClickToShowAlwaysHiddenSection)
            #expect(!settings.showAllSectionsOnUserDrag)
            #expect(!settings.hideApplicationMenus)
            #expect(!settings.enableSecondaryContextMenu)
            #expect(settings.enableSecondaryContextMenuQuit)
            #expect(settings.showOnHoverDelay == 1.5)
            #expect(settings.tooltipDelay == 2.5)
            #expect(settings.iconRefreshInterval == 1.0)
            #expect(Defaults.double(forKey: .iconRefreshInterval) == 1.0)
            #expect(settings.showMenuBarTooltips)
            #expect(!settings.enableMenuBarItemOverflow)
            #expect(!settings.useThawBarOnNotchOverflow)
            #expect(settings.useAXClickDelivery)
            #expect(!settings.searchIncludeVisible)
            #expect(!settings.searchIncludeHidden)
            #expect(!settings.searchIncludeAlwaysHidden)
            #expect(settings.moveCursorToRevealedItem)
        }
    }

    @Test("Absent keys leave the shipped defaults in place")
    func absentKeysLeaveTheDefaults() throws {
        try withScratchDefaults { _ in
            let settings = makeSettings()

            #expect(settings.enableAlwaysHiddenSection == Defaults.DefaultValue.enableAlwaysHiddenSection)
            #expect(settings.showAllSectionsOnUserDrag == Defaults.DefaultValue.showAllSectionsOnUserDrag)
            #expect(settings.sectionDividerStyle == Defaults.DefaultValue.sectionDividerStyle)
            #expect(settings.hideApplicationMenus == Defaults.DefaultValue.hideApplicationMenus)
            #expect(settings.showOnHoverDelay == Defaults.DefaultValue.showOnHoverDelay)
            #expect(settings.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
            #expect(settings.iconRefreshInterval == Defaults.DefaultValue.iconRefreshInterval)
            #expect(settings.useAXClickDelivery == Defaults.DefaultValue.useAXClickDelivery)
            #expect(settings.searchSectionOrder.map(\.rawValue) == Defaults.DefaultValue.searchSectionOrder)
        }
    }

    @Test("A stored divider style is loaded")
    func storedDividerStyleIsLoaded() throws {
        try withScratchDefaults { _ in
            Defaults.set(SectionDividerStyle.chevron.rawValue, forKey: .sectionDividerStyle)

            #expect(makeSettings().sectionDividerStyle == .chevron)
        }
    }

    @Test("An unrecognized divider style leaves the default in place")
    func unrecognizedDividerStyleIsIgnored() throws {
        try withScratchDefaults { _ in
            Defaults.set(42, forKey: .sectionDividerStyle)

            #expect(makeSettings().sectionDividerStyle == Defaults.DefaultValue.sectionDividerStyle)
        }
    }

    // MARK: Search section order

    @Test("A stored search order is loaded in the order it was written")
    func storedSearchOrderIsLoaded() throws {
        try withScratchDefaults { _ in
            Defaults.set(["alwaysHidden", "hidden", "visible"], forKey: .searchSectionOrder)

            #expect(makeSettings().searchSectionOrder == [.alwaysHidden, .hidden, .visible])
        }
    }

    @Test("A short stored search order is filled out with the missing sections")
    func shortSearchOrderIsFilledOut() throws {
        try withScratchDefaults { _ in
            Defaults.set(["alwaysHidden"], forKey: .searchSectionOrder)

            let order = makeSettings().searchSectionOrder

            #expect(order.first == .alwaysHidden)
            #expect(Set(order) == Set(MenuBarSection.Name.allCases), "every section has to be listed exactly once")
            #expect(order.count == MenuBarSection.Name.allCases.count)
        }
    }

    @Test("Duplicate and unknown section names are dropped from a stored order")
    func malformedSearchOrderIsSanitized() throws {
        try withScratchDefaults { _ in
            Defaults.set(["hidden", "hidden", "sideways", "", "visible"], forKey: .searchSectionOrder)

            let order = makeSettings().searchSectionOrder

            #expect(order == [.hidden, .visible, .alwaysHidden])
        }
    }

    @Test("An empty stored search order falls back to the full set")
    func emptySearchOrderFallsBack() throws {
        try withScratchDefaults { _ in
            Defaults.set([String](), forKey: .searchSectionOrder)

            #expect(makeSettings().searchSectionOrder == MenuBarSection.Name.allCases)
        }
    }

    // MARK: Persistence

    @Test("A property change is written straight through to Defaults")
    func propertyChangesArePersisted() throws {
        try withScratchDefaults { _ in
            let settings = makeSettings()

            settings.enableAlwaysHiddenSection = true
            settings.tooltipDelay = 1.25
            settings.sectionDividerStyle = .chevron
            settings.searchSectionOrder = [.alwaysHidden, .hidden, .visible]
            settings.moveCursorToRevealedItem = true

            #expect(Defaults.bool(forKey: .moveCursorToRevealedItem))
            #expect(Defaults.bool(forKey: .enableAlwaysHiddenSection))
            #expect(Defaults.double(forKey: .tooltipDelay) == 1.25)
            #expect(Defaults.integer(forKey: .sectionDividerStyle) == SectionDividerStyle.chevron.rawValue)
            #expect(Defaults.stringArray(forKey: .searchSectionOrder) == ["alwaysHidden", "hidden", "visible"])
        }
    }

    @Test("Stored values survive a reload")
    func storedValuesRoundTrip() throws {
        try withScratchDefaults { _ in
            let settings = makeSettings()
            settings.enableAlwaysHiddenSection = true
            settings.sectionDividerStyle = .chevron
            settings.searchSectionOrder = [.hidden, .alwaysHidden, .visible]

            let reloaded = makeSettings()

            #expect(reloaded.enableAlwaysHiddenSection)
            #expect(reloaded.sectionDividerStyle == .chevron)
            #expect(reloaded.searchSectionOrder == [.hidden, .alwaysHidden, .visible])
        }
    }

    // MARK: External changes

    @Test("An external boolean change updates the matching property")
    func externalBooleanChangeIsApplied() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            await postExternalChanges([
                ["key": "enableAlwaysHiddenSection", "value": true],
                ["key": "useOptionClickToShowAlwaysHiddenSection", "value": true],
                ["key": "useDoubleClickToShowAlwaysHiddenSection", "value": true],
                ["key": "showAllSectionsOnUserDrag", "value": false],
                ["key": "hideApplicationMenus", "value": false],
                ["key": "enableSecondaryContextMenu", "value": false],
                ["key": "enableSecondaryContextMenuQuit", "value": true],
                ["key": "showMenuBarTooltips", "value": true],
                ["key": "enableMenuBarItemOverflow", "value": false],
                ["key": "useThawBarOnNotchOverflow", "value": false],
                ["key": "useAXClickDelivery", "value": true],
            ])

            #expect(settings.enableAlwaysHiddenSection)
            #expect(settings.useOptionClickToShowAlwaysHiddenSection)
            #expect(settings.useDoubleClickToShowAlwaysHiddenSection)
            #expect(!settings.showAllSectionsOnUserDrag)
            #expect(!settings.hideApplicationMenus)
            #expect(!settings.enableSecondaryContextMenu)
            #expect(settings.enableSecondaryContextMenuQuit)
            #expect(settings.showMenuBarTooltips)
            #expect(!settings.enableMenuBarItemOverflow)
            #expect(!settings.useThawBarOnNotchOverflow)
            #expect(settings.useAXClickDelivery)
        }
    }

    @Test("An external change to a search filter updates it")
    func externalSearchFilterChangeIsApplied() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            await postExternalChanges([
                ["key": "searchIncludeVisible", "value": false],
                ["key": "searchIncludeHidden", "value": false],
                ["key": "searchIncludeAlwaysHidden", "value": false],
            ])

            #expect(!settings.searchIncludeVisible)
            #expect(!settings.searchIncludeHidden)
            #expect(!settings.searchIncludeAlwaysHidden)
        }
    }

    @Test("An external change to the pointer-move setting updates it")
    func externalMoveCursorChangeIsApplied() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            await postExternalChange(["key": "moveCursorToRevealedItem", "value": true])

            #expect(settings.moveCursorToRevealedItem)
        }
    }

    @Test("An external double change updates the matching delay")
    func externalDoubleChangeIsApplied() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            await postExternalChanges([
                ["key": "showOnHoverDelay", "doubleValue": 1.75],
                ["key": "tooltipDelay", "doubleValue": 2.75],
                ["key": "iconRefreshInterval", "doubleValue": 3.75],
            ])

            // Only the model is asserted, not `Defaults`: a suite that restores a
            // whole persistent domain can land during the suspension above and
            // wipe the writes this model just made. Persistence itself is covered
            // synchronously by `propertyChangesArePersisted`.
            #expect(settings.showOnHoverDelay == 1.75)
            #expect(settings.tooltipDelay == 2.75)
            #expect(settings.iconRefreshInterval == 1.0)
        }
    }

    @Test(
        "An external change to an unknown key is ignored",
        arguments: ["", "nope", "enableAlwaysHiddenSectio", "ENABLEALWAYSHIDDENSECTION"]
    )
    func externalChangeToUnknownKeyIsIgnored(_ key: String) async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            await postExternalChange(["key": key, "value": true])

            #expect(!settings.enableAlwaysHiddenSection, "\(key) must not reach any property")
        }
    }

    @Test("An external change to another model's key is ignored")
    func externalChangeToAnotherModelsKeyIsIgnored() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            // `alwaysShowHiddenItems` is a per-display setting owned by
            // DisplaySettingsManager. This model sees every change posted on this
            // channel and has to let the ones it does not own by.
            await postExternalChange(["key": "alwaysShowHiddenItems", "value": true])

            #expect(settings.enableAlwaysHiddenSection == Defaults.DefaultValue.enableAlwaysHiddenSection)
            #expect(settings.showMenuBarTooltips == Defaults.DefaultValue.showMenuBarTooltips)
        }
    }

    @Test("A numeric payload for a boolean setting is ignored")
    func wronglyTypedNumericPayloadIsIgnored() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            await postExternalChange(["key": "enableAlwaysHiddenSection", "doubleValue": 1.0])

            #expect(!settings.enableAlwaysHiddenSection)
        }
    }

    @Test("A boolean payload for a numeric setting is ignored")
    func wronglyTypedBooleanPayloadIsIgnored() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            await postExternalChange(["key": "tooltipDelay", "value": true])

            #expect(settings.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
        }
    }

    @Test("A string payload reaches no property")
    func stringPayloadIsIgnored() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            await postExternalChange(["key": "enableAlwaysHiddenSection", "value": "true"])

            #expect(!settings.enableAlwaysHiddenSection)
        }
    }

    @Test("Settings with no external channel are left alone")
    func settingsWithoutAnExternalChannelAreLeftAlone() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()
            let order = settings.searchSectionOrder

            // Neither key is handled by `handleExternalSettingsChange`, so a
            // well-formed payload for one must still change nothing.
            await postExternalChanges([
                ["key": "sectionDividerStyle", "rawEnumValue": SectionDividerStyle.chevron.rawValue],
                ["key": "searchSectionOrder", "value": true],
            ])

            #expect(settings.sectionDividerStyle == Defaults.DefaultValue.sectionDividerStyle)
            #expect(settings.searchSectionOrder == order)
        }
    }

    @Test("A change with no key is dropped before it reaches the model")
    func changeWithoutAKeyIsDropped() async throws {
        try await withScratchDefaults { _ in
            let settings = makeSettings()

            await postExternalChange(["value": true])

            #expect(!settings.enableAlwaysHiddenSection)
        }
    }
}
