//
//  TriggerConditionSurfaceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the value surface of ``TriggerCondition`` and the enums the trigger
/// editor drives it with: the per-kind lookup tables, the accessors that pull
/// a carried value back out of a case, and the `with…` copies the editor uses
/// to edit one field without disturbing the rest.
///
/// Deliberately exhaustive over `allCases` rather than spot-checked. Every one
/// of these tables is a `switch` the compiler forces to stay complete, so the
/// failure mode worth catching is a new case wired to the wrong arm — which
/// only a pass over the whole set finds.
@Suite("Trigger condition surface")
@MainActor
struct TriggerConditionSurfaceTests {
    // MARK: - Kind tables

    @Test("Every kind has an id, a display string and a default condition")
    func everyKindIsFullyDescribed() {
        for kind in TriggerConditionKind.allCases {
            #expect(kind.id == kind.rawValue)
            #expect(!kind.displayString.isEmpty)
            #expect(TriggerCondition.defaultCondition(for: kind).kind == kind)
        }
    }

    @Test("Only the two battery thresholds use a percentage")
    func percentageKinds() {
        let usingPercentage = TriggerConditionKind.allCases.filter(\.usesPercentage)
        #expect(usingPercentage == [.batteryBelow, .batteryAtOrAbove])
    }

    @Test("Jittery sources settle for longer than discrete ones")
    func settleIntervals() {
        #expect(TriggerConditionKind.batteryBelow.settleInterval == .seconds(6))
        #expect(TriggerConditionKind.batteryAtOrAbove.settleInterval == .seconds(6))
        #expect(TriggerConditionKind.frontmostApp.settleInterval == .milliseconds(1500))
        #expect(TriggerConditionKind.appRunning.settleInterval == .milliseconds(500))
        #expect(TriggerConditionKind.scriptResult.settleInterval == .seconds(2))
        #expect(TriggerConditionKind.imageChanged.settleInterval == .seconds(2))
        // Everything else shares the one-second default.
        #expect(TriggerConditionKind.charging.settleInterval == .seconds(1))
        #expect(TriggerConditionKind.nearLocation.settleInterval == .seconds(1))

        for kind in TriggerConditionKind.allCases {
            #expect(kind.settleInterval >= .milliseconds(500))
        }
    }

