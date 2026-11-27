//
//  SystemExtraTakeoverCoordinatorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import os
import PlatformRuntimeKit
import Testing
@testable import Thaw

/// The coordinator driven through in-memory sections, switches and stand-ins.
@MainActor
final class TakeoverRig {
    let fake = FakeStandInSystem()
    let sections = FakeStandInSections()
    let journal = MemoryExtraJournal()
    let settings = LayoutSettings()
    let switches = Dictionary(uniqueKeysWithValues: SystemExtraItem.allCases.map { ($0, FakeNativeSwitch(item: $0)) })
    let launcher: SystemExtraStandInLauncher
    var shownInControlCenter: Set<String> = []
    private(set) var known: [String] = []
    private(set) lazy var coordinator = SystemExtraTakeoverCoordinator(
        journal: journal,
        adapters: switches.mapValues { $0 },
        launcher: launcher,
        isShownInMenuBar: { [unowned self] in shownInControlCenter.contains($0) }
    )

    init() {
        launcher = SystemExtraStandInLauncher(system: fake.system)
    }

    func start() {
        coordinator.start(controller: sections, settings: settings) { [unowned self] in known.append($0) }
    }

    /// Lets the engine and the stand-in launches it started finish.
    func drain() async {
        await coordinator.engine.awaitPendingOperations()
        try? await Task.sleep(for: .milliseconds(30))
        await coordinator.engine.awaitPendingOperations()
    }

    static func standInID(_ standIn: SystemExtraStandIn) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(standIn.itemIdentifier)
    }

    /// The module's original as Control Center reports it, before canonicalising.
    static func moduleTag(_ title: String) -> String {
        MenuBarItemTag(namespace: .menuBarAgent, title: title).tagIdentifier
    }

    static func moduleID(_ title: String) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(moduleTag(title))
    }

    static let focus = "com.apple.menuextra.focusmode"
    static let airDrop = "com.apple.menuextra.airdrop"
    static let wiFi = "com.apple.menuextra.wifi"
}

@MainActor
@Suite("System extra takeover coordinator", .serialized, .scratchDefaults)
struct SystemExtraTakeoverCoordinatorTests {
    @Test("With every switch off nothing is hidden, journaled, launched or moved")
    func allOffDoesNothing() async {
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = false

        rig.start()
        await rig.drain()

        #expect(rig.fake.opens.isEmpty)
        let switchWrites = rig.switches.values.flatMap(\.writes)
        #expect(switchWrites.isEmpty)
        #expect(rig.journal.entries.isEmpty)
        #expect(rig.sections.writes.isEmpty)
    }

    @Test("A takeover on at start hides the original, journals it and puts the stand-in in its slot")
    func enabledAtStartTakesOver() async {
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = false
        rig.settings.enableTimeMachineTakeover = true
        let original = SystemExtraItem.timeMachine.canonicalIdentifier
        rig.sections.sectionItemOrder[.visible] = ["x", original]

        rig.start()
        await rig.drain()

        let standIn = TakeoverRig.standInID(.timeMachine)
        #expect((rig.switches[.timeMachine]?.hides ?? 0) > 0)
        #expect(rig.journal.entries[SystemExtraItem.timeMachine.rawValue] == .value(1))
        #expect(rig.fake.opened(.timeMachine) == 1)
        #expect(rig.fake.opens.count == 1)
        #expect(rig.known == [standIn])
        #expect(rig.sections.writes == [.order(["x", original, standIn], .visible)])
        #expect(rig.coordinator.status(for: .timeMachine).phase == .active)
    }

    @Test("A stand-in with a section of its own is launched there")
    func assignedStandInKeepsSection() async {
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = false
        rig.settings.enableTimeMachineTakeover = true
        rig.sections.sectionAssignment[TakeoverRig.standInID(.timeMachine)] = .alwaysHidden

        rig.start()
        await rig.drain()

        #expect(rig.fake.opened(.timeMachine) == 1)
        #expect(rig.sections.writes.isEmpty)
        #expect(rig.sections.sectionAssignment[TakeoverRig.standInID(.timeMachine)] == .alwaysHidden)
    }

    @Test("Each takeover switch launches its own stand-in only", arguments: SystemExtraItem.allCases)
    func eachSwitchLaunchesItsOwn(item: SystemExtraItem) async {
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = false
        switch item {
        case .timeMachine: rig.settings.enableTimeMachineTakeover = true
        case .timer: rig.settings.enableTimerTakeover = true
        case .textInput: rig.settings.enableTextInputTakeover = true
        }

        rig.start()
        await rig.drain()

        for other in SystemExtraItem.allCases {
            #expect(rig.fake.opened(SystemExtraStandIn(other)) == (other == item ? 1 : 0))
            #expect(((rig.switches[other]?.hides ?? 0) > 0) == (other == item))
        }
    }

