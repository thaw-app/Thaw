//
//  MenuBarItemTriggersManagerCRUDTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Exercises the trigger CRUD surface of ``MenuBarItemTriggersManager`` —
/// add, remove, update, and priority reordering, plus what survives a
/// reload. The manager runs without `performSetup`, so no live menu bar,
/// item manager, or system monitors are involved.
@Suite("Menu bar item triggers manager CRUD")
@MainActor
struct MenuBarItemTriggersManagerCRUDTests {
    private func makeTrigger(named name: String, item: String) -> MenuBarItemTrigger {
        MenuBarItemTrigger(
            name: name,
            itemIdentifier: item,
            condition: .onACPower
        )
    }

    // MARK: - In-memory CRUD

    @Test("Add appends in order")
    func addAppends() {
        let manager = MenuBarItemTriggersManager(persistenceEnabled: false)
        let first = makeTrigger(named: "First", item: "item-a")
        let second = makeTrigger(named: "Second", item: "item-b")

        manager.add(first)
        manager.add(second)

        #expect(manager.triggers.map(\.name) == ["First", "Second"])
    }

    @Test("Removing by id drops the trigger and its recorded state")
    func removeByID() {
        let manager = MenuBarItemTriggersManager(persistenceEnabled: false)
        let trigger = makeTrigger(named: "Only", item: "item-a")
        manager.add(trigger)

        manager.remove(id: trigger.id)

        #expect(manager.triggers.isEmpty)
        #expect(manager.controllingTrigger(forBaseIdentifier: "item-a") == nil)
        #expect(!manager.isControlledByTrigger(baseIdentifier: "item-a"))
    }

    @Test("Removing an unknown id is a harmless no-op")
    func removeUnknownID() {
        let manager = MenuBarItemTriggersManager(persistenceEnabled: false)
        manager.remove(id: UUID())
        #expect(manager.triggers.isEmpty)
    }

    @Test("Removing at offsets removes exactly those triggers")
    func removeAtOffsets() {
        let manager = MenuBarItemTriggersManager(persistenceEnabled: false)
        let one = makeTrigger(named: "One", item: "item-a")
        let two = makeTrigger(named: "Two", item: "item-b")
        let three = makeTrigger(named: "Three", item: "item-c")
        manager.add(one)
        manager.add(two)
        manager.add(three)

        manager.remove(atOffsets: IndexSet([1]))

        #expect(manager.triggers.map(\.name) == ["One", "Three"])
        #expect(manager.controllingTrigger(forBaseIdentifier: "item-b") == nil)
        #expect(manager.controllingTrigger(forBaseIdentifier: "item-a") != nil)
    }

    @Test("Update replaces the trigger sharing the id and ignores strangers")
    func updateReplacesByID() {
        let manager = MenuBarItemTriggersManager(persistenceEnabled: false)
        let original = makeTrigger(named: "Original", item: "item-a")
        manager.add(original)

        var edited = original
        edited.name = "Edited"
        manager.update(edited)
        #expect(manager.triggers.count == 1)
        #expect(manager.triggers[0].name == "Edited")

        let stranger = makeTrigger(named: "Stranger", item: "item-z")
        manager.update(stranger)
        #expect(manager.triggers.count == 1)
        #expect(manager.triggers[0].name == "Edited")
    }

    // MARK: - Priority reordering

    @Test("moveTrigger reorders by index and ignores out-of-range moves")
    func moveTriggerByIndex() {
        let manager = MenuBarItemTriggersManager(persistenceEnabled: false)
        let a = makeTrigger(named: "A", item: "item-a")
        let b = makeTrigger(named: "B", item: "item-b")
        let c = makeTrigger(named: "C", item: "item-c")
        manager.add(a)
        manager.add(b)
        manager.add(c)

        manager.moveTrigger(from: 2, to: 0)
        #expect(manager.triggers.map(\.name) == ["C", "A", "B"])

        // Out-of-range and no-op moves leave the order alone.
        manager.moveTrigger(from: 0, to: 0)
        manager.moveTrigger(from: -1, to: 0)
        manager.moveTrigger(from: 0, to: 99)
        #expect(manager.triggers.map(\.name) == ["C", "A", "B"])
    }

    @Test("moveTrigger(id:before:) reorders by identity")
    func moveTriggerByID() {
        let manager = MenuBarItemTriggersManager(persistenceEnabled: false)
        let a = makeTrigger(named: "A", item: "item-a")
        let b = makeTrigger(named: "B", item: "item-b")
        let c = makeTrigger(named: "C", item: "item-c")
        manager.add(a)
        manager.add(b)
        manager.add(c)

        manager.moveTrigger(id: c.id, before: a.id)
        #expect(manager.triggers.map(\.name) == ["C", "A", "B"])

        // Unknown ids are no-ops.
        manager.moveTrigger(id: UUID(), before: a.id)
        manager.moveTrigger(id: a.id, before: UUID())
        #expect(manager.triggers.map(\.name) == ["C", "A", "B"])
    }

    // MARK: - Persistence

    @Test("Mutations persist and survive a reload")
    func mutationsPersistAndReload() throws {
        try withScratchDefaults { _ in
            Defaults.removeObject(forKey: .menuBarItemTriggers)
            let manager = MenuBarItemTriggersManager(persistenceEnabled: true)
            let first = makeTrigger(named: "First", item: "item-a")
            manager.add(first)

            var renamed = first
            renamed.name = "Renamed"
            manager.update(renamed)
            manager.add(makeTrigger(named: "Second", item: "item-b"))

            #expect(Defaults.data(forKey: .menuBarItemTriggers) != nil)

            let reloaded = MenuBarItemTriggersManager(persistenceEnabled: true)
            #expect(reloaded.triggers.count == 2)
            #expect(reloaded.triggers[0].name == "Renamed")
            #expect(reloaded.triggers[1].name == "Second")
        }
    }

    @Test("A persistence-disabled manager neither reads nor writes")
    func persistenceDisabledStaysClean() throws {
        try withScratchDefaults { _ in
            Defaults.removeObject(forKey: .menuBarItemTriggers)

            let manager = MenuBarItemTriggersManager(persistenceEnabled: false)
            manager.add(makeTrigger(named: "Ephemeral", item: "item-a"))
            manager.remove(atOffsets: IndexSet([0]))

            #expect(Defaults.data(forKey: .menuBarItemTriggers) == nil)
        }
    }

    @Test("A reload restores triggers persisted by an older build")
    func reloadRestoresPersistedTriggers() throws {
        try withScratchDefaults { _ in
            Defaults.removeObject(forKey: .menuBarItemTriggers)

            let persisted = makeTrigger(named: "Legacy", item: "item-a")
            let data = try! JSONEncoder().encode([persisted])
            Defaults.set(data, forKey: .menuBarItemTriggers)

            let reloaded = MenuBarItemTriggersManager(persistenceEnabled: true)
            #expect(reloaded.triggers.count == 1)
            #expect(reloaded.triggers[0].name == "Legacy")
            #expect(reloaded.controllingTrigger(forBaseIdentifier: "item-a") != nil)
        }
    }
}
