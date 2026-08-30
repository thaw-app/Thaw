//
//  MenuBarItemTriggerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import IOKit.ps
import Testing
@testable import Thaw

@Suite("Menu bar item triggers")
@MainActor
struct MenuBarItemTriggerTests {
    // MARK: - Helpers

    private func makeManager() -> MenuBarItemTriggersManager {
        MenuBarItemTriggersManager(persistenceEnabled: false)
    }

    private func state(
        battery: Double? = nil,
        onAC: Bool = false,
        charging: Bool = false,
        frontmost: String? = nil,
        running: Set<String> = [],
        networkConnected: Bool = true,
        vpn: Bool = false,
        ssid: String? = nil,
        bluetooth: Set<String> = [],
        audio: String? = nil,
        screenCount: Int = 1,
        externalDisplay: Bool = false,
        focus: Bool = false,
        seekingAttention: Set<String> = []
    ) -> SystemState {
        SystemState(
            power: PowerState(batteryPercentage: battery, isOnACPower: onAC, isCharging: charging),
            frontmostAppBundleID: frontmost,
            runningAppBundleIDs: running,
            isNetworkConnected: networkConnected,
            isVPNActive: vpn,
            wifiSSID: ssid,
            connectedBluetoothDeviceNames: bluetooth,
            audioOutputDeviceName: audio,
            screenCount: screenCount,
            externalDisplayConnected: externalDisplay,
            isFocusActive: focus,
            itemsSeekingAttention: seekingAttention
        )
    }

    // MARK: - itemSeekingAttention

    @Test("An attention condition is satisfied while its item is blinking")
    func attentionConditionFiresForItsItem() {
        let condition = TriggerCondition.itemSeekingAttention(itemIdentifier: "com.example.app:Status")
        #expect(condition.isSatisfied(state: state(seekingAttention: ["com.example.app:Status"])))
    }

    @Test("An attention condition ignores a different item blinking")
    func attentionConditionIsPerItem() {
        let condition = TriggerCondition.itemSeekingAttention(itemIdentifier: "com.example.app:Status")
        #expect(!condition.isSatisfied(state: state(seekingAttention: ["com.other.app:Status"])))
    }

    @Test("An attention condition is unsatisfied when nothing is blinking")
    func attentionConditionIsFalseWhenQuiet() {
        let condition = TriggerCondition.itemSeekingAttention(itemIdentifier: "com.example.app:Status")
        #expect(!condition.isSatisfied(state: state()))
    }

    @Test("An attention condition maps to its own kind, editor and feature")
    func attentionConditionMapsToItsKind() {
        let condition = TriggerCondition.itemSeekingAttention(itemIdentifier: "x")
        #expect(condition.kind == .itemSeekingAttention)
        #expect(TriggerConditionKind.itemSeekingAttention.editor == .itemPicker)
        #expect(TriggerConditionKind.itemSeekingAttention.requiredFeature == .attentionSeeking)
    }

    @Test("The watched item survives switching between the two icon kinds")
    func watchedItemIsPreservedAcrossKindChange() {
        let watched = "com.example.app:Status"
        let image = TriggerCondition.imageChanged(itemIdentifier: watched, referenceHash: 42)

        let attention = TriggerCondition.make(kind: .itemSeekingAttention, preserving: image)
        #expect(attention.watchedItemIdentifier == watched)

        // And back again -- the reference hash is gone, which is correct: it
        // described a comparison this kind never made.
        let backToImage = TriggerCondition.make(kind: .imageChanged, preserving: attention)
        #expect(backToImage.watchedItemIdentifier == watched)
        #expect(backToImage.imageValue?.referenceHash == nil)
    }

    @Test("Choosing an item rebuilds the attention condition")
    func withAttentionItemSetsTheWatchedItem() {
        let condition = TriggerCondition.itemSeekingAttention(itemIdentifier: "")
        #expect(condition.withAttentionItem("com.example.app:Status").watchedItemIdentifier == "com.example.app:Status")
    }

    @Test("withAttentionItem leaves other condition kinds alone")
    func withAttentionItemIgnoresOtherKinds() {
        let condition = TriggerCondition.onACPower
        #expect(condition.withAttentionItem("com.example.app:Status") == .onACPower)
    }

    // MARK: - Battery / Power

    @Test func batteryBelow() {
        #expect(TriggerCondition.batteryBelow(percentage: 50).isSatisfied(state: state(battery: 30)))
        #expect(!TriggerCondition.batteryBelow(percentage: 50).isSatisfied(state: state(battery: 50)))
    }

    @Test func batteryAtOrAbove() {
        #expect(TriggerCondition.batteryAtOrAbove(percentage: 50).isSatisfied(state: state(battery: 50)))
        #expect(!TriggerCondition.batteryAtOrAbove(percentage: 50).isSatisfied(state: state(battery: 49)))
    }

    @Test func batteryConditionsNeedBattery() {
        #expect(!TriggerCondition.batteryBelow(percentage: 50).isSatisfied(state: state(battery: nil)))
        #expect(!TriggerCondition.batteryAtOrAbove(percentage: 50).isSatisfied(state: state(battery: nil)))
    }

    @Test func powerSourceConditions() {
        #expect(TriggerCondition.onACPower.isSatisfied(state: state(onAC: true)))
        #expect(!TriggerCondition.onACPower.isSatisfied(state: state(onAC: false)))
        #expect(TriggerCondition.onBatteryPower.isSatisfied(state: state(onAC: false)))
        #expect(TriggerCondition.charging.isSatisfied(state: state(charging: true)))
    }

    @Test func builtInBatteryIsProtectedFromConditionalPlacement() {
        let battery = MenuBarItemTag(
            namespace: .controlCenter,
            title: "Battery",
            instanceIndex: 2
        )
        #expect(battery.triggerTargetPolicy == .systemVisibilityPreferenceSensitive)
        #expect(
            MenuBarItemTag.triggerTargetPolicy(for: "com.apple.controlcenter:Battery:2")
                == .systemVisibilityPreferenceSensitive
        )
        #expect(MenuBarItemTag.triggerTargetPolicy(for: "com.example.app:Battery") == .supported)
        #expect(MenuBarItemTag.triggerTargetPolicy(for: "com.apple.controlcenter:BatteryStatus") == .supported)

        #expect(MenuBarItemManager.triggerMovePreflight(for: battery, to: .visible) == .allowed)
        #expect(MenuBarItemManager.triggerMovePreflight(for: battery, to: .hidden) == .protectedSystemItem)
        #expect(MenuBarItemManager.triggerMovePreflight(for: battery, to: .alwaysHidden) == .protectedSystemItem)