    @Test("A takeover switched on after start takes over, and switched off gives the original back")
    func switchingLaterFollowsSettings() async throws {
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = false
        rig.start()
        await rig.drain()
        #expect(rig.fake.opens.isEmpty)

        rig.settings.enableTextInputTakeover = true
        await settle { rig.fake.startedProcesses.count == 1 }
        await rig.drain()
        let process = try #require(rig.fake.startedProcesses.only)
        #expect((rig.switches[.textInput]?.hides ?? 0) > 0)

        rig.settings.enableTextInputTakeover = false
        await settle { process.terminateCalls > 0 }
        await rig.drain()

        #expect(process.terminateCalls == 1)
        #expect(rig.switches[.textInput]?.writes.last == .value(1))
        #expect(rig.journal.entries.isEmpty)
        #expect(rig.coordinator.status(for: .textInput) == .off)
    }

    @Test("Shutting down restores originals, quits stand-ins and stops following settings")
    func terminationRestoresAndStops() async throws {
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = false
        rig.settings.enableTimeMachineTakeover = true
        rig.start()
        await rig.drain()
        let process = try #require(rig.fake.startedProcesses.only)

        rig.coordinator.prepareForTermination()
        await rig.drain()
        #expect(process.terminateCalls == 1)
        #expect(rig.switches[.timeMachine]?.writes.last == .value(1))
        #expect(rig.journal.entries.isEmpty)

        // The engine refuses work after shutdown, so a module stand-in is what shows the watches stopped.
        rig.sections.sectionAssignment[TakeoverRig.moduleID(TakeoverRig.focus)] = .hidden
        rig.settings.enableModuleStandIns = true
        rig.sections.announce()
        await rig.drain()
        #expect(rig.fake.opened(.focus) == 0)
    }

    @Test("An item with no Control Center module never reads as shown")
    func unknownModuleIsNotShown() {
        #expect(!SystemExtraTakeoverCoordinator.isShownInMenuBar("com.example.thaw.tests:Nothing"))
    }

    @Test("An original journaled by an earlier session is put back on recovery")
    func recoveryRestoresJournaledOriginal() async {
        let rig = TakeoverRig()
        rig.journal.entries = [SystemExtraItem.timeMachine.rawValue: .value(1)]
        rig.switches[.timeMachine]?.value = .value(0)

        rig.coordinator.recoverPreviousSession()
        await rig.drain()

        #expect(rig.switches[.timeMachine]?.writes == [.value(1)])
        #expect(rig.journal.entries.isEmpty)
        #expect(!rig.coordinator.status(for: .timeMachine).recoveryPending)
    }
}

@MainActor
@Suite("Control Center module stand-ins", .serialized, .scratchDefaults)
struct ModuleStandInCoordinatorTests {
    private func rig(enabled: Bool = true) -> TakeoverRig {
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = enabled
        rig.settings.skippedModuleStandIns = []
        return rig
    }

    @Test("A module whose original is in Hidden gets a stand-in there; modules left visible and off get none")
    func hiddenOriginalGetsStandIn() async {
        let rig = rig()
        rig.sections.sectionAssignment[TakeoverRig.moduleID(TakeoverRig.focus)] = .hidden

        rig.start()
        await settle { rig.fake.opens.count == 1 }
        await rig.drain()

        #expect(rig.fake.opened(.focus) == 1)
        #expect(rig.fake.opens.count == 1)
        #expect(rig.sections.writes == [.section(.hidden, TakeoverRig.standInID(.focus))])
        #expect(rig.launcher.placed == [.focus])
    }

    @Test("A module shown by Control Center in Visible gets a stand-in, and its original is moved to Hidden")
    func shownModuleHandsOverOriginal() async {
        let rig = rig()
        rig.shownInControlCenter = [TakeoverRig.moduleTag(TakeoverRig.airDrop)]
        let original = TakeoverRig.moduleID(TakeoverRig.airDrop)

        rig.start()
        await settle { rig.sections.sectionAssignment[original] == .hidden }
        await rig.drain()

        #expect(rig.fake.opened(.airDrop) == 1)
        #expect(rig.fake.opens.count == 1)
        #expect(rig.sections.writes == [.section(.hidden, original)])
    }