    @Test("Only the power conditions are available without a feature flag")
    func alwaysAvailableKinds() {
        let alwaysAvailable = TriggerConditionKind.allCases.filter { $0.requiredFeature == nil }
        #expect(Set(alwaysAvailable) == [
            .batteryBelow, .batteryAtOrAbove, .onACPower, .onBatteryPower, .charging,
        ])
    }

    @Test("Value-less kinds are the ones with no editor")
    func editorlessKinds() {
        let editorless = TriggerConditionKind.allCases.filter { $0.editor == .none }
        #expect(Set(editorless) == [
            .onACPower, .onBatteryPower, .charging, .networkConnected, .vpnActive,
            .externalDisplay, .focusActive, .cameraInUse, .microphoneInUse,
        ])
    }

    @Test("Text kinds each carry their own prompt")
    func textEditorPrompts() {
        let prompts = TriggerConditionKind.allCases.compactMap { kind -> String? in
            guard case let .text(prompt) = kind.editor else { return nil }
            return prompt
        }
        // Three text kinds, and no two share a prompt — a copy-paste slip in
        // that table is otherwise invisible.
        #expect(prompts.count == 3)
        #expect(Set(prompts).count == 3)
        #expect(prompts.allSatisfy { !$0.isEmpty })
    }

    // MARK: - Summaries

    @Test("Every kind's default condition summarizes to something readable")
    func everyDefaultConditionHasASummary() {
        for kind in TriggerConditionKind.allCases {
            let summary = TriggerCondition.defaultCondition(for: kind).summary
            #expect(!summary.isEmpty, "\(kind.rawValue) has no summary")
        }
    }

    @Test("Summaries name the value a condition carries")
    func summariesIncludeCarriedValues() {
        #expect(TriggerCondition.batteryBelow(percentage: 20).summary == "Battery is below 20%")
        #expect(TriggerCondition.batteryAtOrAbove(percentage: 80).summary == "Battery is at or above 80%")
        // Percentages are rounded rather than truncated.
        #expect(TriggerCondition.batteryBelow(percentage: 19.6).summary == "Battery is below 20%")
        #expect(TriggerCondition.wifiSSID(name: "Café").summary.contains("Café"))
        #expect(TriggerCondition.bluetoothConnected(name: "Keyboard").summary.contains("Keyboard"))
        #expect(TriggerCondition.audioOutput(contains: "Studio").summary.contains("Studio"))
        #expect(TriggerCondition.focusMode(name: "Work").summary.contains("Work"))
        #expect(TriggerCondition.nearLocation(
            latitude: 1, longitude: 2, radiusMeters: 250, label: "Home"
        ).summary.contains("Home"))
        #expect(TriggerCondition.thermalPressure(atLeast: .critical).summary.contains("critical"))
    }

    @Test("An empty value summarizes generically instead of leaving a gap")
    func emptyValuesSummarizeGenerically() {
        #expect(TriggerCondition.frontmostApp(bundleID: "").summary == "An app is frontmost")
        #expect(TriggerCondition.appRunning(bundleID: "").summary == "An app is running")
        #expect(TriggerCondition.wifiSSID(name: "").summary == "On a Wi-Fi network")
        #expect(TriggerCondition.bluetoothConnected(name: "").summary == "A Bluetooth device is connected")
        #expect(TriggerCondition.audioOutput(contains: "").summary == "Audio output device")
        #expect(TriggerCondition.focusMode(name: "").summary == "A Focus mode is active")
        #expect(TriggerCondition.nearLocation(
            latitude: 0, longitude: 0, radiusMeters: 150, label: ""
        ).summary.contains("a saved location"))
    }

    @Test("A script summary names the file, not the whole path")
    func scriptSummaryUsesTheFileName() {
        let named = TriggerCondition.scriptResult(path: "/Users/me/bin/check.sh", expectedOutput: "")
        #expect(named.summary == "check.sh exits 0")

        let expecting = TriggerCondition.scriptResult(path: "/Users/me/bin/check.sh", expectedOutput: "ok")
        #expect(expecting.summary.contains("check.sh"))
        #expect(expecting.summary.contains("ok"))

        #expect(TriggerCondition.scriptResult(path: "", expectedOutput: "").summary == "a script exits 0")
    }

    @Test("An image condition says whether a reference has been captured")
    func imageSummaryDistinguishesTheUncapturedCase() {
        let uncaptured = TriggerCondition.imageChanged(itemIdentifier: "item", referenceHash: nil)
        #expect(uncaptured.summary.contains("capture a reference"))

        let captured = TriggerCondition.imageChanged(itemIdentifier: "item", referenceHash: 42)
        #expect(!captured.summary.contains("capture a reference"))
    }

    @Test("The legacy low-power case summarizes as its Energy Mode equivalent")
    func lowPowerModeSummaryMatchesEnergyMode() {
        #expect(TriggerCondition.lowPowerMode.summary == EnergyModeMatch.low.summary)
    }

    @Test("A weekly schedule names its days unless it covers all of them")
    func weeklyScheduleSummary() {
        let everyDay = TriggerCondition.weeklySchedule(
            startMinutes: 9 * 60, endMinutes: 17 * 60, weekdays: ScheduleWeekday.everyDay
        )
        #expect(!everyDay.summary.contains(" on "))

        let weekdaysOnly = TriggerCondition.weeklySchedule(
            startMinutes: 9 * 60,
            endMinutes: 17 * 60,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
        )
        #expect(weekdaysOnly.summary.contains("Mon, Tue, Wed, Thu, Fri"))

        let noDays = TriggerCondition.weeklySchedule(
            startMinutes: 0, endMinutes: 60, weekdays: []
        )
        #expect(noDays.summary.contains("no days"))
    }

    // MARK: - Accessors

    @Test("Each accessor reads only the cases that carry its value")
    func accessorsAreCaseSpecific() {
        #expect(TriggerCondition.batteryBelow(percentage: 15).percentage == 15)
        #expect(TriggerCondition.batteryAtOrAbove(percentage: 85).percentage == 85)
        #expect(TriggerCondition.charging.percentage == nil)

        #expect(TriggerCondition.frontmostApp(bundleID: "com.example").bundleID == "com.example")
        #expect(TriggerCondition.appRunning(bundleID: "com.example").bundleID == "com.example")
        #expect(TriggerCondition.charging.bundleID == nil)

        #expect(TriggerCondition.wifiSSID(name: "Net").text == "Net")
        #expect(TriggerCondition.bluetoothConnected(name: "Mouse").text == "Mouse")
        #expect(TriggerCondition.audioOutput(contains: "Display").text == "Display")
        #expect(TriggerCondition.focusMode(name: "Work").text == "Work")
        #expect(TriggerCondition.charging.text == nil)

        #expect(TriggerCondition.energyMode(.high).energyModeMatch == .high)
        #expect(TriggerCondition.lowPowerMode.energyModeMatch == .low)
        #expect(TriggerCondition.charging.energyModeMatch == nil)

        #expect(TriggerCondition.thermalPressure(atLeast: .fair).thermalLevel == .fair)
        #expect(TriggerCondition.charging.thermalLevel == nil)
    }

    @Test("Schedule accessors read both the daily and the weekly spelling")
    func scheduleAccessors() {
        let daily = TriggerCondition.schedule(startMinutes: 480, endMinutes: 1020)
        #expect(daily.scheduleWindow?.start == 480)
        #expect(daily.scheduleWindow?.end == 1020)
        // A daily window applies every day, so that is what it reports.
        #expect(daily.scheduleWeekdays == ScheduleWeekday.everyDay)

        let weekly = TriggerCondition.weeklySchedule(
            startMinutes: 60, endMinutes: 120, weekdays: [.saturday, .sunday]
        )
        #expect(weekly.scheduleWindow?.start == 60)
        #expect(weekly.scheduleWeekdays == [.saturday, .sunday])

        #expect(TriggerCondition.charging.scheduleWindow == nil)
        #expect(TriggerCondition.charging.scheduleWeekdays == nil)
    }

    @Test("Tuple accessors return every field they carry")
    func tupleAccessors() {
        let location = TriggerCondition.nearLocation(
            latitude: 48.2, longitude: 16.4, radiusMeters: 300, label: "Office"
        )
        #expect(location.locationValue?.latitude == 48.2)
        #expect(location.locationValue?.longitude == 16.4)
        #expect(location.locationValue?.radiusMeters == 300)
        #expect(location.locationValue?.label == "Office")
        #expect(TriggerCondition.charging.locationValue == nil)

        let script = TriggerCondition.scriptResult(path: "/tmp/s.sh", expectedOutput: "yes")
        #expect(script.scriptValue?.path == "/tmp/s.sh")
        #expect(script.scriptValue?.expectedOutput == "yes")
        #expect(TriggerCondition.charging.scriptValue == nil)

        let image = TriggerCondition.imageChanged(itemIdentifier: "item", referenceHash: 7)
        #expect(image.imageValue?.itemIdentifier == "item")
        #expect(image.imageValue?.referenceHash == 7)
        #expect(TriggerCondition.charging.imageValue == nil)
    }

    @Test("Both icon-watching kinds report their watched item")
    func watchedItemIdentifier() {
        #expect(TriggerCondition.imageChanged(
            itemIdentifier: "watched", referenceHash: nil
        ).watchedItemIdentifier == "watched")
        #expect(TriggerCondition.itemSeekingAttention(
            itemIdentifier: "watched"
        ).watchedItemIdentifier == "watched")
        #expect(TriggerCondition.charging.watchedItemIdentifier == nil)
    }

    // MARK: - Editing copies

    @Test("Each with-copy edits only the cases it applies to")
    func withCopiesAreCaseSpecific() {
        #expect(TriggerCondition.batteryBelow(percentage: 20).withPercentage(35).percentage == 35)
        #expect(TriggerCondition.batteryAtOrAbove(percentage: 80).withPercentage(35).percentage == 35)
        #expect(TriggerCondition.charging.withPercentage(35) == .charging)

        #expect(TriggerCondition.frontmostApp(bundleID: "a").withBundleID("b").bundleID == "b")
        #expect(TriggerCondition.appRunning(bundleID: "a").withBundleID("b").bundleID == "b")
        #expect(TriggerCondition.charging.withBundleID("b") == .charging)

        #expect(TriggerCondition.wifiSSID(name: "a").withText("b").text == "b")
        #expect(TriggerCondition.bluetoothConnected(name: "a").withText("b").text == "b")
        #expect(TriggerCondition.audioOutput(contains: "a").withText("b").text == "b")
        #expect(TriggerCondition.focusMode(name: "a").withText("b").text == "b")
        #expect(TriggerCondition.charging.withText("b") == .charging)

        #expect(TriggerCondition.energyMode(.low).withEnergyMode(.high).energyModeMatch == .high)
        #expect(TriggerCondition.lowPowerMode.withEnergyMode(.notLow).energyModeMatch == .notLow)
        #expect(TriggerCondition.charging.withEnergyMode(.high) == .charging)

        #expect(TriggerCondition.thermalPressure(atLeast: .fair)
            .withThermalLevel(.critical).thermalLevel == .critical)
        #expect(TriggerCondition.charging.withThermalLevel(.critical) == .charging)
    }

    @Test("Editing a schedule window keeps the selected weekdays")
    func withScheduleKeepsWeekdays() {
        // A daily window has no weekday selection to keep, so it normalizes
        // to every day rather than inventing one.
        let fromDaily = TriggerCondition.schedule(startMinutes: 0, endMinutes: 60)
            .withSchedule(start: 300, end: 400)
        #expect(fromDaily.scheduleWindow?.start == 300)
        #expect(fromDaily.scheduleWeekdays == ScheduleWeekday.everyDay)

        let fromWeekly = TriggerCondition.weeklySchedule(
            startMinutes: 0, endMinutes: 60, weekdays: [.monday]
        ).withSchedule(start: 300, end: 400)
        #expect(fromWeekly.scheduleWindow?.end == 400)
        #expect(fromWeekly.scheduleWeekdays == [.monday])

        #expect(TriggerCondition.charging.withSchedule(start: 1, end: 2) == .charging)
    }

    @Test("Editing the weekdays keeps the window, from either spelling")
    func withScheduleWeekdaysKeepsTheWindow() {
        let fromDaily = TriggerCondition.schedule(startMinutes: 540, endMinutes: 1020)
            .withScheduleWeekdays([.friday])
        #expect(fromDaily.scheduleWindow?.start == 540)
        #expect(fromDaily.scheduleWindow?.end == 1020)
        #expect(fromDaily.scheduleWeekdays == [.friday])

        let fromWeekly = TriggerCondition.weeklySchedule(
            startMinutes: 540, endMinutes: 1020, weekdays: [.monday]
        ).withScheduleWeekdays([.sunday])
        #expect(fromWeekly.scheduleWindow?.start == 540)
        #expect(fromWeekly.scheduleWeekdays == [.sunday])

        #expect(TriggerCondition.charging.withScheduleWeekdays([.monday]) == .charging)
    }

    @Test("Script edits replace one field and leave the other alone")
    func scriptEdits() {
        let base = TriggerCondition.scriptResult(path: "/tmp/a.sh", expectedOutput: "ok")

        let repathed = base.withScriptPath("/tmp/b.sh")
        #expect(repathed.scriptValue?.path == "/tmp/b.sh")
        #expect(repathed.scriptValue?.expectedOutput == "ok")

        let reworded = base.withScriptExpectedOutput("done")
        #expect(reworded.scriptValue?.path == "/tmp/a.sh")
        #expect(reworded.scriptValue?.expectedOutput == "done")

        #expect(TriggerCondition.charging.withScriptPath("/tmp/b.sh") == .charging)
        #expect(TriggerCondition.charging.withScriptExpectedOutput("done") == .charging)
    }

    @Test("Rewatching an item clears the reference hash it no longer matches")
    func imageEdits() {
        let base = TriggerCondition.imageChanged(itemIdentifier: "old", referenceHash: 99)

        let rewatched = base.withImageItem("new")
        #expect(rewatched.imageValue?.itemIdentifier == "new")
        #expect(rewatched.imageValue?.referenceHash == nil)

        let recaptured = base.withImageReferenceHash(123)
        #expect(recaptured.imageValue?.itemIdentifier == "old")
        #expect(recaptured.imageValue?.referenceHash == 123)

        #expect(TriggerCondition.charging.withImageItem("new") == .charging)
        #expect(TriggerCondition.charging.withImageReferenceHash(1) == .charging)
    }

    @Test("A location edit replaces only the fields it is given")
    func locationEdits() {
        let base = TriggerCondition.nearLocation(
            latitude: 1, longitude: 2, radiusMeters: 100, label: "Home"
        )

        let moved = base.withLocation(latitude: 10, longitude: 20)
        #expect(moved.locationValue?.latitude == 10)
        #expect(moved.locationValue?.longitude == 20)
        #expect(moved.locationValue?.radiusMeters == 100)
        #expect(moved.locationValue?.label == "Home")

        let widened = base.withLocation(radiusMeters: 500)
        #expect(widened.locationValue?.radiusMeters == 500)
        #expect(widened.locationValue?.latitude == 1)

        let renamed = base.withLocation(label: "Office")
        #expect(renamed.locationValue?.label == "Office")
        #expect(renamed.locationValue?.radiusMeters == 100)

        #expect(base.withLocation() == base)
        #expect(TriggerCondition.charging.withLocation(latitude: 5) == .charging)
    }

    // MARK: - Kind conversion

    @Test("Converting to any kind produces a condition of that kind")
    func conversionAlwaysLandsOnTheRequestedKind() {
        for from in TriggerConditionKind.allCases {
            let old = TriggerCondition.defaultCondition(for: from)
            for to in TriggerConditionKind.allCases {
                let converted = TriggerCondition.make(kind: to, preserving: old)
                #expect(converted.kind == to, "\(from.rawValue) -> \(to.rawValue)")
            }
        }
    }

    @Test("Conversion carries a compatible value across")
    func conversionPreservesCompatibleValues() {
        let below = TriggerCondition.batteryBelow(percentage: 42)
        #expect(TriggerCondition.make(kind: .batteryAtOrAbove, preserving: below).percentage == 42)

        let frontmost = TriggerCondition.frontmostApp(bundleID: "com.example")
        #expect(TriggerCondition.make(kind: .appRunning, preserving: frontmost).bundleID == "com.example")

        let ssid = TriggerCondition.wifiSSID(name: "Net")
        #expect(TriggerCondition.make(kind: .audioOutput, preserving: ssid).text == "Net")
        #expect(TriggerCondition.make(kind: .focusModeNamed, preserving: ssid).text == "Net")
        #expect(TriggerCondition.make(kind: .bluetoothConnected, preserving: ssid).text == "Net")

        let weekly = TriggerCondition.weeklySchedule(
            startMinutes: 300, endMinutes: 400, weekdays: [.monday]
        )
        let reschedule = TriggerCondition.make(kind: .schedule, preserving: weekly)
        #expect(reschedule.scheduleWindow?.start == 300)
        #expect(reschedule.scheduleWeekdays == [.monday])

        let energy = TriggerCondition.energyMode(.high)
        #expect(TriggerCondition.make(kind: .energyMode, preserving: energy).energyModeMatch == .high)

        let thermal = TriggerCondition.thermalPressure(atLeast: .critical)
        #expect(TriggerCondition.make(kind: .thermalPressure, preserving: thermal).thermalLevel == .critical)

        let script = TriggerCondition.scriptResult(path: "/tmp/a.sh", expectedOutput: "ok")
        let rescripted = TriggerCondition.make(kind: .scriptResult, preserving: script)
        #expect(rescripted.scriptValue?.path == "/tmp/a.sh")
        #expect(rescripted.scriptValue?.expectedOutput == "ok")
    }

    @Test("Switching between the two icon-watching kinds keeps the item")
    func conversionPreservesTheWatchedItem() {
        let watching = TriggerCondition.imageChanged(itemIdentifier: "item", referenceHash: 5)
        let seeking = TriggerCondition.make(kind: .itemSeekingAttention, preserving: watching)
        #expect(seeking == .itemSeekingAttention(itemIdentifier: "item"))

        let back = TriggerCondition.make(kind: .imageChanged, preserving: seeking)
        #expect(back.imageValue?.itemIdentifier == "item")
        // The reference hash belongs to the captured image, not the item, so
        // it does not survive the round trip.
        #expect(back.imageValue?.referenceHash == nil)
    }

    @Test("Converting from an incompatible kind falls back to the default")
    func conversionFallsBackToTheDefault() {
        for to in TriggerConditionKind.allCases {
            let converted = TriggerCondition.make(kind: to, preserving: .charging)
            #expect(converted == TriggerCondition.defaultCondition(for: to), "\(to.rawValue)")
        }
    }

    @Test("Rewatching the attention item applies only to that kind")
    func attentionItemEdit() {
        #expect(TriggerCondition.itemSeekingAttention(itemIdentifier: "old")
            .withAttentionItem("new") == .itemSeekingAttention(itemIdentifier: "new"))
        #expect(TriggerCondition.charging.withAttentionItem("new") == .charging)
        #expect(TriggerCondition.imageChanged(itemIdentifier: "old", referenceHash: nil)
            .withAttentionItem("new").watchedItemIdentifier == "old")
    }
}

