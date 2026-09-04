//
//  MenuBarItemTriggersManagerPlanTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Exercises the decision half of ``MenuBarItemTriggersManager``: the priority
/// plan that resolves which trigger owns which item, the identifier resolution
/// that survives an item being re-instanced, the runtime status the settings
/// pane renders, and the legacy-target repair applied on load.
///
/// The manager runs without `performSetup`, so there is no live menu bar, item
/// manager or system monitor behind any of this. Everything a plan needs is
/// passed in: the state, the identifiers currently present, and the clock.
@Suite("Menu bar item triggers priority plan")
@MainActor
struct MenuBarItemTriggersManagerPlanTests {
    // MARK: - Fixtures

    private func makeManager() -> MenuBarItemTriggersManager {
        MenuBarItemTriggersManager(persistenceEnabled: false)
    }

    private func makeTrigger(
        name: String,
        item: String,
        baseIdentifier: String? = nil,
        condition: TriggerCondition = .onACPower,
        isEnabled: Bool = true,
        additionalItems: [TriggerTargetItem] = []
    ) -> MenuBarItemTrigger {
        MenuBarItemTrigger(
            name: name,
            isEnabled: isEnabled,
            itemIdentifier: item,
            itemDisplayName: name,
            itemBaseIdentifier: baseIdentifier,
            additionalItems: additionalItems,
            condition: condition
        )
    }

    /// A state that satisfies `.onACPower` and fails `.onBatteryPower`.
    private var onAC: SystemState {
        SystemState(power: PowerState(batteryPercentage: 50, isOnACPower: true, isCharging: true))
    }

    /// A state that satisfies `.onBatteryPower` and fails `.onACPower`.
    private var onBattery: SystemState {
        SystemState(power: PowerState(batteryPercentage: 50, isOnACPower: false, isCharging: false))
    }

    // MARK: - Identifier resolution

    @Test("An identifier that is present resolves to itself")
    func exactIdentifierResolves() {
        let resolved = MenuBarItemTriggersManager.resolvedPresentIdentifier(
            for: "ns:Title:0",
            capturedBaseIdentifier: nil,
            presentIdentifiers: ["ns:Title:0"],
            presentIdentifierBases: [:]
        )
        #expect(resolved == "ns:Title:0")
    }

    @Test("A re-instanced item resolves through its captured base")
    func baseIdentifierResolvesTheNewInstance() {
        // The item came back under a different instance suffix, which is the
        // whole reason a base identifier is captured alongside the concrete one.
        let resolved = MenuBarItemTriggersManager.resolvedPresentIdentifier(
            for: "ns:Title:0",
            capturedBaseIdentifier: "ns:Title",
            presentIdentifiers: ["ns:Title:3"],
            presentIdentifierBases: ["ns:Title:3": "ns:Title"]
        )
        #expect(resolved == "ns:Title:3")
    }

    @Test("An ambiguous base resolves to nothing rather than to a guess")
    func ambiguousBaseDoesNotResolve() {
        // Two live siblings share the base, so there is no way to tell which
        // one the trigger meant. Moving the wrong sibling is worse than
        // moving nothing.
        let resolved = MenuBarItemTriggersManager.resolvedPresentIdentifier(
            for: "ns:Title:0",
            capturedBaseIdentifier: "ns:Title",
            presentIdentifiers: ["ns:Title:1", "ns:Title:2"],
            presentIdentifierBases: ["ns:Title:1": "ns:Title", "ns:Title:2": "ns:Title"]
        )
        #expect(resolved == nil)
    }

    @Test("Without a captured base an absent identifier stays absent")
    func absentIdentifierWithoutBase() {
        let resolved = MenuBarItemTriggersManager.resolvedPresentIdentifier(
            for: "ns:Title:0",
            capturedBaseIdentifier: nil,
            presentIdentifiers: ["ns:Other:0"],
            presentIdentifierBases: ["ns:Other:0": "ns:Other"]
        )
        #expect(resolved == nil)
    }

    // MARK: - Plan actions