    @Test("Wi-Fi gets a stand-in from its own setting, and its original is moved to Hidden and kept out of reveals")
    func wiFiStandInReplacesOriginal() async {
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = false
        rig.settings.optInStandIns = ["wifi"]
        rig.shownInControlCenter = [TakeoverRig.moduleTag(TakeoverRig.wiFi)]
        let original = TakeoverRig.moduleID(TakeoverRig.wiFi)

        rig.start()
        await settle { rig.sections.sectionAssignment[original] == .hidden }
        await rig.drain()

        #expect(rig.fake.opened(.wiFi) == 1)
        #expect(rig.fake.opens.count == 1)
        #expect(rig.sections.replacedItems == [original])

        rig.settings.optInStandIns = []
        await settle { rig.sections.replacedItems.isEmpty }
        #expect(rig.sections.sectionAssignment[original] == .visible)
    }

    @Test("A stand-in that keeps exiting gives its original back, until its switch is turned off and on")
    func crashingStandInReturnsOriginal() async throws {
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = false
        rig.settings.optInStandIns = ["wifi"]
        rig.shownInControlCenter = [TakeoverRig.moduleTag(TakeoverRig.wiFi)]
        let original = TakeoverRig.moduleID(TakeoverRig.wiFi)
        rig.start()
        await settle { rig.sections.sectionAssignment[original] == .hidden }

        for _ in 1 ... 4 {
            let count = rig.fake.startedProcesses.count
            try #require(rig.fake.startedProcesses.last).exit()
            await settle { rig.fake.startedProcesses.count > count || rig.sections.replacedItems.isEmpty }
        }
        await settle { rig.sections.sectionAssignment[original] == .visible }
        #expect(rig.sections.replacedItems.isEmpty)
        #expect(rig.sections.sectionAssignment[original] == .visible)
        #expect(rig.fake.opened(.wiFi) == 4, "three restarts, then no more")

        // Back to back, the off and the on can reach the coordinator as one change.
        let publishes = rig.sections.replacedItemsPublishes
        rig.settings.optInStandIns = []
        await settle { rig.sections.replacedItemsPublishes > publishes }
        #expect(rig.fake.opened(.wiFi) == 4)
        rig.settings.optInStandIns = ["wifi"]
        await settle { rig.fake.opened(.wiFi) == 5 }
        #expect(rig.fake.opened(.wiFi) == 5)
        #expect(rig.sections.replacedItems == [original])
    }

    @Test("A stand-in that fails to open gives its original back its section and leaves the order alone")
    func failedOpenKeepsOriginal() async {
        struct OpenFailed: Error {}
        let rig = TakeoverRig()
        rig.settings.enableModuleStandIns = false
        rig.settings.optInStandIns = ["wifi"]
        rig.shownInControlCenter = [TakeoverRig.moduleTag(TakeoverRig.wiFi)]
        let original = TakeoverRig.moduleID(TakeoverRig.wiFi)
        rig.sections.sectionItemOrder[.visible] = ["a", original, "b"]
        rig.fake.openError = OpenFailed()
        var ordersAtOpen = 0
        // What a layout change during the open would do: the placed stand-in's original is hidden.
        rig.fake.duringOpen = {
            rig.sections.sectionAssignment[original] = .hidden
            ordersAtOpen = rig.sections.writes.count { if case .order = $0 { true } else { false } }
        }
        rig.start()
        await settle { rig.sections.sectionAssignment[original] == .visible }
        await rig.drain()

        #expect(rig.sections.sectionAssignment[original] == .visible)
        #expect(rig.sections.writes.count { if case .order = $0 { true } else { false } } == ordersAtOpen)
        #expect(rig.sections.replacedItems.isEmpty)
        #expect(rig.launcher.placed.isEmpty)
    }

    @Test("An original the user brings back to Visible is moved to Hidden again on the next layout change")
    func layoutChangeRehidesOriginal() async {
        let rig = rig()
        rig.shownInControlCenter = [TakeoverRig.moduleTag(TakeoverRig.airDrop)]
        let original = TakeoverRig.moduleID(TakeoverRig.airDrop)
        rig.start()
        await settle { rig.sections.sectionAssignment[original] == .hidden }

        rig.sections.setSection(.visible, identifier: original)
        rig.sections.announce()
        await settle { rig.sections.sectionAssignment[original] == .hidden }
        await rig.drain()

        #expect(rig.sections.writes.last == .section(.hidden, original))
        #expect(rig.fake.opened(.airDrop) == 1)
    }