        let observedBattery = TriggerItemOption(
            id: battery.tagIdentifier,
            name: "Battery",
            baseIdentifier: battery.stableIdentifierBase
        )
        #expect(!observedBattery.supportsConditionalPlacement)
        #expect(
            TriggerItemOption(
                id: "com.example.app:Battery",
                name: "Battery",
                baseIdentifier: "com.example.app:Battery"
            ).supportsConditionalPlacement
        )
    }

    // MARK: - Applications

    @Test func frontmostApp() {
        let s = state(frontmost: "com.apple.Safari")
        #expect(TriggerCondition.frontmostApp(bundleID: "com.apple.Safari").isSatisfied(state: s))
        #expect(!TriggerCondition.frontmostApp(bundleID: "com.apple.Mail").isSatisfied(state: s))
        #expect(!TriggerCondition.frontmostApp(bundleID: "").isSatisfied(state: s))
    }

    @Test func appRunning() {
        let s = state(running: ["com.apple.Safari", "com.apple.Mail"])
        #expect(TriggerCondition.appRunning(bundleID: "com.apple.Mail").isSatisfied(state: s))
        #expect(!TriggerCondition.appRunning(bundleID: "com.apple.Music").isSatisfied(state: s))
    }

    // MARK: - Network / Devices

    @Test func networkAndVPN() {
        #expect(TriggerCondition.networkConnected.isSatisfied(state: state(networkConnected: true)))
        #expect(!TriggerCondition.networkConnected.isSatisfied(state: state(networkConnected: false)))
        #expect(TriggerCondition.vpnActive.isSatisfied(state: state(vpn: true)))
    }

    @Test func wifiSSIDCaseInsensitive() {
        let s = state(ssid: "HomeNet")
        #expect(TriggerCondition.wifiSSID(name: "homenet").isSatisfied(state: s))
        #expect(!TriggerCondition.wifiSSID(name: "Office").isSatisfied(state: s))
    }

    @Test func bluetoothSubstringMatch() {
        let s = state(bluetooth: ["Alvie's AirPods Pro"])
        #expect(TriggerCondition.bluetoothConnected(name: "airpods").isSatisfied(state: s))
        #expect(!TriggerCondition.bluetoothConnected(name: "Magic Mouse").isSatisfied(state: s))
    }

    @Test func audioOutputSubstring() {
        let s = state(audio: "External Headphones")
        #expect(TriggerCondition.audioOutput(contains: "headphones").isSatisfied(state: s))
        #expect(!TriggerCondition.audioOutput(contains: "speakers").isSatisfied(state: s))
    }

    @Test func externalDisplay() {
        #expect(TriggerCondition.externalDisplayConnected.isSatisfied(state: state(externalDisplay: true)))
        #expect(!TriggerCondition.externalDisplayConnected.isSatisfied(state: state(externalDisplay: false)))
    }

    @Test func focusActive() {
        #expect(TriggerCondition.focusActive.isSatisfied(state: state(focus: true)))
        #expect(!TriggerCondition.focusActive.isSatisfied(state: state(focus: false)))
    }

    // MARK: - Location

    private func locatedState(lat: Double, lon: Double) -> SystemState {
        var s = state()
        s.currentLatitude = lat
        s.currentLongitude = lon
        return s
    }

    @Test("near location within radius")
    func nearLocationWithinRadius() {
        // ~11m north of the target — inside a 150m radius.
        let condition = TriggerCondition.nearLocation(
            latitude: 37.3349, longitude: -122.0090, radiusMeters: 150, label: "Work"
        )
        #expect(condition.isSatisfied(state: locatedState(lat: 37.3350, lon: -122.0090)))
    }

    @Test("near location outside radius")
    func nearLocationOutsideRadius() {
        // Cupertino target vs San Francisco current — far outside any radius.
        let condition = TriggerCondition.nearLocation(
            latitude: 37.3349, longitude: -122.0090, radiusMeters: 150, label: "Work"
        )
        #expect(!condition.isSatisfied(state: locatedState(lat: 37.7749, lon: -122.4194)))
    }

    @Test("near location without a fix is false")
    func nearLocationWithoutFixIsFalse() {
        let condition = TriggerCondition.nearLocation(
            latitude: 37.3349, longitude: -122.0090, radiusMeters: 150, label: "Work"
        )
        #expect(!condition.isSatisfied(state: state()))
    }

    @Test("withLocation updates all fields")
    func withLocationUpdatesFields() {
        let base = TriggerCondition.nearLocation(latitude: 0, longitude: 0, radiusMeters: 150, label: "")
        let updated = base.withLocation(latitude: 1, longitude: 2, radiusMeters: 300, label: "Home")
        #expect(updated.locationValue?.latitude == 1)
        #expect(updated.locationValue?.longitude == 2)
        #expect(updated.locationValue?.radiusMeters == 300)
        #expect(updated.locationValue?.label == "Home")
    }

    // MARK: - Schedule

    private func date(
        year: Int = 2026,
        month: Int = 6,
        day: Int = 24,
        hour: Int,
        minute: Int
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    @Test("schedule window does not wrap midnight")
    func scheduleNonWrapping() {
        let condition = TriggerCondition.schedule(startMinutes: 9 * 60, endMinutes: 17 * 60)
        #expect(condition.isSatisfied(state: state(), now: date(hour: 12, minute: 0)))
        #expect(!condition.isSatisfied(state: state(), now: date(hour: 8, minute: 0)))
        #expect(!condition.isSatisfied(state: state(), now: date(hour: 17, minute: 0)))
    }

    @Test("schedule window wraps midnight")
    func scheduleWrappingMidnight() {
        let condition = TriggerCondition.schedule(startMinutes: 22 * 60, endMinutes: 6 * 60)
        #expect(condition.isSatisfied(state: state(), now: date(hour: 23, minute: 0)))
        #expect(condition.isSatisfied(state: state(), now: date(hour: 2, minute: 0)))
        #expect(!condition.isSatisfied(state: state(), now: date(hour: 12, minute: 0)))
    }

    @Test("empty schedule window never fires")
    func scheduleEmptyWindow() {
        let condition = TriggerCondition.schedule(startMinutes: 600, endMinutes: 600)
        #expect(!condition.isSatisfied(state: state(), now: date(hour: 10, minute: 0)))
    }

    @Test("weekly schedule without wrapping")
    func weeklyScheduleNonWrapping() {
        let condition = TriggerCondition.weeklySchedule(
            startMinutes: 9 * 60,
            endMinutes: 17 * 60,
            weekdays: [.monday]
        )

        #expect(condition.isSatisfied(state: state(), now: date(day: 22, hour: 12, minute: 0)))
        #expect(!condition.isSatisfied(state: state(), now: date(day: 23, hour: 12, minute: 0)))
        #expect(!condition.isSatisfied(state: state(), now: date(day: 22, hour: 8, minute: 0)))
    }

    @Test("weekly schedule wrapping midnight uses the start day")
    func weeklyScheduleWrappingMidnightUsesStartDay() {
        let condition = TriggerCondition.weeklySchedule(
            startMinutes: 22 * 60,
            endMinutes: 6 * 60,
            weekdays: [.monday]
        )

        #expect(condition.isSatisfied(state: state(), now: date(day: 22, hour: 23, minute: 0)))
        #expect(condition.isSatisfied(state: state(), now: date(day: 23, hour: 2, minute: 0)))
        #expect(!condition.isSatisfied(state: state(), now: date(day: 23, hour: 23, minute: 0)))
        #expect(!condition.isSatisfied(state: state(), now: date(day: 22, hour: 2, minute: 0)))
    }

    @Test("weekly schedule survives a Codable round trip")
    func weeklyScheduleCodableRoundTrip() throws {
        let condition = TriggerCondition.weeklySchedule(
            startMinutes: 9 * 60,
            endMinutes: 17 * 60,
            weekdays: [.monday, .wednesday, .friday]
        )

        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: data)

        #expect(decoded == condition)
    }

    @Test("legacy schedule decodes with every-day weekdays")
    func legacyScheduleDefaultsToEveryDay() throws {
        let json = """
        { "schedule": { "startMinutes": 540, "endMinutes": 1020 } }
        """

        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: Data(json.utf8))

        #expect(decoded.scheduleWindow?.start == 540)
        #expect(decoded.scheduleWindow?.end == 1020)
        #expect(decoded.scheduleWeekdays == ScheduleWeekday.everyDay)
    }

    // MARK: - System load

    @Test func lowPowerMode() {
        var on = state()
        on.energyMode = .low
        #expect(TriggerCondition.lowPowerMode.isSatisfied(state: on))
        #expect(!TriggerCondition.lowPowerMode.isSatisfied(state: state()))
    }

    /// The layout editor reads this per item on every redraw, so it is
    /// memoized — it has to survive edits to the trigger list.
    @Test func controlledBaseIdentifiersTracksTriggerEdits() {
        let manager = makeManager()
        #expect(!manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))

        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.example.Status",
                condition: .onACPower
            ),
        ]
        #expect(manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))

        manager.triggers[0].isEnabled = false
        #expect(!manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))

        manager.triggers = []
        #expect(!manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))
        #expect(!manager.isControlledByTrigger(baseIdentifier: ""))
    }

    /// A legacy target stored with an instance suffix and no captured base
    /// must still read as owned when queried by the live base — the badge
    /// and the tooltip resolve ownership through different paths, and they
    /// have to agree.
    @Test func legacySuffixedTargetWithoutBaseIsOwned() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.example.Status:2",
                condition: .onACPower
            ),
        ]

        #expect(manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))
        #expect(manager.controllingTrigger(forBaseIdentifier: "com.example.Status") != nil)
        // A title that merely ends in ":<number>" is not an instance suffix
        // unless the base is live; an unrelated base must not match.
        #expect(!manager.isControlledByTrigger(baseIdentifier: "com.example.Other"))
    }

    /// The two ownership queries answer from the same predicate: whenever the
    /// set says owned, the tooltip lookup must produce the owning trigger.
    @Test func ownershipQueriesAgree() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.example.Status:2",
                itemBaseIdentifier: "com.example.Status",
                condition: .onACPower
            ),
        ]

        for base in ["com.example.Status", "com.example.Status:2", "com.example.Other", ""] {
            #expect(
                manager.isControlledByTrigger(baseIdentifier: base)
                    == (manager.controllingTrigger(forBaseIdentifier: base) != nil),
                "queries disagree for \(base)"
            )
        }
    }

    /// A target stored with an instance suffix is owned under both spellings,
    /// since the live tag resolves to the base.
    @Test func controlledBaseIdentifiersCoversCapturedBase() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.example.Status:2",
                itemBaseIdentifier: "com.example.Status",
                condition: .onACPower
            ),
        ]

        #expect(manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))
        #expect(manager.isControlledByTrigger(baseIdentifier: "com.example.Status:2"))
    }

    // MARK: - Combinators

    @Test("'None of' is satisfied only when no condition is")
    func noneOfIsSatisfiedOnlyWhenNoConditionIs() {
        var trigger = MenuBarItemTrigger(
            itemIdentifier: "item",
            condition: .onACPower
        )
        trigger.additionalConditions = [.charging]
        trigger.combinator = .noneOf

        // Neither holds.
        #expect(trigger.shouldReveal(state: state(onAC: false, charging: false)))
        // One holds.
        #expect(!trigger.shouldReveal(state: state(onAC: true, charging: false)))
        #expect(!trigger.shouldReveal(state: state(onAC: false, charging: true)))
        // Both hold.
        #expect(!trigger.shouldReveal(state: state(onAC: true, charging: true)))
    }

    /// "None of" is the condition-side negation; `invert` is the action-side
    /// one. Combining them has to cancel out, not compound.
    @Test("'None of' composes with invert")
    func noneOfComposesWithInvert() {
        var trigger = MenuBarItemTrigger(
            itemIdentifier: "item",
            condition: .onACPower
        )
        trigger.combinator = .noneOf
        trigger.invert = true

        #expect(trigger.shouldReveal(state: state(onAC: true)))
        #expect(!trigger.shouldReveal(state: state(onAC: false)))
    }

    /// Joining with " or " alone would read as if any one of them fired the
    /// trigger, which is the opposite of what "None of" means.
    @Test("'None of' summary states the relationship")
    func noneOfSummaryStatesTheRelationship() {
        var trigger = MenuBarItemTrigger(
            itemIdentifier: "item",
            condition: .onACPower
        )
        trigger.combinator = .noneOf

        #expect(trigger.conditionSummary == "Not: Connected to power")

        trigger.additionalConditions = [.charging]
        #expect(
            trigger.conditionSummary == "None of: Connected to power or Battery is charging"
        )
    }

    /// The raw value is persisted, so it must stay stable, and triggers saved
    /// before the combinator existed must still decode.
    @Test func combinatorCodableRoundTrip() throws {
        #expect(TriggerCombinator.noneOf.rawValue == "none")

        var trigger = MenuBarItemTrigger(itemIdentifier: "item", condition: .onACPower)
        trigger.combinator = .noneOf
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        #expect(decoded.combinator == .noneOf)
    }

    // MARK: - Layout ownership

    /// The layout editor asks this to decide whether an item is still the
    /// user's to place.
    @Test func controllingTriggerFindsEnabledTargetingTrigger() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.example.Status",
                condition: .batteryBelow(percentage: 69)
            ),
        ]

        let owner = manager.controllingTrigger(forBaseIdentifier: "com.example.Status")

        #expect(owner?.itemIdentifier == "com.example.Status")
        #expect(manager.controllingTrigger(forBaseIdentifier: "com.example.Other") == nil)
        #expect(manager.controllingTrigger(forBaseIdentifier: "") == nil)
    }

    /// Ownership is claimed by an enabled trigger whether or not its
    /// condition is currently met, matching when the item manager takes the
    /// item over. A disabled trigger claims nothing.
    @Test func controllingTriggerIgnoresDisabledTriggers() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: false,
                itemIdentifier: "com.example.Status",
                condition: .batteryBelow(percentage: 69)
            ),
        ]

        #expect(manager.controllingTrigger(forBaseIdentifier: "com.example.Status") == nil)
    }

    /// A stored target carrying a stale instance suffix still resolves to the
    /// live item, so the layout editor doesn't quietly re-open a locked item.
    @Test func controllingTriggerFollowsInstanceSuffixDrift() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.example.Status:2",
                condition: .onBatteryPower
            ),
        ]

        #expect(manager.controllingTrigger(forBaseIdentifier: "com.example.Status") != nil)
    }

    /// Two enabled triggers on one item resolve to the higher-priority one,
    /// the same winner the priority plan picks.
    @Test func controllingTriggerPrefersHigherPriority() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                name: "First",
                isEnabled: true,
                itemIdentifier: "com.example.Status",
                condition: .onBatteryPower
            ),
            MenuBarItemTrigger(
                name: "Second",
                isEnabled: true,
                itemIdentifier: "com.example.Status",
                condition: .onACPower
            ),
        ]

        #expect(
            manager.controllingTrigger(forBaseIdentifier: "com.example.Status")?.displayName
                == "First"
        )
    }

    @Test func protectedBatteryTriggerDoesNotClaimLayoutOwnership() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                itemIdentifier: "com.apple.controlcenter:Battery:2",
                itemBaseIdentifier: "com.apple.controlcenter:Battery",
                condition: .onBatteryPower
            ),
        ]

        #expect(!manager.isControlledByTrigger(baseIdentifier: "com.apple.controlcenter:Battery"))
        #expect(manager.controllingTrigger(forBaseIdentifier: "com.apple.controlcenter:Battery") == nil)
        #expect(manager.runtimeStatus(for: manager.triggers[0]) == .protectedSystemItem)
    }

    @Test func protectedTriggerConditionSourcesAreNotPolled() {
        let protected = MenuBarItemTrigger(
            itemIdentifier: "com.apple.controlcenter:Battery",
            itemBaseIdentifier: "com.apple.controlcenter:Battery",
            condition: .scriptResult(path: "/protected-only", expectedOutput: "protected"),
            additionalConditions: [
                .imageChanged(itemIdentifier: "protected-image", referenceHash: nil),
                .scriptResult(path: "/shared", expectedOutput: "protected"),
                .imageChanged(itemIdentifier: "shared-image", referenceHash: nil),
            ]
        )
        let supported = MenuBarItemTrigger(
            itemIdentifier: "com.example.Status",
            condition: .scriptResult(path: "/shared", expectedOutput: "supported"),
            additionalConditions: [
                .imageChanged(itemIdentifier: "shared-image", referenceHash: nil),
            ]
        )

        #expect(
            MenuBarItemTriggersManager.runnableScriptExpectedOutputs(
                in: [protected, supported]
            ) == ["/shared": ["supported"]]
        )
        #expect(
            MenuBarItemTriggersManager.runnableImageObservationIdentifiers(
                in: [protected, supported]
            ) == ["shared-image"]
        )
    }

    @Test func energyModeMatchesExactMode() {
        for mode in EnergyMode.allCases {
            var current = state()
            current.energyMode = mode

            #expect(TriggerCondition.energyMode(.low).isSatisfied(state: current) == (mode == .low))
            #expect(TriggerCondition.energyMode(.automatic).isSatisfied(state: current) == (mode == .automatic))
            #expect(TriggerCondition.energyMode(.high).isSatisfied(state: current) == (mode == .high))
        }
    }

    /// "Not Low Power" has to cover High Power too, not just Automatic —
    /// the case that a plain inversion of the old boolean would get wrong.
    @Test func notLowPowerCoversAutomaticAndHigh() {
        var low = state()
        low.energyMode = .low
        #expect(!TriggerCondition.energyMode(.notLow).isSatisfied(state: low))

        for mode in [EnergyMode.automatic, .high] {
            var current = state()
            current.energyMode = mode
            #expect(
                TriggerCondition.energyMode(.notLow).isSatisfied(state: current),
                "Not Low Power should be satisfied in \(mode.displayString)"
            )
        }
    }

    /// Triggers saved before Energy Mode replaced the Low Power Mode
    /// condition must keep decoding, and keep meaning "Low Power".
    @Test func legacyLowPowerModeDecodesAndBehavesAsLow() throws {
        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: Data(#"{ "lowPowerMode": {} }"#.utf8))

        #expect(decoded.kind == .energyMode)
        #expect(decoded.energyModeMatch == .low)

        var low = state()
        low.energyMode = .low
        #expect(decoded.isSatisfied(state: low))

        var high = state()
        high.energyMode = .high
        #expect(!decoded.isSatisfied(state: high))
    }

    /// Editing a legacy condition upgrades it in place rather than leaving
    /// a value the editor can't represent.
    @Test func editingLegacyLowPowerModeProducesEnergyMode() {
        #expect(TriggerCondition.lowPowerMode.withEnergyMode(.high) == .energyMode(.high))
        #expect(
            TriggerCondition.make(kind: .energyMode, preserving: .lowPowerMode) == .energyMode(.low)
        )
    }

    /// Switching to a kind that carries no compatible value still yields the
    /// Energy Mode default rather than dropping the selection.
    @Test func energyModeDefaults() {
        #expect(TriggerCondition.defaultCondition(for: .energyMode) == .energyMode(.low))
        #expect(TriggerCondition.make(kind: .energyMode, preserving: .charging) == .energyMode(.low))
        #expect(TriggerCondition.energyMode(.high).kind.editor == .energyMode)
    }

    @Test func highPowerModeIsOfferedOnlyWhereSupported() {
        #expect(
            EnergyModeMatch.selectableCases(highPowerModeSupported: true)
                == [.low, .notLow, .automatic, .high]
        )
        #expect(
            EnergyModeMatch.selectableCases(highPowerModeSupported: false)
                == [.low, .notLow, .automatic]
        )
    }

    @Test func thermalPressureThreshold() {
        var serious = state()
        serious.thermalState = .serious
        #expect(TriggerCondition.thermalPressure(atLeast: .fair).isSatisfied(state: serious))
        #expect(TriggerCondition.thermalPressure(atLeast: .serious).isSatisfied(state: serious))
        #expect(!TriggerCondition.thermalPressure(atLeast: .critical).isSatisfied(state: serious))

        var nominal = state()
        nominal.thermalState = .nominal
        #expect(!TriggerCondition.thermalPressure(atLeast: .fair).isSatisfied(state: nominal))
    }

    @Test func cameraInUse() {
        var on = state()
        on.isCameraInUse = true
        #expect(TriggerCondition.cameraInUse.isSatisfied(state: on))
        #expect(!TriggerCondition.cameraInUse.isSatisfied(state: state()))
    }

    @Test func microphoneInUse() {
        var on = state()
        on.isMicrophoneInUse = true
        #expect(TriggerCondition.microphoneInUse.isSatisfied(state: on))
        #expect(!TriggerCondition.microphoneInUse.isSatisfied(state: state()))
    }

    // MARK: - Script result

    private func scriptState(_ path: String, exit: Int32, output: String) -> SystemState {
        var s = state()
        s.scriptOutcomes = [path: ScriptOutcome(exitCode: exit, output: output)]
        return s
    }

    @Test func scriptResultExitCode() {
        let condition = TriggerCondition.scriptResult(path: "/tmp/s.sh", expectedOutput: "")
        #expect(condition.isSatisfied(state: scriptState("/tmp/s.sh", exit: 0, output: "")))
        #expect(!condition.isSatisfied(state: scriptState("/tmp/s.sh", exit: 1, output: "")))
        // No outcome cached -> not satisfied.
        #expect(!condition.isSatisfied(state: state()))
    }

    @Test func scriptResultOutputMatch() {
        let condition = TriggerCondition.scriptResult(path: "/tmp/s.sh", expectedOutput: "online")
        #expect(condition.isSatisfied(state: scriptState("/tmp/s.sh", exit: 0, output: "status: ONLINE")))
        #expect(!condition.isSatisfied(state: scriptState("/tmp/s.sh", exit: 0, output: "offline")))
    }

    @Test func scriptValuePreservedOnConversion() {
        let original = TriggerCondition.scriptResult(path: "/a", expectedOutput: "x")
        let converted = TriggerCondition.make(kind: .scriptResult, preserving: original)
        #expect(converted.scriptValue?.path == "/a")
        #expect(converted.scriptValue?.expectedOutput == "x")
    }

    @Test func thermalLevelPreservedOnConversion() {
        let original = TriggerCondition.thermalPressure(atLeast: .critical)
        let converted = TriggerCondition.make(kind: .thermalPressure, preserving: original)
        #expect(converted.thermalLevel == .critical)
    }

    // MARK: - Image comparison

    /// Builds a small test image: the left `whiteColumns` columns white, rest black.
    private func makeImage(whiteColumns: Int, size: Int = 16) -> CGImage {
        let bytesPerRow = size
        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0 ..< size {
            for x in 0 ..< size where x < whiteColumns {
                pixels[y * size + x] = 255
            }
        }
        let context = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return context.makeImage()!
    }

    @Test func hammingDistanceBasics() {
        #expect(ImageHashing.hammingDistance(0, 0) == 0)
        #expect(ImageHashing.hammingDistance(0xFF, 0) == 8)
        #expect(ImageHashing.hammingDistance(.max, 0) == 64)
    }

    @Test func averageHashIsDeterministic() {
        let image = makeImage(whiteColumns: 8)
        #expect(ImageHashing.averageHash(image) == ImageHashing.averageHash(image))
    }

    @Test func averageHashDetectsLargeChange() throws {
        let mostlyBlack = try #require(ImageHashing.averageHash(makeImage(whiteColumns: 2)))
        let mostlyWhite = try #require(ImageHashing.averageHash(makeImage(whiteColumns: 14)))
        #expect(ImageHashing.hammingDistance(mostlyBlack, mostlyWhite) > ImageHashing.changeThreshold)
    }

    @Test func exactHashIsDeterministicAndPixelSensitive() {
        let first = makeImage(whiteColumns: 8)
        let same = makeImage(whiteColumns: 8)
        let changed = makeImage(whiteColumns: 9)

        #expect(ImageHashing.exactHash(first) == ImageHashing.exactHash(same))
        #expect(ImageHashing.exactHash(first) != ImageHashing.exactHash(changed))
    }

    @Test func imageChangedCondition() {
        let id = "com.apple.controlcenter:Battery"
        let reference: UInt64 = 0x0000_0000_0000_0000
        let condition = TriggerCondition.imageChanged(itemIdentifier: id, referenceHash: reference)

        var changed = state()
        changed.imageHashes = [id: .max] // 64 bits different -> changed
        #expect(condition.isSatisfied(state: changed))

        var same = state()
        same.imageHashes = [id: reference]
        #expect(!condition.isSatisfied(state: same))

        // No reference captured -> never satisfied.
        let noRef = TriggerCondition.imageChanged(itemIdentifier: id, referenceHash: nil)
        #expect(!noRef.isSatisfied(state: changed))
    }

    @Test func exactAndFuzzyImageComparisonDifferOnSmallChanges() {
        let id = "com.example:Status"
        var current = state()
        current.imageHashes = [id: 1] // One perceptual bit differs.
        current.exactImageHashes = [id: 101]

        let fuzzy = TriggerCondition.imageChanged(
            itemIdentifier: id,
            referenceHash: 0,
            referenceExactHash: 100,
            comparisonMode: .fuzzy
        )
        let exact = TriggerCondition.imageChanged(
            itemIdentifier: id,
            referenceHash: 0,
            referenceExactHash: 100,
            comparisonMode: .exact
        )

        #expect(!fuzzy.isSatisfied(state: current))
        #expect(exact.isSatisfied(state: current))
    }

    @Test func exactComparisonRequiresAnExactReference() {
        let condition = TriggerCondition.imageChanged(
            itemIdentifier: "item",
            referenceHash: 0,
            comparisonMode: .exact
        )
        var current = state()
        current.exactImageHashes = ["item": 1]
        #expect(!condition.isSatisfied(state: current))
    }

    @Test func imageChangedCodableRoundTrip() throws {
        let id = "com.apple.controlcenter:Battery"
        let condition = TriggerCondition.imageChanged(itemIdentifier: id, referenceHash: 0)

        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: data)

        #expect(decoded == condition)
    }

    @Test func imageChangedWithoutReferenceCodableRoundTrip() throws {
        let condition = TriggerCondition.imageChanged(itemIdentifier: "item", referenceHash: nil)

        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: data)

        #expect(decoded == condition)
    }

    @Test func imageComparisonSettingsCodableRoundTrip() throws {
        let condition = TriggerCondition.imageChanged(
            itemIdentifier: "item",
            referenceHash: 7,
            referenceExactHash: 11,
            comparisonMode: .exact,
            referenceImageData: Data([1, 2, 3])
        )

        let data = try JSONEncoder().encode(condition)
        #expect(try JSONDecoder().decode(TriggerCondition.self, from: data) == condition)
    }

    @Test func legacyImageComparisonDefaultsToFuzzyWithoutPreview() throws {
        let data = Data(#"{"imageChanged":{"itemIdentifier":"item","referenceHash":7}}"#.utf8)
        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: data)

        #expect(decoded.imageValue?.comparisonMode == .fuzzy)
        #expect(decoded.imageValue?.referenceHash == 7)
        #expect(decoded.imageValue?.referenceExactHash == nil)
        #expect(decoded.imageValue?.referenceImageData == nil)
    }

    @Test func capturedReferenceAndModeArePreserved() {
        let reference = ImageComparisonReference(
            perceptualHash: 7,
            exactHash: 11,
            imageData: Data([1, 2, 3])
        )
        let condition = TriggerCondition.imageChanged(
            itemIdentifier: "item",
            referenceHash: nil,
            comparisonMode: .exact
        )
        let captured = condition.withImageReference(reference)

        #expect(captured.imageValue?.comparisonMode == .exact)
        #expect(captured.imageValue?.referenceHash == 7)
        #expect(captured.imageValue?.referenceExactHash == 11)
        #expect(captured.imageValue?.referenceImageData == Data([1, 2, 3]))

        let changedItem = captured.withImageItem("other")
        #expect(changedItem.imageValue?.comparisonMode == .exact)
        #expect(changedItem.imageValue?.referenceHash == nil)
        #expect(changedItem.imageValue?.referenceExactHash == nil)
        #expect(changedItem.imageValue?.referenceImageData == nil)
    }

    // MARK: - Kind / editor mapping

    @Test func kindRoundTrip() {
        for kind in TriggerConditionKind.allCases {
            let condition = TriggerCondition.defaultCondition(for: kind)
            #expect(condition.kind == kind)
        }
    }

    @Test func makePreservesPercentage() {
        let original = TriggerCondition.batteryBelow(percentage: 15)
        let converted = TriggerCondition.make(kind: .batteryAtOrAbove, preserving: original)
        #expect(converted.percentage == 15)
    }

    @Test func makePreservesBundleID() {
        let original = TriggerCondition.frontmostApp(bundleID: "com.apple.Safari")
        let converted = TriggerCondition.make(kind: .appRunning, preserving: original)
        #expect(converted.bundleID == "com.apple.Safari")
    }

    @Test func requiredFeatureMapping() {
        #expect(TriggerConditionKind.batteryBelow.requiredFeature == nil)
        #expect(TriggerConditionKind.frontmostApp.requiredFeature == .frontmostApp)
        #expect(TriggerConditionKind.vpnActive.requiredFeature == .vpn)
        #expect(TriggerConditionKind.schedule.requiredFeature == .schedule)
        #expect(TriggerConditionKind.imageChanged.requiredFeature == .imageComparison)
    }

    @Test func frontmostAppUsesResponsiveSettleInterval() {
        #expect(TriggerConditionKind.frontmostApp.settleInterval == .milliseconds(1500))
    }

    @Test func appRunningUsesFastSettleInterval() {
        #expect(TriggerConditionKind.appRunning.settleInterval == .milliseconds(500))
    }

    @Test func runtimeStatusForDisabledTrigger() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            isEnabled: false,
            itemIdentifier: "com.example.StatusItem",
            condition: .onACPower
        )

        #expect(manager.runtimeStatus(for: trigger) == .off)
    }

    @Test("default manager does not persist fixtures into real defaults")
    func defaultManagerDoesNotPersistFixtures() throws {
        // A throwaway suite rather than per-key snapshot/restore. The restore
        // was correct, but the window between mutation and restore was
        // visible to anything else in the process reading this key, and an
        // interrupted run left the developer's real preferences modified.
        try withScratchDefaults { _ in
            let manager = MenuBarItemTriggersManager()
            manager.triggers = [
                MenuBarItemTrigger(
                    name: "Test fixture",
                    itemIdentifier: "test-only-item",
                    condition: .onACPower
                ),
            ]

            // Nothing was seeded into the scratch suite, so persisting here
            // would show up as a non-nil value.
            #expect(Defaults.data(forKey: .menuBarItemTriggers) == nil)
        }
    }

    @Test func runtimeStatusForUnappliedRevealDecision() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "com.example.StatusItem",
            condition: .onACPower
        )

        #expect(manager.runtimeStatus(for: trigger) == .pending)
    }

    @Test func runtimeStatusForFalseCondition() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "com.example.StatusItem",
            condition: .batteryBelow(percentage: 20)
        )

        #expect(manager.runtimeStatus(for: trigger) == .idle)
    }

    @Test func priorityPlanLetsLowerMetTriggerWinWhenHigherTriggerIsUnmet() {
        let manager = makeManager()
        let higher = MenuBarItemTrigger(
            name: "Battery low",
            itemIdentifier: "battery-item",
            condition: .batteryBelow(percentage: 75)
        )
        let lower = MenuBarItemTrigger(
            name: "On AC",
            itemIdentifier: "battery-item",
            condition: .onACPower
        )
        manager.triggers = [higher, lower]

        let plan = manager.priorityPlan(
            for: state(battery: 80, onAC: true),
            presentIdentifiers: ["battery-item"]
        )

        #expect(plan.actions[higher.id] == nil)
        #expect(
            plan.actions[lower.id]
                == MenuBarItemTriggersManager.TriggerPriorityAction(reveal: true, identifiers: ["battery-item"])
        )
    }

    @Test func priorityPlanMarksLowerMetTriggerOverriddenByHigherMetTrigger() {
        let manager = makeManager()
        let higher = MenuBarItemTrigger(
            name: "Top trigger",
            itemIdentifier: "battery-item",
            condition: .onACPower
        )
        let lower = MenuBarItemTrigger(
            name: "Lower trigger",
            itemIdentifier: "battery-item",
            condition: .onACPower
        )
        manager.triggers = [higher, lower]

        let plan = manager.priorityPlan(
            for: state(onAC: true),
            presentIdentifiers: ["battery-item"]
        )

        #expect(
            plan.actions[higher.id]
                == MenuBarItemTriggersManager.TriggerPriorityAction(reveal: true, identifiers: ["battery-item"])
        )
        #expect(plan.actions[lower.id] == nil)
        #expect(plan.overriddenBy[lower.id] == ["Top trigger"])
    }

    @Test func priorityPlanKeepsUnconflictedTargetsWhenMultiItemTriggerIsPartiallyOverridden() {
        let manager = makeManager()
        let higher = MenuBarItemTrigger(
            name: "Top trigger",
            itemIdentifier: "shared-item",
            condition: .onACPower
        )
        let lower = MenuBarItemTrigger(
            name: "Lower trigger",
            itemIdentifier: "shared-item",
            additionalItems: [TriggerTargetItem(identifier: "independent-item", displayName: "Independent")],
            condition: .onACPower
        )
        manager.triggers = [higher, lower]

        let plan = manager.priorityPlan(
            for: state(onAC: true),
            presentIdentifiers: ["shared-item", "independent-item"]
        )

        #expect(
            plan.actions[higher.id]
                == MenuBarItemTriggersManager.TriggerPriorityAction(reveal: true, identifiers: ["shared-item"])
        )
        #expect(
            plan.actions[lower.id]
                == MenuBarItemTriggersManager.TriggerPriorityAction(reveal: true, identifiers: ["independent-item"])
        )
        #expect(plan.overriddenBy[lower.id] == ["Top trigger"])
    }

    @Test func priorityPlanUsesHighestTriggerAsFallbackWhenNoneAreMet() {
        let manager = makeManager()
        let higher = MenuBarItemTrigger(
            name: "Battery below 75",
            itemIdentifier: "battery-item",
            condition: .batteryBelow(percentage: 75)
        )
        let lower = MenuBarItemTrigger(
            name: "Battery below 50",
            itemIdentifier: "battery-item",
            condition: .batteryBelow(percentage: 50)
        )
        manager.triggers = [higher, lower]

        let plan = manager.priorityPlan(
            for: state(battery: 80),
            presentIdentifiers: ["battery-item"]
        )

        #expect(
            plan.actions[higher.id]
                == MenuBarItemTriggersManager.TriggerPriorityAction(reveal: false, identifiers: ["battery-item"])
        )
        #expect(plan.actions[lower.id] == nil)
    }

    /// The built-in Battery item is governed by macOS's Show in Menu Bar
    /// preference. A conditional off-screen drag can turn that preference off,
    /// so the entire trigger is suspended before it claims ownership or plans
    /// either branch.
    @Test func priorityPlanProtectsControlCenterBatteryInBothBranches() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "com.apple.controlcenter:Battery",
            itemBaseIdentifier: "com.apple.controlcenter:Battery",
            condition: .batteryBelow(percentage: 50)
        )
        manager.triggers = [trigger]

        let hiddenPlan = manager.priorityPlan(
            for: state(battery: 75),
            presentIdentifiers: ["com.apple.controlcenter:Battery"],
            presentIdentifierBases: [
                "com.apple.controlcenter:Battery": "com.apple.controlcenter:Battery",
            ]
        )
        #expect(hiddenPlan.actions[trigger.id] == nil)
        #expect(hiddenPlan.protectedTriggerIDs.contains(trigger.id))
        #expect(!hiddenPlan.unavailableTriggerIDs.contains(trigger.id))

        let revealPlan = manager.priorityPlan(
            for: state(battery: 25),
            presentIdentifiers: ["com.apple.controlcenter:Battery"],
            presentIdentifierBases: [
                "com.apple.controlcenter:Battery": "com.apple.controlcenter:Battery",
            ]
        )
        #expect(revealPlan.actions[trigger.id] == nil)
        #expect(revealPlan.protectedTriggerIDs.contains(trigger.id))
    }

    @Test func priorityPlanRejectsMultiItemTriggerContainingProtectedBattery() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "com.example.Safe",
            itemBaseIdentifier: "com.example.Safe",
            additionalItems: [
                TriggerTargetItem(
                    identifier: "com.apple.controlcenter:Battery:1",
                    displayName: "Battery",
                    baseIdentifier: "com.apple.controlcenter:Battery"
                ),
            ],
            condition: .onACPower
        )
        manager.triggers = [trigger]

        let plan = manager.priorityPlan(
            for: state(onAC: true),
            presentIdentifiers: ["com.example.Safe", "com.apple.controlcenter:Battery:1"],
            presentIdentifierBases: [
                "com.example.Safe": "com.example.Safe",
                "com.apple.controlcenter:Battery:1": "com.apple.controlcenter:Battery",
            ]
        )

        #expect(plan.actions[trigger.id] == nil)
        #expect(plan.protectedTriggerIDs.contains(trigger.id))
    }

    @Test func priorityPlanReacquiresUnambiguousSuffixDriftFromLiveTagBases() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "com.example.app:Status:1",
            itemBaseIdentifier: "com.example.app:Status",
            condition: .onACPower
        )
        manager.triggers = [trigger]

        let plan = manager.priorityPlan(
            for: state(onAC: true),
            presentIdentifiers: ["com.example.app:Status:2"],
            presentIdentifierBases: ["com.example.app:Status:2": "com.example.app:Status"]
        )

        #expect(
            plan.actions[trigger.id]
                == MenuBarItemTriggersManager.TriggerPriorityAction(
                    reveal: true,
                    identifiers: ["com.example.app:Status:2"]
                )
        )
        #expect(!plan.unavailableTriggerIDs.contains(trigger.id))
    }

    @Test func priorityPlanDoesNotTreatLegacyNumericTitleAsAnInstanceSuffix() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "com.example.app:Meeting:30",
            condition: .onACPower
        )
        manager.triggers = [trigger]

        let plan = manager.priorityPlan(
            for: state(onAC: true),
            presentIdentifiers: ["com.example.app:Meeting"],
            presentIdentifierBases: ["com.example.app:Meeting": "com.example.app:Meeting"]
        )

        #expect(plan.actions[trigger.id] == nil)
        #expect(plan.unavailableTriggerIDs.contains(trigger.id))
    }

    @Test func moveTriggerReordersPriority() {
        let manager = makeManager()
        let first = MenuBarItemTrigger(name: "First")
        let second = MenuBarItemTrigger(name: "Second")
        let third = MenuBarItemTrigger(name: "Third")
        manager.triggers = [first, second, third]

        manager.moveTrigger(id: third.id, before: first.id)

        #expect(manager.triggers.map(\.id) == [third.id, first.id, second.id])
    }

    @Test func disableAllFeatureFlags() throws {
        try withScratchDefaults { _ in
            let manager = TriggerFeatureFlagsManager()

            manager.setEnabled(.frontmostApp, true)
            manager.setEnabled(.imageComparison, true)
            #expect(manager.hasEnabledFlags)

            manager.disableAll()

            #expect(!manager.hasEnabledFlags)
            #expect(!manager.isEnabled(.frontmostApp))
            #expect(!manager.isEnabled(.imageComparison))
            #expect(Defaults.stringArray(forKey: .triggerFeatureFlags) ?? [] == [])
        }
    }

    @Test func allOffMenuItemDefaultsHiddenAndPersists() throws {
        try withScratchDefaults { _ in
            let manager = TriggerFeatureFlagsManager()
            #expect(!manager.showsAllOffInMenuBarMenu)

            manager.showsAllOffInMenuBarMenu = true
            #expect(Defaults.bool(forKey: .showTriggerFeatureFlagsAllOffMenuItem))
            #expect(TriggerFeatureFlagsManager().showsAllOffInMenuBarMenu)

            manager.showsAllOffInMenuBarMenu = false
            #expect(!Defaults.bool(forKey: .showTriggerFeatureFlagsAllOffMenuItem))
        }
    }

    // MARK: - Compound conditions

    @Test("'All' requires every condition")
    func compoundAllRequiresEveryCondition() {
        let trigger = MenuBarItemTrigger(
            condition: .onBatteryPower,
            additionalConditions: [.batteryBelow(percentage: 30)],
            combinator: .all
        )
        // On battery AND below 30%.
        #expect(trigger.shouldReveal(state: state(battery: 20, onAC: false)))
        // On battery but not below 30%.
        #expect(!trigger.shouldReveal(state: state(battery: 80, onAC: false)))
        // Below 30% but on AC.
        #expect(!trigger.shouldReveal(state: state(battery: 20, onAC: true)))
    }

    @Test("'Any' requires at least one condition")
    func compoundAnyRequiresOneCondition() {
        let trigger = MenuBarItemTrigger(
            condition: .vpnActive,
            additionalConditions: [.wifiSSID(name: "Home")],
            combinator: .any
        )
        #expect(trigger.shouldReveal(state: state(vpn: true)))
        #expect(trigger.shouldReveal(state: state(vpn: false, ssid: "Home")))
        #expect(!trigger.shouldReveal(state: state(vpn: false, ssid: "Office")))
    }

    @Test func compoundWithInvert() {
        let trigger = MenuBarItemTrigger(
            condition: .onACPower,
            additionalConditions: [.charging],
            combinator: .all,
            invert: true
        )
        // AC and charging -> satisfied -> inverted hides (shouldReveal false).
        #expect(!trigger.shouldReveal(state: state(onAC: true, charging: true)))
        #expect(trigger.shouldReveal(state: state(onAC: true, charging: false)))
    }

    @Test func compoundCodableRoundTrip() throws {
        let trigger = MenuBarItemTrigger(
            condition: .onBatteryPower,
            additionalConditions: [.batteryBelow(percentage: 25), .thermalPressure(atLeast: .serious)],
            combinator: .any
        )
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        #expect(decoded == trigger)
    }

    // MARK: - Multiple target items

    @Test func allItemIdentifiersIncludesPrimaryAndAdditional() {
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "a",
            additionalItems: [TriggerTargetItem(identifier: "b", displayName: "B"), TriggerTargetItem(identifier: "", displayName: "")]
        )
        // Primary first, empties filtered out.
        #expect(trigger.allItemIdentifiers == ["a", "b"])
    }

    @Test func multiItemCodableRoundTrip() throws {
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "a",
            additionalItems: [TriggerTargetItem(identifier: "b", displayName: "B")],
            notifyOnReveal: true,
            settleSecondsOverride: 4
        )
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        #expect(decoded == trigger)
    }

    // MARK: - Invert

    @Test func invertFlipsReveal() {
        var trigger = MenuBarItemTrigger(condition: .onACPower)
        let onAC = state(onAC: true)
        #expect(trigger.shouldReveal(state: onAC))
        trigger.invert = true
        #expect(!trigger.shouldReveal(state: onAC))
    }

    // MARK: - Trigger model

    @Test func displayNameFallsBackToAutoTitle() {
        let trigger = MenuBarItemTrigger(
            name: "   ",
            itemDisplayName: "Battery",
            condition: .batteryBelow(percentage: 20)
        )
        #expect(trigger.displayName == "Battery: Battery is below 20%")
    }

    @Test func customNameOverridesAutoTitle() {
        let trigger = MenuBarItemTrigger(
            name: "Low battery",
            itemDisplayName: "Battery",
            condition: .batteryBelow(percentage: 20)
        )
        #expect(trigger.displayName == "Low battery")
    }

    @Test func autoTitleWithoutItemName() {
        let trigger = MenuBarItemTrigger(itemDisplayName: "", condition: .onACPower)
        #expect(trigger.autoTitle == "Connected to power")
    }

    @Test func repairsPersistedBatteryItemTestFixtureIdentifier() {
        let fixtures = [
            MenuBarItemTrigger(
                itemIdentifier: "battery-item",
                additionalItems: [
                    TriggerTargetItem(identifier: "battery-item", displayName: "battery-item"),
                    TriggerTargetItem(identifier: "com.example:Other", displayName: "Other"),
                ],
                condition: .batteryBelow(percentage: 75)
            ),
        ]

        let repaired = MenuBarItemTriggersManager.repairingLegacyTestFixtureIdentifiers(in: fixtures)

        #expect(repaired[0].itemIdentifier == "com.apple.controlcenter:Battery")
        #expect(repaired[0].itemDisplayName == "Battery")
        #expect(repaired[0].itemBaseIdentifier == "com.apple.controlcenter:Battery")
        #expect(repaired[0].additionalItems[0] == TriggerTargetItem(
            identifier: "com.apple.controlcenter:Battery",
            displayName: "Battery",
            baseIdentifier: "com.apple.controlcenter:Battery"
        ))
        #expect(repaired[0].additionalItems[1] == TriggerTargetItem(
            identifier: "com.example:Other",
            displayName: "Other",
            baseIdentifier: "com.example:Other"
        ))
    }

    @Test func repairsLegacyBatteryTargetSoItFollowsAnInstanceChange() {
        let manager = makeManager()
        let legacy = MenuBarItemTrigger(
            itemIdentifier: "com.apple.controlcenter:Battery",
            itemDisplayName: "Battery",
            condition: .batteryBelow(percentage: 50)
        )
        let repaired = MenuBarItemTriggersManager.repairingLegacyTestFixtureIdentifiers(in: [legacy])[0]
        manager.triggers = [repaired]

        let plan = manager.priorityPlan(
            for: state(battery: 25),
            presentIdentifiers: ["com.apple.controlcenter:Battery:1"],
            presentIdentifierBases: [
                "com.apple.controlcenter:Battery:1": "com.apple.controlcenter:Battery",
            ]
        )

        #expect(repaired.itemBaseIdentifier == "com.apple.controlcenter:Battery")
        #expect(plan.actions[repaired.id] == nil)
        #expect(plan.protectedTriggerIDs.contains(repaired.id))
        #expect(!plan.unavailableTriggerIDs.contains(repaired.id))
    }

    @Test func doesNotAddABaseToLegacyNumericTitle() {
        let legacy = MenuBarItemTrigger(
            itemIdentifier: "com.example.app:Meeting:30",
            itemDisplayName: "Meeting 30"
        )

        let repaired = MenuBarItemTriggersManager.repairingLegacyTestFixtureIdentifiers(in: [legacy])[0]

        #expect(repaired.itemBaseIdentifier == nil)
    }

    @Test func codableRoundTrip() throws {
        let trigger = MenuBarItemTrigger(
            name: "Show battery when low",
            itemIdentifier: "com.apple.controlcenter:Battery",
            itemDisplayName: "Battery",
            revealSection: .visible,
            hideSection: .alwaysHidden,
            condition: .batteryBelow(percentage: 20),
            invert: true
        )
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        #expect(decoded == trigger)
    }

    @Test func decodingWithoutInvertDefaultsFalse() throws {
        // Simulates a trigger persisted before `invert` existed.
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "isEnabled": true,
            "itemIdentifier": "x",
            "itemDisplayName": "X",
            "revealSection": "visible",
            "hideSection": "hidden",
            "condition": { "onACPower": {} }
        }
        """
        let data = Data(json.utf8)
        let expected = try MenuBarItemTrigger(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            name: "Legacy",
            itemIdentifier: "x",
            itemDisplayName: "X",
            condition: .onACPower
        )
        let decoded = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        #expect(decoded == expected)
        #expect(!decoded.invert)
    }

    // MARK: - Regression coverage for trigger integration

    @Test func presentIdentifierResolutionKeepsDuplicateTitleInstancesDistinct() {
        let present: Set = ["com.example:Status", "com.example:Status:1"]
        let bases = [
            "com.example:Status": "com.example:Status",
            "com.example:Status:1": "com.example:Status",
        ]

        #expect(
            MenuBarItemTriggersManager.resolvedPresentIdentifier(
                for: "com.example:Status:1",
                capturedBaseIdentifier: "com.example:Status",
                presentIdentifiers: present,
                presentIdentifierBases: bases
            ) == "com.example:Status:1"
        )
        #expect(
            MenuBarItemTriggersManager.resolvedPresentIdentifier(
                for: "com.example:Status:9",
                capturedBaseIdentifier: "com.example:Status",
                presentIdentifiers: present,
                presentIdentifierBases: bases
            ) == nil,
            "a stale suffix must not guess between two same-title siblings"
        )
    }

    @Test func savedOrderFilterRemovesOnlyTheControlledSibling() {
        let saved = [
            "visible": ["com.example:Status", "com.example:Status:1", "com.example:Other"],
        ]
        let filtered = MenuBarItemManager.savedOrderExcludingTriggerControlledIdentifiers(
            saved,
            controlledIdentifiers: ["com.example:Status:1"],
            knownBaseIdentifiers: ["com.example:Status", "com.example:Other"],
            knownLiveIdentifiers: ["com.example:Status", "com.example:Status:1", "com.example:Other"]
        )

        #expect(filtered["visible"] == ["com.example:Status", "com.example:Other"])
    }

    @Test func switchingBetweenDuplicateTitleInstancesReleasesTheOldSibling() {
        let released = MenuBarItemManager.releasedTriggerIdentifiers(
            previousIdentifiers: ["com.example:Status"],
            currentIdentifiers: ["com.example:Status:1"],
            knownBaseIdentifiers: ["com.example:Status"],
            knownLiveIdentifiers: ["com.example:Status", "com.example:Status:1"]
        )

        #expect(released == ["com.example:Status"])
    }

    @Test func singleLiveInstanceSuffixChangeRemainsContinuouslyControlled() {
        let released = MenuBarItemManager.releasedTriggerIdentifiers(
            previousIdentifiers: ["com.example:Status:1"],
            currentIdentifiers: ["com.example:Status:2"],
            knownBaseIdentifiers: ["com.example:Status"],
            knownLiveIdentifiers: ["com.example:Status:2"]
        )

        #expect(released.isEmpty)
    }

    @Test func desktopWithoutPowerSourcesDefaultsToAC() {
        let power = PowerSourceMonitor.state(from: [])

        #expect(power.isOnACPower)
        #expect(power.batteryPercentage == nil)
        #expect(!power.isCharging)
    }

    @Test func internalBatteryWinsOverLaterUPS() {
        let internalBattery: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSMaxCapacityKey: 100,
            kIOPSCurrentCapacityKey: 42,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
            kIOPSIsChargingKey: false,
        ]
        let ups: [String: Any] = [
            kIOPSTypeKey: kIOPSUPSType,
            kIOPSMaxCapacityKey: 100,
            kIOPSCurrentCapacityKey: 99,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSIsChargingKey: true,
        ]

        let power = PowerSourceMonitor.state(from: [internalBattery, ups])

        #expect(power.batteryPercentage == 42)
        #expect(!power.isOnACPower)
        #expect(!power.isCharging)
    }
}
