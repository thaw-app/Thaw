//
//  MenuBarItemTriggerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@MainActor
final class MenuBarItemTriggerTests: XCTestCase {
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
        focus: Bool = false
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
            isFocusActive: focus
        )
    }

    // MARK: - Battery / Power

    func testBatteryBelow() {
        XCTAssertTrue(TriggerCondition.batteryBelow(percentage: 50).isSatisfied(state: state(battery: 30)))
        XCTAssertFalse(TriggerCondition.batteryBelow(percentage: 50).isSatisfied(state: state(battery: 50)))
    }

    func testBatteryAtOrAbove() {
        XCTAssertTrue(TriggerCondition.batteryAtOrAbove(percentage: 50).isSatisfied(state: state(battery: 50)))
        XCTAssertFalse(TriggerCondition.batteryAtOrAbove(percentage: 50).isSatisfied(state: state(battery: 49)))
    }

    func testBatteryConditionsNeedBattery() {
        XCTAssertFalse(TriggerCondition.batteryBelow(percentage: 50).isSatisfied(state: state(battery: nil)))
        XCTAssertFalse(TriggerCondition.batteryAtOrAbove(percentage: 50).isSatisfied(state: state(battery: nil)))
    }

    func testPowerSourceConditions() {
        XCTAssertTrue(TriggerCondition.onACPower.isSatisfied(state: state(onAC: true)))
        XCTAssertFalse(TriggerCondition.onACPower.isSatisfied(state: state(onAC: false)))
        XCTAssertTrue(TriggerCondition.onBatteryPower.isSatisfied(state: state(onAC: false)))
        XCTAssertTrue(TriggerCondition.charging.isSatisfied(state: state(charging: true)))
    }

    // MARK: - Applications

    func testFrontmostApp() {
        let s = state(frontmost: "com.apple.Safari")
        XCTAssertTrue(TriggerCondition.frontmostApp(bundleID: "com.apple.Safari").isSatisfied(state: s))
        XCTAssertFalse(TriggerCondition.frontmostApp(bundleID: "com.apple.Mail").isSatisfied(state: s))
        XCTAssertFalse(TriggerCondition.frontmostApp(bundleID: "").isSatisfied(state: s))
    }

    func testAppRunning() {
        let s = state(running: ["com.apple.Safari", "com.apple.Mail"])
        XCTAssertTrue(TriggerCondition.appRunning(bundleID: "com.apple.Mail").isSatisfied(state: s))
        XCTAssertFalse(TriggerCondition.appRunning(bundleID: "com.apple.Music").isSatisfied(state: s))
    }

    // MARK: - Network / Devices

    func testNetworkAndVPN() {
        XCTAssertTrue(TriggerCondition.networkConnected.isSatisfied(state: state(networkConnected: true)))
        XCTAssertFalse(TriggerCondition.networkConnected.isSatisfied(state: state(networkConnected: false)))
        XCTAssertTrue(TriggerCondition.vpnActive.isSatisfied(state: state(vpn: true)))
    }

    func testWiFiSSIDCaseInsensitive() {
        let s = state(ssid: "HomeNet")
        XCTAssertTrue(TriggerCondition.wifiSSID(name: "homenet").isSatisfied(state: s))
        XCTAssertFalse(TriggerCondition.wifiSSID(name: "Office").isSatisfied(state: s))
    }

    func testBluetoothSubstringMatch() {
        let s = state(bluetooth: ["Alvie's AirPods Pro"])
        XCTAssertTrue(TriggerCondition.bluetoothConnected(name: "airpods").isSatisfied(state: s))
        XCTAssertFalse(TriggerCondition.bluetoothConnected(name: "Magic Mouse").isSatisfied(state: s))
    }

    func testAudioOutputSubstring() {
        let s = state(audio: "External Headphones")
        XCTAssertTrue(TriggerCondition.audioOutput(contains: "headphones").isSatisfied(state: s))
        XCTAssertFalse(TriggerCondition.audioOutput(contains: "speakers").isSatisfied(state: s))
    }

    func testExternalDisplay() {
        XCTAssertTrue(TriggerCondition.externalDisplayConnected.isSatisfied(state: state(externalDisplay: true)))
        XCTAssertFalse(TriggerCondition.externalDisplayConnected.isSatisfied(state: state(externalDisplay: false)))
    }

    func testFocusActive() {
        XCTAssertTrue(TriggerCondition.focusActive.isSatisfied(state: state(focus: true)))
        XCTAssertFalse(TriggerCondition.focusActive.isSatisfied(state: state(focus: false)))
    }

    // MARK: - Location

    private func locatedState(lat: Double, lon: Double) -> SystemState {
        var s = state()
        s.currentLatitude = lat
        s.currentLongitude = lon
        return s
    }

    func testNearLocationWithinRadius() {
        // ~11m north of the target — inside a 150m radius.
        let condition = TriggerCondition.nearLocation(
            latitude: 37.3349, longitude: -122.0090, radiusMeters: 150, label: "Work"
        )
        XCTAssertTrue(condition.isSatisfied(state: locatedState(lat: 37.3350, lon: -122.0090)))
    }

    func testNearLocationOutsideRadius() {
        // Cupertino target vs San Francisco current — far outside any radius.
        let condition = TriggerCondition.nearLocation(
            latitude: 37.3349, longitude: -122.0090, radiusMeters: 150, label: "Work"
        )
        XCTAssertFalse(condition.isSatisfied(state: locatedState(lat: 37.7749, lon: -122.4194)))
    }

    func testNearLocationWithoutFixIsFalse() {
        let condition = TriggerCondition.nearLocation(
            latitude: 37.3349, longitude: -122.0090, radiusMeters: 150, label: "Work"
        )
        XCTAssertFalse(condition.isSatisfied(state: state()))
    }

    func testWithLocationUpdatesFields() {
        let base = TriggerCondition.nearLocation(latitude: 0, longitude: 0, radiusMeters: 150, label: "")
        let updated = base.withLocation(latitude: 1, longitude: 2, radiusMeters: 300, label: "Home")
        XCTAssertEqual(updated.locationValue?.latitude, 1)
        XCTAssertEqual(updated.locationValue?.longitude, 2)
        XCTAssertEqual(updated.locationValue?.radiusMeters, 300)
        XCTAssertEqual(updated.locationValue?.label, "Home")
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

    func testScheduleNonWrapping() {
        let condition = TriggerCondition.schedule(startMinutes: 9 * 60, endMinutes: 17 * 60)
        XCTAssertTrue(condition.isSatisfied(state: state(), now: date(hour: 12, minute: 0)))
        XCTAssertFalse(condition.isSatisfied(state: state(), now: date(hour: 8, minute: 0)))
        XCTAssertFalse(condition.isSatisfied(state: state(), now: date(hour: 17, minute: 0)))
    }

    func testScheduleWrappingMidnight() {
        let condition = TriggerCondition.schedule(startMinutes: 22 * 60, endMinutes: 6 * 60)
        XCTAssertTrue(condition.isSatisfied(state: state(), now: date(hour: 23, minute: 0)))
        XCTAssertTrue(condition.isSatisfied(state: state(), now: date(hour: 2, minute: 0)))
        XCTAssertFalse(condition.isSatisfied(state: state(), now: date(hour: 12, minute: 0)))
    }

    func testScheduleEmptyWindow() {
        let condition = TriggerCondition.schedule(startMinutes: 600, endMinutes: 600)
        XCTAssertFalse(condition.isSatisfied(state: state(), now: date(hour: 10, minute: 0)))
    }

    func testWeeklyScheduleNonWrapping() {
        let condition = TriggerCondition.weeklySchedule(
            startMinutes: 9 * 60,
            endMinutes: 17 * 60,
            weekdays: [.monday]
        )

        XCTAssertTrue(condition.isSatisfied(state: state(), now: date(day: 22, hour: 12, minute: 0)))
        XCTAssertFalse(condition.isSatisfied(state: state(), now: date(day: 23, hour: 12, minute: 0)))
        XCTAssertFalse(condition.isSatisfied(state: state(), now: date(day: 22, hour: 8, minute: 0)))
    }

    func testWeeklyScheduleWrappingMidnightUsesStartDay() {
        let condition = TriggerCondition.weeklySchedule(
            startMinutes: 22 * 60,
            endMinutes: 6 * 60,
            weekdays: [.monday]
        )

        XCTAssertTrue(condition.isSatisfied(state: state(), now: date(day: 22, hour: 23, minute: 0)))
        XCTAssertTrue(condition.isSatisfied(state: state(), now: date(day: 23, hour: 2, minute: 0)))
        XCTAssertFalse(condition.isSatisfied(state: state(), now: date(day: 23, hour: 23, minute: 0)))
        XCTAssertFalse(condition.isSatisfied(state: state(), now: date(day: 22, hour: 2, minute: 0)))
    }

    func testWeeklyScheduleCodableRoundTrip() throws {
        let condition = TriggerCondition.weeklySchedule(
            startMinutes: 9 * 60,
            endMinutes: 17 * 60,
            weekdays: [.monday, .wednesday, .friday]
        )

        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: data)

        XCTAssertEqual(decoded, condition)
    }

    func testLegacyScheduleDefaultsToEveryDay() throws {
        let json = """
        { "schedule": { "startMinutes": 540, "endMinutes": 1020 } }
        """

        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.scheduleWindow?.start, 540)
        XCTAssertEqual(decoded.scheduleWindow?.end, 1020)
        XCTAssertEqual(decoded.scheduleWeekdays, ScheduleWeekday.everyDay)
    }

    // MARK: - System load

    func testLowPowerMode() {
        var on = state()
        on.energyMode = .low
        XCTAssertTrue(TriggerCondition.lowPowerMode.isSatisfied(state: on))
        XCTAssertFalse(TriggerCondition.lowPowerMode.isSatisfied(state: state()))
    }

    /// The layout editor reads this per item on every redraw, so it is
    /// memoized — it has to survive edits to the trigger list.
    func testControlledBaseIdentifiersTracksTriggerEdits() {
        let manager = makeManager()
        XCTAssertFalse(manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))

        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.example.Status",
                condition: .onACPower
            ),
        ]
        XCTAssertTrue(manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))

        manager.triggers[0].isEnabled = false
        XCTAssertFalse(manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))

        manager.triggers = []
        XCTAssertFalse(manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))
        XCTAssertFalse(manager.isControlledByTrigger(baseIdentifier: ""))
    }

    /// A legacy target stored with an instance suffix and no captured base
    /// must still read as owned when queried by the live base — the badge
    /// and the tooltip resolve ownership through different paths, and they
    /// have to agree.
    func testLegacySuffixedTargetWithoutBaseIsOwned() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.example.Status:2",
                condition: .onACPower
            ),
        ]

        XCTAssertTrue(manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))
        XCTAssertNotNil(manager.controllingTrigger(forBaseIdentifier: "com.example.Status"))
        // A title that merely ends in ":<number>" is not an instance suffix
        // unless the base is live; an unrelated base must not match.
        XCTAssertFalse(manager.isControlledByTrigger(baseIdentifier: "com.example.Other"))
    }

    /// The two ownership queries answer from the same predicate: whenever the
    /// set says owned, the tooltip lookup must produce the owning trigger.
    func testOwnershipQueriesAgree() {
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
            XCTAssertEqual(
                manager.isControlledByTrigger(baseIdentifier: base),
                manager.controllingTrigger(forBaseIdentifier: base) != nil,
                "queries disagree for \(base)"
            )
        }
    }

    /// A target stored with an instance suffix is owned under both spellings,
    /// since the live tag resolves to the base.
    func testControlledBaseIdentifiersCoversCapturedBase() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.example.Status:2",
                itemBaseIdentifier: "com.example.Status",
                condition: .onACPower
            ),
        ]

        XCTAssertTrue(manager.isControlledByTrigger(baseIdentifier: "com.example.Status"))
        XCTAssertTrue(manager.isControlledByTrigger(baseIdentifier: "com.example.Status:2"))
    }

    // MARK: - Combinators

    func testNoneOfIsSatisfiedOnlyWhenNoConditionIs() {
        var trigger = MenuBarItemTrigger(
            itemIdentifier: "item",
            condition: .onACPower
        )
        trigger.additionalConditions = [.charging]
        trigger.combinator = .noneOf

        // Neither holds.
        XCTAssertTrue(trigger.shouldReveal(state: state(onAC: false, charging: false)))
        // One holds.
        XCTAssertFalse(trigger.shouldReveal(state: state(onAC: true, charging: false)))
        XCTAssertFalse(trigger.shouldReveal(state: state(onAC: false, charging: true)))
        // Both hold.
        XCTAssertFalse(trigger.shouldReveal(state: state(onAC: true, charging: true)))
    }

    /// "None of" is the condition-side negation; `invert` is the action-side
    /// one. Combining them has to cancel out, not compound.
    func testNoneOfComposesWithInvert() {
        var trigger = MenuBarItemTrigger(
            itemIdentifier: "item",
            condition: .onACPower
        )
        trigger.combinator = .noneOf
        trigger.invert = true

        XCTAssertTrue(trigger.shouldReveal(state: state(onAC: true)))
        XCTAssertFalse(trigger.shouldReveal(state: state(onAC: false)))
    }

    /// Joining with " or " alone would read as if any one of them fired the
    /// trigger, which is the opposite of what "None of" means.
    func testNoneOfSummaryStatesTheRelationship() {
        var trigger = MenuBarItemTrigger(
            itemIdentifier: "item",
            condition: .onACPower
        )
        trigger.combinator = .noneOf

        XCTAssertEqual(trigger.conditionSummary, "Not: Connected to power")

        trigger.additionalConditions = [.charging]
        XCTAssertEqual(
            trigger.conditionSummary,
            "None of: Connected to power or Battery is charging"
        )
    }

    /// The raw value is persisted, so it must stay stable, and triggers saved
    /// before the combinator existed must still decode.
    func testCombinatorCodableRoundTrip() throws {
        XCTAssertEqual(TriggerCombinator.noneOf.rawValue, "none")

        var trigger = MenuBarItemTrigger(itemIdentifier: "item", condition: .onACPower)
        trigger.combinator = .noneOf
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        XCTAssertEqual(decoded.combinator, .noneOf)
    }

    // MARK: - Layout ownership

    /// The layout editor asks this to decide whether an item is still the
    /// user's to place.
    func testControllingTriggerFindsEnabledTargetingTrigger() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.apple.controlcenter:Battery",
                condition: .batteryBelow(percentage: 69)
            ),
        ]

        let owner = manager.controllingTrigger(forBaseIdentifier: "com.apple.controlcenter:Battery")

        XCTAssertEqual(owner?.itemIdentifier, "com.apple.controlcenter:Battery")
        XCTAssertNil(manager.controllingTrigger(forBaseIdentifier: "com.example.Other"))
        XCTAssertNil(manager.controllingTrigger(forBaseIdentifier: ""))
    }

    /// Ownership is claimed by an enabled trigger whether or not its
    /// condition is currently met, matching when the item manager takes the
    /// item over. A disabled trigger claims nothing.
    func testControllingTriggerIgnoresDisabledTriggers() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: false,
                itemIdentifier: "com.apple.controlcenter:Battery",
                condition: .batteryBelow(percentage: 69)
            ),
        ]

        XCTAssertNil(manager.controllingTrigger(forBaseIdentifier: "com.apple.controlcenter:Battery"))
    }

    /// A stored target carrying a stale instance suffix still resolves to the
    /// live item, so the layout editor doesn't quietly re-open a locked item.
    func testControllingTriggerFollowsInstanceSuffixDrift() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                isEnabled: true,
                itemIdentifier: "com.apple.controlcenter:Battery:2",
                condition: .onBatteryPower
            ),
        ]

        XCTAssertNotNil(manager.controllingTrigger(forBaseIdentifier: "com.apple.controlcenter:Battery"))
    }

    /// Two enabled triggers on one item resolve to the higher-priority one,
    /// the same winner the priority plan picks.
    func testControllingTriggerPrefersHigherPriority() {
        let manager = makeManager()
        manager.triggers = [
            MenuBarItemTrigger(
                name: "First",
                isEnabled: true,
                itemIdentifier: "com.apple.controlcenter:Battery",
                condition: .onBatteryPower
            ),
            MenuBarItemTrigger(
                name: "Second",
                isEnabled: true,
                itemIdentifier: "com.apple.controlcenter:Battery",
                condition: .onACPower
            ),
        ]

        XCTAssertEqual(
            manager.controllingTrigger(forBaseIdentifier: "com.apple.controlcenter:Battery")?.displayName,
            "First"
        )
    }

    func testEnergyModeMatchesExactMode() {
        for mode in EnergyMode.allCases {
            var current = state()
            current.energyMode = mode

            XCTAssertEqual(TriggerCondition.energyMode(.low).isSatisfied(state: current), mode == .low)
            XCTAssertEqual(TriggerCondition.energyMode(.automatic).isSatisfied(state: current), mode == .automatic)
            XCTAssertEqual(TriggerCondition.energyMode(.high).isSatisfied(state: current), mode == .high)
        }
    }

    /// "Not Low Power" has to cover High Power too, not just Automatic —
    /// the case that a plain inversion of the old boolean would get wrong.
    func testNotLowPowerCoversAutomaticAndHigh() {
        var low = state()
        low.energyMode = .low
        XCTAssertFalse(TriggerCondition.energyMode(.notLow).isSatisfied(state: low))

        for mode in [EnergyMode.automatic, .high] {
            var current = state()
            current.energyMode = mode
            XCTAssertTrue(
                TriggerCondition.energyMode(.notLow).isSatisfied(state: current),
                "Not Low Power should be satisfied in \(mode.displayString)"
            )
        }
    }

    /// Triggers saved before Energy Mode replaced the Low Power Mode
    /// condition must keep decoding, and keep meaning "Low Power".
    func testLegacyLowPowerModeDecodesAndBehavesAsLow() throws {
        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: Data(#"{ "lowPowerMode": {} }"#.utf8))

        XCTAssertEqual(decoded.kind, .energyMode)
        XCTAssertEqual(decoded.energyModeMatch, .low)

        var low = state()
        low.energyMode = .low
        XCTAssertTrue(decoded.isSatisfied(state: low))

        var high = state()
        high.energyMode = .high
        XCTAssertFalse(decoded.isSatisfied(state: high))
    }

    /// Editing a legacy condition upgrades it in place rather than leaving
    /// a value the editor can't represent.
    func testEditingLegacyLowPowerModeProducesEnergyMode() {
        XCTAssertEqual(TriggerCondition.lowPowerMode.withEnergyMode(.high), .energyMode(.high))
        XCTAssertEqual(
            TriggerCondition.make(kind: .energyMode, preserving: .lowPowerMode),
            .energyMode(.low)
        )
    }

    /// Switching to a kind that carries no compatible value still yields the
    /// Energy Mode default rather than dropping the selection.
    func testEnergyModeDefaults() {
        XCTAssertEqual(TriggerCondition.defaultCondition(for: .energyMode), .energyMode(.low))
        XCTAssertEqual(TriggerCondition.make(kind: .energyMode, preserving: .charging), .energyMode(.low))
        XCTAssertEqual(TriggerCondition.energyMode(.high).kind.editor, .energyMode)
    }

    func testHighPowerModeIsOfferedOnlyWhereSupported() {
        XCTAssertEqual(
            EnergyModeMatch.selectableCases(highPowerModeSupported: true),
            [.low, .notLow, .automatic, .high]
        )
        XCTAssertEqual(
            EnergyModeMatch.selectableCases(highPowerModeSupported: false),
            [.low, .notLow, .automatic]
        )
    }

    func testThermalPressureThreshold() {
        var serious = state()
        serious.thermalState = .serious
        XCTAssertTrue(TriggerCondition.thermalPressure(atLeast: .fair).isSatisfied(state: serious))
        XCTAssertTrue(TriggerCondition.thermalPressure(atLeast: .serious).isSatisfied(state: serious))
        XCTAssertFalse(TriggerCondition.thermalPressure(atLeast: .critical).isSatisfied(state: serious))

        var nominal = state()
        nominal.thermalState = .nominal
        XCTAssertFalse(TriggerCondition.thermalPressure(atLeast: .fair).isSatisfied(state: nominal))
    }

    func testCameraInUse() {
        var on = state()
        on.isCameraInUse = true
        XCTAssertTrue(TriggerCondition.cameraInUse.isSatisfied(state: on))
        XCTAssertFalse(TriggerCondition.cameraInUse.isSatisfied(state: state()))
    }

    func testMicrophoneInUse() {
        var on = state()
        on.isMicrophoneInUse = true
        XCTAssertTrue(TriggerCondition.microphoneInUse.isSatisfied(state: on))
        XCTAssertFalse(TriggerCondition.microphoneInUse.isSatisfied(state: state()))
    }

    // MARK: - Script result

    private func scriptState(_ path: String, exit: Int32, output: String) -> SystemState {
        var s = state()
        s.scriptOutcomes = [path: ScriptOutcome(exitCode: exit, output: output)]
        return s
    }

    func testScriptResultExitCode() {
        let condition = TriggerCondition.scriptResult(path: "/tmp/s.sh", expectedOutput: "")
        XCTAssertTrue(condition.isSatisfied(state: scriptState("/tmp/s.sh", exit: 0, output: "")))
        XCTAssertFalse(condition.isSatisfied(state: scriptState("/tmp/s.sh", exit: 1, output: "")))
        // No outcome cached -> not satisfied.
        XCTAssertFalse(condition.isSatisfied(state: state()))
    }

    func testScriptResultOutputMatch() {
        let condition = TriggerCondition.scriptResult(path: "/tmp/s.sh", expectedOutput: "online")
        XCTAssertTrue(condition.isSatisfied(state: scriptState("/tmp/s.sh", exit: 0, output: "status: ONLINE")))
        XCTAssertFalse(condition.isSatisfied(state: scriptState("/tmp/s.sh", exit: 0, output: "offline")))
    }

    func testScriptValuePreservedOnConversion() {
        let original = TriggerCondition.scriptResult(path: "/a", expectedOutput: "x")
        let converted = TriggerCondition.make(kind: .scriptResult, preserving: original)
        XCTAssertEqual(converted.scriptValue?.path, "/a")
        XCTAssertEqual(converted.scriptValue?.expectedOutput, "x")
    }

    func testThermalLevelPreservedOnConversion() {
        let original = TriggerCondition.thermalPressure(atLeast: .critical)
        let converted = TriggerCondition.make(kind: .thermalPressure, preserving: original)
        XCTAssertEqual(converted.thermalLevel, .critical)
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

    func testHammingDistanceBasics() {
        XCTAssertEqual(ImageHashing.hammingDistance(0, 0), 0)
        XCTAssertEqual(ImageHashing.hammingDistance(0xFF, 0), 8)
        XCTAssertEqual(ImageHashing.hammingDistance(.max, 0), 64)
    }

    func testAverageHashIsDeterministic() {
        let image = makeImage(whiteColumns: 8)
        XCTAssertEqual(ImageHashing.averageHash(image), ImageHashing.averageHash(image))
    }

    func testAverageHashDetectsLargeChange() throws {
        let mostlyBlack = try XCTUnwrap(ImageHashing.averageHash(makeImage(whiteColumns: 2)))
        let mostlyWhite = try XCTUnwrap(ImageHashing.averageHash(makeImage(whiteColumns: 14)))
        XCTAssertGreaterThan(ImageHashing.hammingDistance(mostlyBlack, mostlyWhite), ImageHashing.changeThreshold)
    }

    func testImageChangedCondition() {
        let id = "com.apple.controlcenter:Battery"
        let reference: UInt64 = 0x0000_0000_0000_0000
        let condition = TriggerCondition.imageChanged(itemIdentifier: id, referenceHash: reference)

        var changed = state()
        changed.imageHashes = [id: .max] // 64 bits different -> changed
        XCTAssertTrue(condition.isSatisfied(state: changed))

        var same = state()
        same.imageHashes = [id: reference]
        XCTAssertFalse(condition.isSatisfied(state: same))

        // No reference captured -> never satisfied.
        let noRef = TriggerCondition.imageChanged(itemIdentifier: id, referenceHash: nil)
        XCTAssertFalse(noRef.isSatisfied(state: changed))
    }

    func testImageChangedCodableRoundTrip() throws {
        let id = "com.apple.controlcenter:Battery"
        let condition = TriggerCondition.imageChanged(itemIdentifier: id, referenceHash: 0)

        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: data)

        XCTAssertEqual(decoded, condition)
    }

    func testImageChangedWithoutReferenceCodableRoundTrip() throws {
        let condition = TriggerCondition.imageChanged(itemIdentifier: "item", referenceHash: nil)

        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(TriggerCondition.self, from: data)

        XCTAssertEqual(decoded, condition)
    }

    // MARK: - Kind / editor mapping

    func testKindRoundTrip() {
        for kind in TriggerConditionKind.allCases {
            let condition = TriggerCondition.defaultCondition(for: kind)
            XCTAssertEqual(condition.kind, kind)
        }
    }

    func testMakePreservesPercentage() {
        let original = TriggerCondition.batteryBelow(percentage: 15)
        let converted = TriggerCondition.make(kind: .batteryAtOrAbove, preserving: original)
        XCTAssertEqual(converted.percentage, 15)
    }

    func testMakePreservesBundleID() {
        let original = TriggerCondition.frontmostApp(bundleID: "com.apple.Safari")
        let converted = TriggerCondition.make(kind: .appRunning, preserving: original)
        XCTAssertEqual(converted.bundleID, "com.apple.Safari")
    }

    func testRequiredFeatureMapping() {
        XCTAssertNil(TriggerConditionKind.batteryBelow.requiredFeature)
        XCTAssertEqual(TriggerConditionKind.frontmostApp.requiredFeature, .frontmostApp)
        XCTAssertEqual(TriggerConditionKind.vpnActive.requiredFeature, .vpn)
        XCTAssertEqual(TriggerConditionKind.schedule.requiredFeature, .schedule)
        XCTAssertEqual(TriggerConditionKind.imageChanged.requiredFeature, .imageComparison)
    }

    func testFrontmostAppUsesResponsiveSettleInterval() {
        XCTAssertEqual(TriggerConditionKind.frontmostApp.settleInterval, .milliseconds(1500))
    }

    func testAppRunningUsesFastSettleInterval() {
        XCTAssertEqual(TriggerConditionKind.appRunning.settleInterval, .milliseconds(500))
    }

    @MainActor
    func testRuntimeStatusForDisabledTrigger() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            isEnabled: false,
            itemIdentifier: "com.example.StatusItem",
            condition: .onACPower
        )

        XCTAssertEqual(manager.runtimeStatus(for: trigger), .off)
    }

    @MainActor
    func testDefaultManagerDoesNotPersistFixturesUnderXCTest() {
        let original = Defaults.data(forKey: .menuBarItemTriggers)
        defer {
            if Defaults.data(forKey: .menuBarItemTriggers) != original {
                if let original {
                    Defaults.set(original, forKey: .menuBarItemTriggers)
                } else {
                    Defaults.removeObject(forKey: .menuBarItemTriggers)
                }
            }
        }

        let manager = MenuBarItemTriggersManager()
        manager.triggers = [
            MenuBarItemTrigger(
                name: "Test fixture",
                itemIdentifier: "test-only-item",
                condition: .onACPower
            ),
        ]

        XCTAssertEqual(Defaults.data(forKey: .menuBarItemTriggers), original)
    }

    @MainActor
    func testRuntimeStatusForUnappliedRevealDecision() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "com.example.StatusItem",
            condition: .onACPower
        )

        XCTAssertEqual(manager.runtimeStatus(for: trigger), .pending)
    }

    @MainActor
    func testRuntimeStatusForFalseCondition() {
        let manager = makeManager()
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "com.example.StatusItem",
            condition: .batteryBelow(percentage: 20)
        )

        XCTAssertEqual(manager.runtimeStatus(for: trigger), .idle)
    }

    @MainActor
    func testPriorityPlanLetsLowerMetTriggerWinWhenHigherTriggerIsUnmet() {
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

        XCTAssertNil(plan.actions[higher.id])
        XCTAssertEqual(
            plan.actions[lower.id],
            MenuBarItemTriggersManager.TriggerPriorityAction(reveal: true, identifiers: ["battery-item"])
        )
    }

    @MainActor
    func testPriorityPlanMarksLowerMetTriggerOverriddenByHigherMetTrigger() {
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

        XCTAssertEqual(
            plan.actions[higher.id],
            MenuBarItemTriggersManager.TriggerPriorityAction(reveal: true, identifiers: ["battery-item"])
        )
        XCTAssertNil(plan.actions[lower.id])
        XCTAssertEqual(plan.overriddenBy[lower.id], ["Top trigger"])
    }

    @MainActor
    func testPriorityPlanKeepsUnconflictedTargetsWhenMultiItemTriggerIsPartiallyOverridden() {
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

        XCTAssertEqual(
            plan.actions[higher.id],
            MenuBarItemTriggersManager.TriggerPriorityAction(reveal: true, identifiers: ["shared-item"])
        )
        XCTAssertEqual(
            plan.actions[lower.id],
            MenuBarItemTriggersManager.TriggerPriorityAction(reveal: true, identifiers: ["independent-item"])
        )
        XCTAssertEqual(plan.overriddenBy[lower.id], ["Top trigger"])
    }

    @MainActor
    func testPriorityPlanUsesHighestTriggerAsFallbackWhenNoneAreMet() {
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

        XCTAssertEqual(
            plan.actions[higher.id],
            MenuBarItemTriggersManager.TriggerPriorityAction(reveal: false, identifiers: ["battery-item"])
        )
        XCTAssertNil(plan.actions[lower.id])
    }

    /// Battery hides like any other target. An earlier revision exempted the
    /// Control Center Battery control from the hide branch, on the theory
    /// that concealing it would turn off the system's own Show in Menu Bar
    /// setting; that does not happen, and the exemption made a trigger
    /// silently ignore the "Otherwise hide in" section the user picked.
    @MainActor
    func testPriorityPlanHidesControlCenterBatteryWhenConditionClears() {
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
        XCTAssertEqual(
            hiddenPlan.actions[trigger.id],
            MenuBarItemTriggersManager.TriggerPriorityAction(
                reveal: false,
                identifiers: ["com.apple.controlcenter:Battery"]
            )
        )
        XCTAssertFalse(hiddenPlan.unavailableTriggerIDs.contains(trigger.id))

        let revealPlan = manager.priorityPlan(
            for: state(battery: 25),
            presentIdentifiers: ["com.apple.controlcenter:Battery"],
            presentIdentifierBases: [
                "com.apple.controlcenter:Battery": "com.apple.controlcenter:Battery",
            ]
        )
        XCTAssertEqual(
            revealPlan.actions[trigger.id],
            MenuBarItemTriggersManager.TriggerPriorityAction(
                reveal: true,
                identifiers: ["com.apple.controlcenter:Battery"]
            )
        )
    }

    @MainActor
    func testPriorityPlanReacquiresUnambiguousSuffixDriftFromLiveTagBases() {
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

        XCTAssertEqual(
            plan.actions[trigger.id],
            MenuBarItemTriggersManager.TriggerPriorityAction(
                reveal: true,
                identifiers: ["com.example.app:Status:2"]
            )
        )
        XCTAssertFalse(plan.unavailableTriggerIDs.contains(trigger.id))
    }

    @MainActor
    func testPriorityPlanDoesNotTreatLegacyNumericTitleAsAnInstanceSuffix() {
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

        XCTAssertNil(plan.actions[trigger.id])
        XCTAssertTrue(plan.unavailableTriggerIDs.contains(trigger.id))
    }

    @MainActor
    func testMoveTriggerReordersPriority() {
        let manager = makeManager()
        let first = MenuBarItemTrigger(name: "First")
        let second = MenuBarItemTrigger(name: "Second")
        let third = MenuBarItemTrigger(name: "Third")
        manager.triggers = [first, second, third]

        manager.moveTrigger(id: third.id, before: first.id)

        XCTAssertEqual(manager.triggers.map(\.id), [third.id, first.id, second.id])
    }

    @MainActor
    func testDisableAllFeatureFlags() {
        let previous = Defaults.stringArray(forKey: .triggerFeatureFlags)
        defer {
            if let previous {
                Defaults.set(previous, forKey: .triggerFeatureFlags)
            } else {
                Defaults.removeObject(forKey: .triggerFeatureFlags)
            }
        }

        Defaults.removeObject(forKey: .triggerFeatureFlags)
        let manager = TriggerFeatureFlagsManager()

        manager.setEnabled(.frontmostApp, true)
        manager.setEnabled(.imageComparison, true)
        XCTAssertTrue(manager.hasEnabledFlags)

        manager.disableAll()

        XCTAssertFalse(manager.hasEnabledFlags)
        XCTAssertFalse(manager.isEnabled(.frontmostApp))
        XCTAssertFalse(manager.isEnabled(.imageComparison))
        XCTAssertEqual(Defaults.stringArray(forKey: .triggerFeatureFlags) ?? [], [])
    }

    @MainActor
    func testAllOffMenuItemDefaultsHiddenAndPersists() {
        let previous = Defaults.object(forKey: .showTriggerFeatureFlagsAllOffMenuItem)
        defer {
            if let previous {
                Defaults.set(previous, forKey: .showTriggerFeatureFlagsAllOffMenuItem)
            } else {
                Defaults.removeObject(forKey: .showTriggerFeatureFlagsAllOffMenuItem)
            }
        }

        Defaults.removeObject(forKey: .showTriggerFeatureFlagsAllOffMenuItem)
        let manager = TriggerFeatureFlagsManager()
        XCTAssertFalse(manager.showsAllOffInMenuBarMenu)

        manager.showsAllOffInMenuBarMenu = true
        XCTAssertTrue(Defaults.bool(forKey: .showTriggerFeatureFlagsAllOffMenuItem))
        XCTAssertTrue(TriggerFeatureFlagsManager().showsAllOffInMenuBarMenu)

        manager.showsAllOffInMenuBarMenu = false
        XCTAssertFalse(Defaults.bool(forKey: .showTriggerFeatureFlagsAllOffMenuItem))
    }

    // MARK: - Compound conditions

    func testCompoundAllRequiresEveryCondition() {
        let trigger = MenuBarItemTrigger(
            condition: .onBatteryPower,
            additionalConditions: [.batteryBelow(percentage: 30)],
            combinator: .all
        )
        // On battery AND below 30%.
        XCTAssertTrue(trigger.shouldReveal(state: state(battery: 20, onAC: false)))
        // On battery but not below 30%.
        XCTAssertFalse(trigger.shouldReveal(state: state(battery: 80, onAC: false)))
        // Below 30% but on AC.
        XCTAssertFalse(trigger.shouldReveal(state: state(battery: 20, onAC: true)))
    }

    func testCompoundAnyRequiresOneCondition() {
        let trigger = MenuBarItemTrigger(
            condition: .vpnActive,
            additionalConditions: [.wifiSSID(name: "Home")],
            combinator: .any
        )
        XCTAssertTrue(trigger.shouldReveal(state: state(vpn: true)))
        XCTAssertTrue(trigger.shouldReveal(state: state(vpn: false, ssid: "Home")))
        XCTAssertFalse(trigger.shouldReveal(state: state(vpn: false, ssid: "Office")))
    }

    func testCompoundWithInvert() {
        let trigger = MenuBarItemTrigger(
            condition: .onACPower,
            additionalConditions: [.charging],
            combinator: .all,
            invert: true
        )
        // AC and charging -> satisfied -> inverted hides (shouldReveal false).
        XCTAssertFalse(trigger.shouldReveal(state: state(onAC: true, charging: true)))
        XCTAssertTrue(trigger.shouldReveal(state: state(onAC: true, charging: false)))
    }

    func testCompoundCodableRoundTrip() throws {
        let trigger = MenuBarItemTrigger(
            condition: .onBatteryPower,
            additionalConditions: [.batteryBelow(percentage: 25), .thermalPressure(atLeast: .serious)],
            combinator: .any
        )
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        XCTAssertEqual(decoded, trigger)
    }

    // MARK: - Multiple target items

    func testAllItemIdentifiersIncludesPrimaryAndAdditional() {
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "a",
            additionalItems: [TriggerTargetItem(identifier: "b", displayName: "B"), TriggerTargetItem(identifier: "", displayName: "")]
        )
        // Primary first, empties filtered out.
        XCTAssertEqual(trigger.allItemIdentifiers, ["a", "b"])
    }

    func testMultiItemCodableRoundTrip() throws {
        let trigger = MenuBarItemTrigger(
            itemIdentifier: "a",
            additionalItems: [TriggerTargetItem(identifier: "b", displayName: "B")],
            notifyOnReveal: true,
            settleSecondsOverride: 4
        )
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        XCTAssertEqual(decoded, trigger)
    }

    // MARK: - Invert

    func testInvertFlipsReveal() {
        var trigger = MenuBarItemTrigger(condition: .onACPower)
        let onAC = state(onAC: true)
        XCTAssertTrue(trigger.shouldReveal(state: onAC))
        trigger.invert = true
        XCTAssertFalse(trigger.shouldReveal(state: onAC))
    }

    // MARK: - Trigger model

    func testDisplayNameFallsBackToAutoTitle() {
        let trigger = MenuBarItemTrigger(
            name: "   ",
            itemDisplayName: "Battery",
            condition: .batteryBelow(percentage: 20)
        )
        XCTAssertEqual(trigger.displayName, "Battery: Battery is below 20%")
    }

    func testCustomNameOverridesAutoTitle() {
        let trigger = MenuBarItemTrigger(
            name: "Low battery",
            itemDisplayName: "Battery",
            condition: .batteryBelow(percentage: 20)
        )
        XCTAssertEqual(trigger.displayName, "Low battery")
    }

    func testAutoTitleWithoutItemName() {
        let trigger = MenuBarItemTrigger(itemDisplayName: "", condition: .onACPower)
        XCTAssertEqual(trigger.autoTitle, "Connected to power")
    }

    @MainActor
    func testRepairsPersistedBatteryItemTestFixtureIdentifier() {
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

        XCTAssertEqual(repaired[0].itemIdentifier, "com.apple.controlcenter:Battery")
        XCTAssertEqual(repaired[0].itemDisplayName, "Battery")
        XCTAssertEqual(repaired[0].itemBaseIdentifier, "com.apple.controlcenter:Battery")
        XCTAssertEqual(repaired[0].additionalItems[0], TriggerTargetItem(
            identifier: "com.apple.controlcenter:Battery",
            displayName: "Battery",
            baseIdentifier: "com.apple.controlcenter:Battery"
        ))
        XCTAssertEqual(repaired[0].additionalItems[1], TriggerTargetItem(
            identifier: "com.example:Other",
            displayName: "Other",
            baseIdentifier: "com.example:Other"
        ))
    }

    @MainActor
    func testRepairsLegacyBatteryTargetSoItFollowsAnInstanceChange() {
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

        XCTAssertEqual(repaired.itemBaseIdentifier, "com.apple.controlcenter:Battery")
        XCTAssertEqual(
            plan.actions[repaired.id],
            MenuBarItemTriggersManager.TriggerPriorityAction(
                reveal: true,
                identifiers: ["com.apple.controlcenter:Battery:1"]
            )
        )
        XCTAssertFalse(plan.unavailableTriggerIDs.contains(repaired.id))
    }

    @MainActor
    func testDoesNotAddABaseToLegacyNumericTitle() {
        let legacy = MenuBarItemTrigger(
            itemIdentifier: "com.example.app:Meeting:30",
            itemDisplayName: "Meeting 30"
        )

        let repaired = MenuBarItemTriggersManager.repairingLegacyTestFixtureIdentifiers(in: [legacy])[0]

        XCTAssertNil(repaired.itemBaseIdentifier)
    }

    func testCodableRoundTrip() throws {
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
        XCTAssertEqual(decoded, trigger)
    }

    func testDecodingWithoutInvertDefaultsFalse() throws {
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
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            name: "Legacy",
            itemIdentifier: "x",
            itemDisplayName: "X",
            condition: .onACPower
        )
        let decoded = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        XCTAssertEqual(decoded, expected)
        XCTAssertFalse(decoded.invert)
    }
}