    @Test("A stand-in placed in an earlier session keeps its section")
    func savedStandInKeepsSection() async {
        let rig = rig()
        let standIn = TakeoverRig.standInID(.focus)
        rig.sections.sectionAssignment[TakeoverRig.moduleID(TakeoverRig.focus)] = .hidden
        rig.sections.sectionAssignment[standIn] = .alwaysHidden
        rig.sections.sectionItemOrder[.alwaysHidden] = [standIn]

        rig.start()
        await settle { rig.fake.opens.count == 1 }
        await rig.drain()

        #expect(rig.fake.opened(.focus) == 1)
        #expect(rig.sections.writes.isEmpty)
        #expect(rig.sections.sectionAssignment[standIn] == .alwaysHidden)
    }

    @Test("A skipped module launches nothing and hands a saved stand-in's place back to its original")
    func skippedModuleRetiresStandIn() async {
        let rig = rig()
        rig.settings.skippedModuleStandIns = [SystemExtraStandIn.focus.rawValue]
        let standIn = TakeoverRig.standInID(.focus)
        let original = TakeoverRig.moduleID(TakeoverRig.focus)
        rig.sections.sectionAssignment[original] = .hidden
        rig.sections.sectionAssignment[standIn] = .alwaysHidden
        rig.sections.sectionItemOrder[.alwaysHidden] = ["a", standIn, "b"]

        rig.start()
        await rig.drain()

        #expect(rig.fake.opens.isEmpty)
        #expect(rig.sections.writes == [
            .section(.alwaysHidden, original),
            .order(["a", "b"], .alwaysHidden),
        ])
    }

    @Test("Turning module stand-ins off quits a running one and returns its place to the original")
    func disablingStopsAndRetires() async throws {
        let rig = rig()
        let standIn = TakeoverRig.standInID(.focus)
        let original = TakeoverRig.moduleID(TakeoverRig.focus)
        rig.sections.sectionAssignment[original] = .hidden
        rig.sections.sectionItemOrder[.hidden] = [original]
        rig.start()
        await settle { rig.fake.startedProcesses.count == 1 }
        await rig.drain()
        let process = try #require(rig.fake.startedProcesses.only)
        #expect(rig.sections.sectionItemOrder[.hidden] == [original, standIn])

        rig.settings.enableModuleStandIns = false
        await settle { process.terminateCalls > 0 }
        await rig.drain()

        #expect(process.terminateCalls == 1)
        #expect(rig.launcher.placed.isEmpty)
        #expect(rig.sections.writes.suffix(2) == [.section(.hidden, original), .order([original], .hidden)])
    }

    @Test("A running module stand-in names its original as replaced, and a stopped one does not")
    func runningStandInReplacesItsOriginal() async throws {
        let rig = rig()
        let original = TakeoverRig.moduleID(TakeoverRig.airDrop)
        rig.sections.sectionAssignment[original] = .hidden
        #expect(rig.coordinator.replacedOriginalIdentifiers.isEmpty, "Nothing is replaced before a stand-in runs")
        let changes = ObservedChanges()
        changes.watch { _ = rig.coordinator.replacedOriginalIdentifiers }

        rig.start()
        await settle { rig.fake.startedProcesses.count == 1 }
        await rig.drain()
        #expect(rig.coordinator.replacedOriginalIdentifiers == [original])
        #expect(changes.count == 1, "whoever reads it hears the stand-in start")
        changes.watch { _ = rig.coordinator.replacedOriginalIdentifiers }

        let process = try #require(rig.fake.startedProcesses.only)
        rig.settings.enableModuleStandIns = false
        await settle { process.terminateCalls > 0 }
        await rig.drain()
        #expect(rig.coordinator.replacedOriginalIdentifiers.isEmpty)
        #expect(changes.count == 2, "and hears it stop")
    }

    @Test("Turning off a stand-in that never joined a saved order returns its original to Visible")
    func disablingUnorderedStandInReturnsOriginal() async throws {
        let rig = rig()
        rig.shownInControlCenter = [TakeoverRig.moduleTag(TakeoverRig.focus)]
        let original = TakeoverRig.moduleID(TakeoverRig.focus)
        rig.start()
        await settle { rig.sections.sectionAssignment[original] == .hidden }
        await rig.drain()
        let process = try #require(rig.fake.startedProcesses.only)
        #expect(rig.sections.sectionItemOrder.values.joined().isEmpty)

        rig.settings.enableModuleStandIns = false
        await settle { process.terminateCalls > 0 }
        await rig.drain()

        #expect(rig.sections.authoredSection(for: original) == .visible)
    }

    @Test("A stand-in that failed to launch is tried again on the next layout change")
    func failedLaunchIsRetried() async {
        let rig = rig()
        rig.sections.sectionAssignment[TakeoverRig.moduleID(TakeoverRig.focus)] = .hidden
        rig.fake.missingBundles = [SystemExtraStandIn.focus.bundleURL]
        rig.start()
        await rig.drain()
        #expect(rig.fake.opens.isEmpty)

        rig.fake.missingBundles = []
        rig.sections.announce()
        await settle { rig.fake.opens.count == 1 }

        #expect(rig.fake.opened(.focus) == 1)
    }
}