/// Covers the small display enums the trigger editor renders: the weekday
/// list, the thermal and Energy Mode pickers, and the combinator that joins a
/// trigger's conditions into one sentence.
@Suite("Trigger display enums")
@MainActor
struct TriggerDisplayEnumTests {
    @Test("Weekdays match Calendar's numbering and wrap backwards")
    func weekdayNumbering() {
        #expect(ScheduleWeekday.sunday.rawValue == 1)
        #expect(ScheduleWeekday.saturday.rawValue == 7)
        #expect(ScheduleWeekday.everyDay == Set(ScheduleWeekday.allCases))

        for day in ScheduleWeekday.allCases {
            #expect(day.id == day.rawValue)
            #expect(day.shortTitle.count == 3)
        }
        #expect(Set(ScheduleWeekday.allCases.map(\.shortTitle)).count == 7)

        // Sunday wraps to the far end of the week rather than falling off it.
        #expect(ScheduleWeekday.sunday.previous == .saturday)
        #expect(ScheduleWeekday.monday.previous == .sunday)
        #expect(ScheduleWeekday.saturday.previous == .friday)
    }

    @Test("Thermal levels are ordered and each reads distinctly")
    func thermalLevels() {
        #expect(ThermalLevel.fair.rawValue < ThermalLevel.serious.rawValue)
        #expect(ThermalLevel.serious.rawValue < ThermalLevel.critical.rawValue)

        for level in ThermalLevel.allCases {
            #expect(level.id == level.rawValue)
            #expect(!level.displayString.isEmpty)
        }
        #expect(Set(ThermalLevel.allCases.map(\.displayString)).count == 3)
    }

