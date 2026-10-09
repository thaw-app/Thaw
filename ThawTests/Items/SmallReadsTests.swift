//
//  SmallReadsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Short reads that each answer one question about the bar or the running apps.
@MainActor
struct SmallReadsTests {
    private func item(_ name: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(name)"), title: "Item-0", instanceIndex: 0),
            windowID: 1, ownerPID: 100, sourcePID: 200,
            bounds: CGRect(x: 100, y: 3, width: 24, height: 24), title: name, isOnScreen: true
        )
    }

    @Test
    func `a stored weight is found by the item's own row, and a missing row gives none`() {
        let known = item("known"), unknown = item("unknown")
        let table = StoredWeights.Table(isAvailable: true, positions: ["status:com.example.known::Item-0": 120])
        let weights = StoredWeights(among: [known, unknown], table: table)

        #expect(weights.isAvailable)
        #expect(weights.weight(of: known) == 120)
        #expect(weights.weight(of: unknown) == nil)
    }

    @Test
    func `an unreadable table gives no weights`() {
        let known = item("known")
        let weights = StoredWeights(among: [known], table: .init(isAvailable: false, positions: [:]))
        #expect(!weights.isAvailable)
        #expect(weights.weight(of: known) == nil)
    }

    @Test
    func `an ordinary weight is not a parked one`() {
        let weights = StoredWeights(among: [], table: .init(isAvailable: true, positions: [:]))
        #expect(!weights.isParked(120))
    }

    @Test
    func `the process table read lists this process, with its bundle`() throws {
        let snapshot = RunningApplicationSnapshot.readSystem()
        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(snapshot.processIDs.contains(pid))
        let bundle = try #require(Bundle.main.bundleIdentifier)
        #expect(snapshot.bundleIdentifiers.contains(bundle))
        #expect(snapshot.bundleIdentifiersByPID[pid] == bundle)
        #expect(Set(snapshot.bundleIdentifiersByPID.keys).isSubset(of: snapshot.processIDs))
    }

    @Test
    func `this process is not one of the stand-ins, so it is kept`() {
        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(SystemExtraStandIn.removingStandIns(from: [pid]) == [pid])
        #expect(SystemExtraStandIn.removingStandIns(from: []).isEmpty)
    }

    @Test
    func `apps the Control Center list has switched off are a subset of those asked about`() {
        #expect(MenuBarAllowState.switchedOff(among: []).isEmpty)
        let asked: Set = ["com.example.never-installed"]
        #expect(MenuBarAllowState.switchedOff(among: asked).isSubset(of: asked))
    }

    @Test
    func `the pinned Control Center limit explains itself`() {
        let texts = [LayoutBarVisibilityLimit.cannotShow, .pinnedModuleCannotShow, .cannotHide].map(\.explanation)
        #expect(Set(texts).count == 3)
        #expect(LayoutBarVisibilityLimit.pinnedModuleCannotShow.explanation.contains("Control Center"))
    }

    @Test
    func `only expected hosts that are running and unseen are worth asking about`() {
        let hosts = UnseenMenuBarHosts(expected: ["com.example.a": 0, "com.example.b": 0, "com.example.c": 0])
        let candidates = hosts.candidates(seen: ["com.example.a"], running: ["com.example.a", "com.example.b", "com.example.z"])
        #expect(candidates == ["com.example.b"])
    }
}