/// Counts what withObservationTracking reports, one change for each watch.
private final class ObservedChanges: Sendable {
    private let changes = OSAllocatedUnfairLock(initialState: 0)

    var count: Int {
        changes.withLock { $0 }
    }

    func watch(_ read: () -> Void) {
        withObservationTracking(read) { [changes] in changes.withLock { $0 += 1 } }
    }
}

@Suite("Module stand-in choice", .scratchDefaults)
@MainActor
struct ModuleStandInChoiceTests {
    private func settings(modules: Bool, skipped: Set<String> = [], wiFi: Bool = false) -> LayoutSettings {
        let settings = LayoutSettings()
        settings.enableModuleStandIns = modules
        settings.skippedModuleStandIns = skipped
        settings.optInStandIns = wiFi ? ["wifi"] : []
        return settings
    }

    @Test("A stand-in runs when stand-ins are on and its checkbox is left on")
    func chosen() {
        #expect(SystemExtraTakeoverCoordinator.isChosen(.airDrop, in: settings(modules: true)))
        #expect(SystemExtraTakeoverCoordinator.isChosen(.airDrop, in: settings(modules: true, skipped: ["focus"])))
    }

    @Test("Unchecking an item, or turning stand-ins off, keeps Apple's own")
    func notChosen() {
        #expect(!SystemExtraTakeoverCoordinator.isChosen(.airDrop, in: settings(modules: true, skipped: ["airdrop"])))
        #expect(!SystemExtraTakeoverCoordinator.isChosen(.focus, in: settings(modules: false)))
    }

    @Test("Wi-Fi follows its own setting, not the modules switch")
    func wiFiFollowsItsOwnSetting() {
        #expect(!SystemExtraTakeoverCoordinator.isChosen(.wiFi, in: settings(modules: true)))
        #expect(SystemExtraTakeoverCoordinator.isChosen(.wiFi, in: settings(modules: false, wiFi: true)))
    }
}

/// What the coordinator reports before it starts. It is never started here:
/// starting it launches stand-ins and writes the system's own settings.
@MainActor
@Suite("System extra takeover status")
struct SystemExtraTakeoverCoordinatorStatusTests {
    /// Hands the engine a fixed journal and records every save.
    private final class StubJournal: SystemExtraOriginalJournaling {
        let entries: [String: SystemExtraOriginalValue]
        private(set) var saves = 0

        init(entries: [String: SystemExtraOriginalValue]) {
            self.entries = entries
        }

        func load() throws -> [String: SystemExtraOriginalValue] {
            entries
        }

        func save(_: [String: SystemExtraOriginalValue]) throws {
            saves += 1
        }
    }

    @Test("With nothing journaled every item reads off")
    func offWithEmptyJournal() {
        let journal = StubJournal(entries: [:])
        let coordinator = SystemExtraTakeoverCoordinator(journal: journal)
        for item in SystemExtraItem.allCases {
            #expect(coordinator.status(for: item) == .off)
        }
        #expect(journal.saves == 0)
    }

    @Test("An original journaled by an earlier session reads as owed a restore")
    func journaledOriginalIsPending() {
        let journal = StubJournal(entries: [SystemExtraItem.timeMachine.rawValue: .value(1)])
        let coordinator = SystemExtraTakeoverCoordinator(journal: journal)
        let status = coordinator.status(for: .timeMachine)
        #expect(status.phase == .off)
        #expect(status.recoveryPending)
        #expect(!coordinator.status(for: .timer).recoveryPending)
        #expect(!coordinator.status(for: .textInput).recoveryPending)
        #expect(journal.saves == 0)
    }
}