    @Test("A met trigger claims its target for a reveal")
    func metTriggerRevealsItsTarget() {
        let manager = makeManager()
        let trigger = makeTrigger(name: "Plugged in", item: "item-a")
        manager.add(trigger)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])

        #expect(plan.actions[trigger.id]?.reveal == true)
        #expect(plan.actions[trigger.id]?.identifiers == ["item-a"])
        #expect(plan.overriddenBy.isEmpty)
        #expect(plan.unavailableTriggerIDs.isEmpty)
    }

    @Test("An unmet trigger claims its target for a hide")
    func unmetTriggerHidesItsTarget() {
        let manager = makeManager()
        let trigger = makeTrigger(name: "Plugged in", item: "item-a")
        manager.add(trigger)

        let plan = manager.priorityPlan(for: onBattery, presentIdentifiers: ["item-a"])

        #expect(plan.actions[trigger.id]?.reveal == false)
        #expect(plan.actions[trigger.id]?.identifiers == ["item-a"])
    }

    @Test("A disabled trigger contributes nothing at all")
    func disabledTriggerIsSkipped() {
        let manager = makeManager()
        let trigger = makeTrigger(name: "Off", item: "item-a", isEnabled: false)
        manager.add(trigger)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])

        #expect(plan.actions.isEmpty)
        #expect(plan.unavailableTriggerIDs.isEmpty)
    }

    @Test("A trigger with no target item is skipped without being marked unavailable")
    func targetlessTriggerIsSkipped() {
        let manager = makeManager()
        let trigger = makeTrigger(name: "Nothing", item: "")
        manager.add(trigger)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])

        #expect(plan.actions.isEmpty)
        #expect(plan.unavailableTriggerIDs.isEmpty)
    }

    @Test("A trigger whose item is absent is reported unavailable")
    func absentTargetIsUnavailable() {
        let manager = makeManager()
        let trigger = makeTrigger(name: "Missing", item: "item-gone")
        manager.add(trigger)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])

        #expect(plan.actions.isEmpty)
        #expect(plan.unavailableTriggerIDs == [trigger.id])
    }

    @Test("Extra target items join the same action, deduplicated")
    func additionalItemsJoinTheAction() {
        let manager = makeManager()
        let trigger = makeTrigger(
            name: "Two items",
            item: "item-a",
            additionalItems: [
                TriggerTargetItem(identifier: "item-b", displayName: "B"),
                // A repeat of the primary target must not be moved twice.
                TriggerTargetItem(identifier: "item-a", displayName: "A again"),
                // An empty target is ignored rather than resolved.
                TriggerTargetItem(identifier: "", displayName: ""),
            ]
        )
        manager.add(trigger)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a", "item-b"])

        #expect(plan.actions[trigger.id]?.identifiers == ["item-a", "item-b"])
        #expect(plan.actions[trigger.id]?.identifierSet == ["item-a", "item-b"])
    }

    @Test("Only the present half of a multi-item target is acted on")
    func partiallyPresentTargetsAreTrimmed() {
        let manager = makeManager()
        let trigger = makeTrigger(
            name: "Two items",
            item: "item-a",
            additionalItems: [TriggerTargetItem(identifier: "item-gone", displayName: "Gone")]
        )
        manager.add(trigger)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])

        #expect(plan.actions[trigger.id]?.identifiers == ["item-a"])
        #expect(plan.unavailableTriggerIDs.isEmpty)
    }

    // MARK: - Priority

    @Test("The earlier trigger wins a contested item and names itself as the override")
    func earlierTriggerWinsAContestedItem() {
        let manager = makeManager()
        let winner = makeTrigger(name: "Winner", item: "item-a")
        let loser = makeTrigger(name: "Loser", item: "item-a")
        manager.add(winner)
        manager.add(loser)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])

        #expect(plan.actions[winner.id]?.identifiers == ["item-a"])
        #expect(plan.actions[loser.id] == nil)
        #expect(plan.overriddenBy[loser.id] == ["Winner"])
    }

    @Test("An overridden trigger still acts on the targets nobody else claimed")
    func partialOverrideKeepsTheUncontestedItem() {
        let manager = makeManager()
        let winner = makeTrigger(name: "Winner", item: "item-a")
        let loser = makeTrigger(
            name: "Loser",
            item: "item-a",
            additionalItems: [TriggerTargetItem(identifier: "item-b", displayName: "B")]
        )
        manager.add(winner)
        manager.add(loser)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a", "item-b"])

        #expect(plan.actions[winner.id]?.identifiers == ["item-a"])
        #expect(plan.actions[loser.id]?.identifiers == ["item-b"])
        #expect(plan.overriddenBy[loser.id] == ["Winner"])
    }

    @Test("Override names are reported sorted and without repeats")
    func overrideNamesAreSortedAndUnique() {
        let manager = makeManager()
        manager.add(makeTrigger(
            name: "Zulu",
            item: "item-a",
            additionalItems: [TriggerTargetItem(identifier: "item-b", displayName: "B")]
        ))
        manager.add(makeTrigger(name: "Alpha", item: "item-c"))
        let loser = makeTrigger(
            name: "Loser",
            item: "item-a",
            additionalItems: [
                TriggerTargetItem(identifier: "item-b", displayName: "B"),
                TriggerTargetItem(identifier: "item-c", displayName: "C"),
            ]
        )
        manager.add(loser)

        let plan = manager.priorityPlan(
            for: onAC,
            presentIdentifiers: ["item-a", "item-b", "item-c"]
        )

        // Zulu owns two of the contested items but is named once.
        #expect(plan.overriddenBy[loser.id] == ["Alpha", "Zulu"])
        #expect(plan.actions[loser.id] == nil)
    }

    @Test("A met trigger outranks an unmet one on the same item, whatever the order")
    func metTriggerOutranksUnmetRegardlessOfOrder() {
        // The unmet trigger is listed first, so priority order alone would
        // give it the item. Met triggers are resolved before any hide
        // fallback, which is what keeps a satisfied rule from being starved
        // by a higher-priority rule that has nothing to say right now.
        let manager = makeManager()
        let unmet = makeTrigger(name: "Unmet", item: "item-a", condition: .onBatteryPower)
        let met = makeTrigger(name: "Met", item: "item-a", condition: .onACPower)
        manager.add(unmet)
        manager.add(met)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])

        #expect(plan.actions[met.id]?.reveal == true)
        #expect(plan.actions[unmet.id] == nil)
    }

    @Test("Among unmet triggers the earlier one claims the hide")
    func firstUnmetTriggerClaimsTheHide() {
        let manager = makeManager()
        let first = makeTrigger(name: "First", item: "item-a", condition: .onBatteryPower)
        let second = makeTrigger(name: "Second", item: "item-a", condition: .onBatteryPower)
        manager.add(first)
        manager.add(second)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])

        #expect(plan.actions[first.id]?.reveal == false)
        // A losing hide is not an override: nothing is currently revealing
        // the item, so there is no owner to name.
        #expect(plan.actions[second.id] == nil)
        #expect(plan.overriddenBy[second.id] == nil)
    }

    @Test("Inverting a trigger swaps which state claims the reveal")
    func invertedTriggerFlipsTheDecision() {
        let manager = makeManager()
        var trigger = makeTrigger(name: "Inverted", item: "item-a")
        trigger.invert = true
        manager.add(trigger)

        #expect(manager.priorityPlan(
            for: onAC, presentIdentifiers: ["item-a"]
        ).actions[trigger.id]?.reveal == false)
        #expect(manager.priorityPlan(
            for: onBattery, presentIdentifiers: ["item-a"]
        ).actions[trigger.id]?.reveal == true)
    }

    @Test("A plan resolves targets through their captured base identifiers")
    func planResolvesThroughBaseIdentifiers() {
        let manager = makeManager()
        let trigger = makeTrigger(
            name: "Reinstanced",
            item: "ns:Title:0",
            baseIdentifier: "ns:Title"
        )
        manager.add(trigger)

        let plan = manager.priorityPlan(
            for: onAC,
            presentIdentifiers: ["ns:Title:4"],
            presentIdentifierBases: ["ns:Title:4": "ns:Title"]
        )

        #expect(plan.actions[trigger.id]?.identifiers == ["ns:Title:4"])
    }

    @Test("A schedule condition is evaluated against the clock the caller passes")
    func planUsesTheSuppliedClock() throws {
        let manager = makeManager()
        manager.featureFlags.setEnabled(.schedule, true)
        let trigger = makeTrigger(
            name: "Morning",
            item: "item-a",
            condition: .schedule(startMinutes: 9 * 60, endMinutes: 17 * 60)
        )
        manager.add(trigger)

        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 12
        let noon = try #require(Calendar.current.date(from: components))
        components.hour = 3
        let earlyMorning = try #require(Calendar.current.date(from: components))

        #expect(manager.priorityPlan(
            for: onAC, presentIdentifiers: ["item-a"], now: noon
        ).actions[trigger.id]?.reveal == true)
        #expect(manager.priorityPlan(
            for: onAC, presentIdentifiers: ["item-a"], now: earlyMorning
        ).actions[trigger.id]?.reveal == false)
    }

    // MARK: - Feature availability

    @Test("A trigger whose feature is off is skipped entirely")
    func flaggedOffTriggerIsSkipped() {
        let manager = makeManager()
        manager.featureFlags.setEnabled(.network, false)
        let trigger = makeTrigger(name: "Network", item: "item-a", condition: .networkConnected)
        manager.add(trigger)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])

        #expect(plan.actions.isEmpty)
        #expect(plan.unavailableTriggerIDs.isEmpty)
        #expect(manager.runtimeStatus(for: trigger) == .inactive)
    }

    @Test("Turning the feature on makes the same trigger available again")
    func flaggedOnTriggerBecomesAvailable() {
        let manager = makeManager()
        let trigger = makeTrigger(name: "Network", item: "item-a", condition: .networkConnected)
        manager.add(trigger)
        manager.featureFlags.setEnabled(.network, true)

        var connected = onAC
        connected.isNetworkConnected = true
        let plan = manager.priorityPlan(for: connected, presentIdentifiers: ["item-a"])

        #expect(plan.actions[trigger.id]?.reveal == true)
    }

    @Test("Power conditions need no feature flag")
    func powerConditionsAreAlwaysAvailable() {
        let manager = makeManager()
        manager.featureFlags.disableAll()
        let trigger = makeTrigger(name: "Power", item: "item-a", condition: .onACPower)
        manager.add(trigger)

        #expect(manager.priorityPlan(
            for: onAC, presentIdentifiers: ["item-a"]
        ).actions[trigger.id]?.reveal == true)
        #expect(manager.runtimeStatus(for: trigger) != .inactive)
    }

    @Test("A compound trigger needs every one of its features")
    func compoundTriggerNeedsAllItsFeatures() {
        let manager = makeManager()
        var trigger = makeTrigger(name: "Compound", item: "item-a", condition: .onACPower)
        trigger.additionalConditions = [.networkConnected]
        manager.add(trigger)

        manager.featureFlags.setEnabled(.network, false)
        #expect(manager.runtimeStatus(for: trigger) == .inactive)

        manager.featureFlags.setEnabled(.network, true)
        #expect(manager.runtimeStatus(for: trigger) != .inactive)
    }

    // MARK: - Runtime status

    @Test("A disabled trigger reads as off before anything else is considered")
    func disabledTriggerReadsOff() {
        let manager = makeManager()
        manager.featureFlags.disableAll()
        let trigger = makeTrigger(
            name: "Off",
            item: "item-a",
            condition: .networkConnected,
            isEnabled: false
        )
        manager.add(trigger)

        // Off outranks inactive: the user turned this one off themselves.
        #expect(manager.runtimeStatus(for: trigger) == .off)
    }

    @Test("An enabled trigger with nothing applied reads from the live decision")
    func idleAndPendingStatuses() {
        let manager = makeManager()
        let onACTrigger = makeTrigger(name: "AC", item: "item-a", condition: .onACPower)
        manager.add(onACTrigger)

        // Nothing has been applied, so the status is whatever the condition
        // says right now. The real power state decides which of the two it is.
        let status = manager.runtimeStatus(for: onACTrigger)
        #expect(status == .pending || status == .idle)
        #expect(manager.shouldRevealNow(onACTrigger) == (status == .pending))
        #expect(!manager.isCurrentlyRevealed(onACTrigger))
    }

    @Test("Terminal statuses survive being read back")
    func terminalStatusesAreTerminal() {
        #expect(MenuBarItemTriggerRuntimeStatus.overridden(by: ["A"]).isTerminalForDisplay)
        #expect(MenuBarItemTriggerRuntimeStatus.deferred.isTerminalForDisplay)
        #expect(MenuBarItemTriggerRuntimeStatus.unavailable.isTerminalForDisplay)
        #expect(MenuBarItemTriggerRuntimeStatus.failed.isTerminalForDisplay)

        for status in [
            MenuBarItemTriggerRuntimeStatus.off, .inactive, .settling,
            .moving, .active, .idle, .pending,
        ] {
            #expect(!status.isTerminalForDisplay)
        }
    }

    // MARK: - Ownership

    @Test("Ownership does not wait for the condition to be met")
    func ownershipDoesNotWaitForTheCondition() {
        let manager = makeManager()
        // The condition is not met, but ownership is about configuration, not
        // satisfaction: the layout editor must not offer the item as free.
        let trigger = makeTrigger(
            name: "Battery",
            item: "ns:Title:0",
            baseIdentifier: "ns:Title",
            condition: .onBatteryPower
        )
        manager.add(trigger)

        #expect(manager.controllingTrigger(forBaseIdentifier: "ns:Title")?.id == trigger.id)
        #expect(manager.isControlledByTrigger(baseIdentifier: "ns:Title"))
    }

    @Test("Exact-identifier ownership stays empty until an item cache resolves it")
    func exactOwnershipNeedsALiveItemCache() {
        // `controlledIdentifiers` holds live identifiers, and every target is
        // put through `resolvedPresentIdentifier` to get one. Without a live
        // item cache nothing is present, so nothing resolves — and the base
        // query below is the only one that can still answer.
        let manager = makeManager()
        let trigger = makeTrigger(name: "Battery", item: "item-a", baseIdentifier: "item-a")
        manager.add(trigger)

        #expect(manager.controlledIdentifiers.isEmpty)
        #expect(!manager.isControlledByTrigger(identifier: "item-a"))
        #expect(manager.controllingTrigger(forIdentifier: "item-a") == nil)
        #expect(manager.controllingTrigger(forBaseIdentifier: "item-a")?.id == trigger.id)
    }

    @Test("A disabled or flagged-off trigger owns nothing")
    func ownershipRequiresAnAvailableTrigger() {
        let manager = makeManager()
        manager.add(makeTrigger(
            name: "Off", item: "ns:A:0", baseIdentifier: "ns:A", isEnabled: false
        ))
        manager.add(makeTrigger(
            name: "Network", item: "ns:B:0", baseIdentifier: "ns:B", condition: .networkConnected
        ))
        manager.featureFlags.setEnabled(.network, false)
        manager.refreshControlledIdentifiers()

        #expect(manager.controllingTrigger(forBaseIdentifier: "ns:A") == nil)
        #expect(manager.controllingTrigger(forBaseIdentifier: "ns:B") == nil)
        #expect(manager.controlledIdentifiers.isEmpty)
    }

    @Test("An empty identifier is never owned")
    func emptyIdentifierIsNeverOwned() {
        let manager = makeManager()
        manager.add(makeTrigger(name: "Real", item: "item-a"))

        #expect(!manager.isControlledByTrigger(identifier: ""))
        #expect(manager.controllingTrigger(forIdentifier: "") == nil)
        #expect(manager.controllingTrigger(forBaseIdentifier: "") == nil)
    }

    @Test("The first trigger in priority order is the one reported as owner")
    func ownerIsTheHighestPriorityTrigger() {
        let manager = makeManager()
        let first = makeTrigger(name: "First", item: "ns:A:0", baseIdentifier: "ns:A")
        let second = makeTrigger(name: "Second", item: "ns:A:0", baseIdentifier: "ns:A")
        manager.add(first)
        manager.add(second)

        #expect(manager.controllingTrigger(forBaseIdentifier: "ns:A")?.id == first.id)
    }

    @Test("The base-identifier query matches either half of a target's identity")
    func baseIdentifierOwnership() {
        let manager = makeManager()
        let byBase = makeTrigger(name: "ByBase", item: "ns:Title:2", baseIdentifier: "ns:Title")
        manager.add(byBase)

        #expect(manager.controllingTrigger(forBaseIdentifier: "ns:Title")?.id == byBase.id)
        #expect(manager.isControlledByTrigger(baseIdentifier: "ns:Title"))
        #expect(!manager.isControlledByTrigger(baseIdentifier: "ns:Other"))
    }

    // MARK: - Priority reordering

    @Test("Moving a trigger by index reorders it")
    func moveTriggerByIndex() {
        let manager = makeManager()
        for name in ["A", "B", "C"] {
            manager.add(makeTrigger(name: name, item: "item-\(name)"))
        }

        manager.moveTrigger(from: 2, to: 0)
        #expect(manager.triggers.map(\.name) == ["C", "A", "B"])
    }

    @Test("An out-of-range or no-op index move changes nothing")
    func invalidIndexMovesAreIgnored() {
        let manager = makeManager()
        for name in ["A", "B"] {
            manager.add(makeTrigger(name: name, item: "item-\(name)"))
        }

        manager.moveTrigger(from: 5, to: 0)
        manager.moveTrigger(from: 0, to: 5)
        manager.moveTrigger(from: 1, to: 1)
        #expect(manager.triggers.map(\.name) == ["A", "B"])
    }

    @Test("Dropping one trigger before another reorders it")
    func moveTriggerBeforeAnother() {
        let manager = makeManager()
        var made = [MenuBarItemTrigger]()
        for name in ["A", "B", "C"] {
            let trigger = makeTrigger(name: name, item: "item-\(name)")
            made.append(trigger)
            manager.add(trigger)
        }

        manager.moveTrigger(id: made[2].id, before: made[0].id)
        #expect(manager.triggers.map(\.name) == ["C", "A", "B"])
    }

    @Test("Reordering around an unknown id changes nothing")
    func unknownIDMovesAreIgnored() {
        let manager = makeManager()
        let trigger = makeTrigger(name: "A", item: "item-a")
        manager.add(trigger)

        manager.moveTrigger(id: UUID(), before: trigger.id)
        manager.moveTrigger(id: trigger.id, before: UUID())
        #expect(manager.triggers.map(\.name) == ["A"])
    }

    @Test("Reordering changes which trigger wins a contested item")
    func reorderingChangesThePlanOwner() {
        let manager = makeManager()
        let first = makeTrigger(name: "First", item: "item-a")
        let second = makeTrigger(name: "Second", item: "item-a")
        manager.add(first)
        manager.add(second)

        manager.moveTrigger(from: 1, to: 0)

        let plan = manager.priorityPlan(for: onAC, presentIdentifiers: ["item-a"])
        #expect(plan.actions[second.id]?.identifiers == ["item-a"])
        #expect(plan.overriddenBy[first.id] == ["Second"])
    }

    // MARK: - Legacy target repair

    @Test("The old battery fixture identifier is repaired to the real item")
    func legacyBatteryFixtureIsRepaired() {
        let expected = MenuBarItemTag(namespace: .controlCenter, title: "Battery").tagIdentifier
        let legacy = MenuBarItemTrigger(
            name: "Battery",
            itemIdentifier: "battery-item",
            itemDisplayName: "battery-item"
        )

        let repaired = MenuBarItemTriggersManager
            .repairingLegacyTestFixtureIdentifiers(in: [legacy])

        #expect(repaired[0].itemIdentifier == expected)
        #expect(repaired[0].itemDisplayName == "Battery")
    }

    @Test("A legacy target with a real display name keeps it")
    func legacyRepairKeepsAUsefulDisplayName() {
        let legacy = MenuBarItemTrigger(
            name: "Battery",
            itemIdentifier: "battery-item",
            itemDisplayName: "My Battery"
        )

        let repaired = MenuBarItemTriggersManager
            .repairingLegacyTestFixtureIdentifiers(in: [legacy])

        #expect(repaired[0].itemDisplayName == "My Battery")
    }

    @Test("A non-numeric final component is adopted as the stable base")
    func nonNumericIdentifierBecomesItsOwnBase() {
        let legacy = MenuBarItemTrigger(
            name: "Old",
            itemIdentifier: "ns:Title",
            itemDisplayName: "Old"
        )

        let repaired = MenuBarItemTriggersManager
            .repairingLegacyTestFixtureIdentifiers(in: [legacy])

        #expect(repaired[0].itemBaseIdentifier == "ns:Title")
    }

    @Test("A numeric final component stays ambiguous and gets no base")
    func numericSuffixIsLeftAlone() {
        // The trailing number could be an instance suffix or part of the
        // title. Only live tag data can tell, so nothing is invented here.
        let legacy = MenuBarItemTrigger(
            name: "Old",
            itemIdentifier: "ns:Title:2",
            itemDisplayName: "Old"
        )

        let repaired = MenuBarItemTriggersManager
            .repairingLegacyTestFixtureIdentifiers(in: [legacy])

        #expect(repaired[0].itemBaseIdentifier == nil)
    }

    @Test("An already-captured base is not overwritten")
    func existingBaseIsPreserved() {
        let current = MenuBarItemTrigger(
            name: "Current",
            itemIdentifier: "ns:Title",
            itemDisplayName: "Current",
            itemBaseIdentifier: "ns:Captured"
        )

        let repaired = MenuBarItemTriggersManager
            .repairingLegacyTestFixtureIdentifiers(in: [current])

        #expect(repaired[0].itemBaseIdentifier == "ns:Captured")
    }

    @Test("Repair reaches the additional targets too")
    func legacyRepairCoversAdditionalItems() {
        let expected = MenuBarItemTag(namespace: .controlCenter, title: "Battery").tagIdentifier
        let legacy = MenuBarItemTrigger(
            name: "Multi",
            itemIdentifier: "ns:Title",
            itemDisplayName: "Multi",
            additionalItems: [
                TriggerTargetItem(identifier: "battery-item", displayName: ""),
                TriggerTargetItem(identifier: "ns:Other", displayName: "Other"),
            ]
        )

        let repaired = MenuBarItemTriggersManager
            .repairingLegacyTestFixtureIdentifiers(in: [legacy])

        #expect(repaired[0].additionalItems[0].identifier == expected)
        #expect(repaired[0].additionalItems[0].displayName == "Battery")
        #expect(repaired[0].additionalItems[1].baseIdentifier == "ns:Other")
    }

    @Test("An identifier with no namespace separator is left untouched")
    func identifierWithoutANamespaceGetsNoBase() {
        let legacy = MenuBarItemTrigger(
            name: "Bare",
            itemIdentifier: "bare",
            itemDisplayName: "Bare"
        )

        let repaired = MenuBarItemTriggersManager
            .repairingLegacyTestFixtureIdentifiers(in: [legacy])

        #expect(repaired[0].itemBaseIdentifier == nil)
    }

    // MARK: - Plan assembly

    @Test("Setting the same decision twice merges the identifiers")
    func planMergesRepeatedDecisions() {
        var plan = MenuBarItemTriggersManager.TriggerPriorityPlan()
        let id = UUID()

        plan.setAction(reveal: true, identifiers: ["a", "b", "a"], for: id)
        plan.setAction(reveal: true, identifiers: ["b", "c"], for: id)

        #expect(plan.actions[id]?.identifiers == ["a", "b", "c"])
    }

    @Test("Setting the opposite decision replaces the action")
    func planReplacesAFlippedDecision() {
        var plan = MenuBarItemTriggersManager.TriggerPriorityPlan()
        let id = UUID()

        plan.setAction(reveal: true, identifiers: ["a"], for: id)
        plan.setAction(reveal: false, identifiers: ["b"], for: id)

        #expect(plan.actions[id]?.reveal == false)
        #expect(plan.actions[id]?.identifiers == ["b"])
    }
}
