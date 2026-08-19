//
//  MenuBarItemTriggerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class MenuBarItemTriggerTests: XCTestCase {
    // MARK: - Helpers

    @MainActor
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
        on.isLowPowerMode = true
        XCTAssertTrue(TriggerCondition.lowPowerMode.isSatisfied(state: on))
        XCTAssertFalse(TriggerCondition.lowPowerMode.isSatisfied(state: state()))
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

    @MainActor
    func testPriorityPlanKeepsControlCenterBatteryVisibleWhenConditionClears() {
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
        XCTAssertNil(hiddenPlan.actions[trigger.id])
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