    @Test("Energy Mode predicates match the modes they name")
    func energyModeMatching() {
        #expect(EnergyModeMatch.low.matches(.low))
        #expect(!EnergyModeMatch.low.matches(.automatic))
        #expect(!EnergyModeMatch.low.matches(.high))

        // notLow is the widening case: it covers both remaining modes.
        #expect(!EnergyModeMatch.notLow.matches(.low))
        #expect(EnergyModeMatch.notLow.matches(.automatic))
        #expect(EnergyModeMatch.notLow.matches(.high))

        #expect(EnergyModeMatch.automatic.matches(.automatic))
        #expect(!EnergyModeMatch.automatic.matches(.high))

        #expect(EnergyModeMatch.high.matches(.high))
        #expect(!EnergyModeMatch.high.matches(.automatic))
    }

    @Test("Every Energy Mode predicate reads distinctly in both registers")
    func energyModeStrings() {
        for match in EnergyModeMatch.allCases {
            #expect(match.id == match.rawValue)
            #expect(!match.displayString.isEmpty)
            #expect(!match.summary.isEmpty)
        }
        #expect(Set(EnergyModeMatch.allCases.map(\.displayString)).count == 4)
        #expect(Set(EnergyModeMatch.allCases.map(\.summary)).count == 4)
    }

