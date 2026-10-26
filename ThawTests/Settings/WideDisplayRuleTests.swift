//
//  WideDisplayRuleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("Wide display rule", .serialized)
@MainActor
struct WideDisplayRuleTests {
    @Test("A display at least as wide as the minimum shows every item")
    func wideDisplayShowsEverything() {
        #expect(WideDisplayRule.applies(isEnabled: true, screenWidth: 2560, minimumWidth: 2560))
        #expect(WideDisplayRule.applies(isEnabled: true, screenWidth: 3008, minimumWidth: 2560))
    }

    @Test("A narrower display, an unknown display or a switched-off rule shows nothing extra")
    func otherCasesShowNothing() {
        #expect(!WideDisplayRule.applies(isEnabled: true, screenWidth: 1512, minimumWidth: 2560))
        #expect(!WideDisplayRule.applies(isEnabled: true, screenWidth: nil, minimumWidth: 2560))
        #expect(!WideDisplayRule.applies(isEnabled: false, screenWidth: 3008, minimumWidth: 2560))
    }

    @Test("The rule starts off at 2,560 points", .scratchDefaults)
    func defaults() throws {
        let rule = WideDisplayRule()
        #expect(!rule.isEnabled)
        #expect(rule.minimumWidth == 2560)
    }

    @Test("Changes are saved and read back", .scratchDefaults)
    func persists() throws {
        let rule = WideDisplayRule()
        rule.isEnabled = true
        rule.minimumWidth = 3200
        let reloaded = WideDisplayRule()
        #expect(reloaded.isEnabled)
        #expect(reloaded.minimumWidth == 3200)
    }

    @Test("The rule asks for the width of the display it is given", .scratchDefaults)
    func readsTheDisplayWidth() throws {
        let rule = WideDisplayRule(screenWidth: { $0 == 2 ? 3008 : 1512 })
        rule.isEnabled = true
        #expect(rule.showsEveryItem(on: 2))
        #expect(!rule.showsEveryItem(on: 1))
    }

    @Test("The rule counts as always showing hidden items, on any display it covers", .scratchDefaults)
    func displaySettingsFollowTheRule() throws {
        let manager = DisplaySettingsManager()
        #expect(!manager.isAlwaysShowEnabledOnAnyDisplay)
        manager.wideDisplayRule.isEnabled = true
        #expect(manager.isAlwaysShowEnabledOnAnyDisplay)
        let displayID = CGMainDisplayID()
        #expect(manager.alwaysShowHiddenItems(for: displayID) == manager.wideDisplayRule.showsEveryItem(on: displayID))
    }

    @Test("Resetting the display settings turns the rule off at its default width", .scratchDefaults)
    func resetTurnsTheRuleOff() throws {
        let settings = AppSettings()
        settings.displaySettings.wideDisplayRule.isEnabled = true
        settings.displaySettings.wideDisplayRule.minimumWidth = 3200
        settings.advanced.skippedModuleStandIns = ["airdrop"]
        settings.resetDisplay()
        settings.resetAdvanced()
        #expect(!settings.displaySettings.wideDisplayRule.isEnabled)
        #expect(settings.displaySettings.wideDisplayRule.minimumWidth == 2560)
        #expect(settings.advanced.skippedModuleStandIns == Set(Defaults.DefaultValue.skippedModuleStandIns))
    }
}

@Suite("Active menu bar display watcher")
@MainActor
struct ActiveMenuBarDisplayWatcherTests {
    @MainActor
    final class Probe {
        var displayID: CGDirectDisplayID? = 1
        var changes = 0
    }

    @Test("A move of the active menu bar to another display is reported once")
    func reportsAMove() {
        let probe = Probe()
        let watcher = ActiveMenuBarDisplayWatcher(readDisplayID: { probe.displayID })
        watcher.onChange = { probe.changes += 1 }
        watcher.check()
        #expect(probe.changes == 0)

        probe.displayID = 2
        watcher.check()
        watcher.check()
        #expect(probe.changes == 1)
    }

    @Test("Losing track of the active display is not a move")
    func ignoresUnknown() {
        let probe = Probe()
        let watcher = ActiveMenuBarDisplayWatcher(readDisplayID: { probe.displayID })
        watcher.onChange = { probe.changes += 1 }
        watcher.check()
        probe.displayID = nil
        watcher.check()
        probe.displayID = 1
        watcher.check()
        #expect(probe.changes == 0)
    }

    @Test("A throttled check reads again only after the throttle interval; a plain one always reads")
    func throttledChecks() {
        let probe = Probe()
        var reads = 0
        let watcher = ActiveMenuBarDisplayWatcher(readDisplayID: { reads += 1; return probe.displayID })
        watcher.onChange = { probe.changes += 1 }
        let start = ContinuousClock.now
        watcher.check(throttled: true, now: start)
        probe.displayID = 2
        watcher.check(throttled: true, now: start + .milliseconds(50))
        #expect(reads == 1)
        #expect(probe.changes == 0, "Too soon to read again")

        watcher.check(throttled: true, now: start + .milliseconds(150))
        #expect(reads == 2)
        #expect(probe.changes == 1)

        watcher.check(now: start + .milliseconds(160))
        #expect(reads == 3, "A click always reads")
    }
}