    @Test("High Power is offered only where the hardware has it")
    func selectableEnergyModes() {
        #expect(EnergyModeMatch.selectableCases(highPowerModeSupported: true) == EnergyModeMatch.allCases)

        let restricted = EnergyModeMatch.selectableCases(highPowerModeSupported: false)
        #expect(!restricted.contains(.high))
        #expect(restricted == [.low, .notLow, .automatic])
    }

    @Test("Energy modes carry their own display strings")
    func energyModeDisplayStrings() {
        for mode in EnergyMode.allCases {
            #expect(mode.id == mode.rawValue)
            #expect(!mode.displayString.isEmpty)
        }
        #expect(Set(EnergyMode.allCases.map(\.displayString)).count == EnergyMode.allCases.count)
    }

    @Test("The none-of combinator keeps its legacy raw value")
    func combinatorRawValues() {
        // Renaming the case must not rewrite what is already on disk.
        #expect(TriggerCombinator.noneOf.rawValue == "none")
        #expect(TriggerCombinator(rawValue: "none") == .noneOf)
        #expect(TriggerCombinator.all.rawValue == "all")
        #expect(TriggerCombinator.any.rawValue == "any")
    }

    @Test("Each combinator joins and prefixes its own way")
    func combinatorPhrasing() {
        for combinator in TriggerCombinator.allCases {
            #expect(combinator.id == combinator.rawValue)
            #expect(!combinator.displayString.isEmpty)
            #expect(!combinator.joiner.isEmpty)
        }

        #expect(TriggerCombinator.all.joiner == " and ")
        #expect(TriggerCombinator.any.joiner == " or ")
        // "None of" reads as a disjunction being negated, so it joins with
        // "or" and carries the negation in the prefix instead.
        #expect(TriggerCombinator.noneOf.joiner == " or ")
        #expect(TriggerCombinator.all.summaryPrefix.isEmpty)
        #expect(TriggerCombinator.any.summaryPrefix.isEmpty)
        #expect(!TriggerCombinator.noneOf.summaryPrefix.isEmpty)
    }
}
