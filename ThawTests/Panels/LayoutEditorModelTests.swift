//
//  LayoutEditorModelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// An app state whose item cache holds items owned by the test process, so they count as running.
@MainActor
struct LayoutEditorWorld {
    let appState = AppState()
    private static var nextWindowID: CGWindowID = 9000

    static func item(_ tag: MenuBarItemTag, ownerPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> MenuBarItem {
        nextWindowID += 1
        return MenuBarItem(
            tag: tag,
            windowID: nextWindowID,
            ownerPID: ownerPID,
            sourcePID: ownerPID,
            bounds: CGRect(x: CGFloat(nextWindowID), y: 0, width: 24, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }

    static func item(_ title: String) -> MenuBarItem {
        item(MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0))
    }

    func seat(_ items: [MenuBarItem], in section: MenuBarSection.Name = .visible) {
        appState.itemManager.itemCache[section] = items
    }
}

@MainActor
@Suite(.serialized)
struct LayoutEditorModelTests {
    private typealias World = LayoutEditorWorld

    /// Records what the model hands to the commit step instead of touching the menu bar.
    @MainActor
    private final class Commits {
        var drops = [LayoutDropCommit.Drop]()
        var finish: (@MainActor () -> Void)?

        func model(for world: World) -> LayoutEditorModel {
            LayoutEditorModel(appState: world.appState) { [self] drop, _, finished in
                drops.append(drop)
                finish = finished
            }
        }
    }

    private func ids(_ model: LayoutEditorModel, _ section: MenuBarSection.Name = .visible) -> [String] {
        (model.units[section] ?? []).map(\.id)
    }

    @Test
    func aRefreshShowsTheSeatedItemsWithoutTheSectionDividers() {
        let world = World()
        let first = World.item("First")
        let second = World.item("Second")
        world.seat([first, World.item(.hiddenControlItem), second])
        let model = LayoutEditorModel(appState: world.appState)

        model.refresh()

        #expect(ids(model) == [first.uniqueIdentifier, second.uniqueIdentifier])
        #expect(model.units[.visible]?.first.map(model.items(of:)) == [first])
        #expect(model.sections.contains(.visible))
    }

    @Test
    func aDropInsideASectionShowsAtOnceAndIsHandedToTheCommit() throws {
        let world = World()
        let items = ["A", "B", "C"].map(World.item)
        world.seat(items)
        let commits = Commits()
        let model = commits.model(for: world)
        model.refresh()

        model.move(items[2].uniqueIdentifier, to: .visible, before: items[0].uniqueIdentifier, undoManager: nil)

        let expected = [items[2], items[0], items[1]]
        #expect(ids(model) == expected.map(\.uniqueIdentifier))
        let drop = try #require(commits.drops.first)
        #expect(drop.items == [items[2]])
        #expect(drop.source == .visible)
        #expect(drop.target == .visible)
        #expect(drop.previousTargetOrder == items)
        #expect(drop.targetOrder == expected)
    }

    @Test
    func theDroppedOrderIsKeptWhileTheBarStillReportsTheOldOne() throws {
        let world = World()
        let items = ["A", "B", "C"].map(World.item)
        world.seat(items)
        let commits = Commits()
        let model = commits.model(for: world)
        model.refresh()
        model.move(items[2].uniqueIdentifier, to: .visible, before: items[0].uniqueIdentifier, undoManager: nil)

        let finish = try #require(commits.finish)
        finish()

        #expect(ids(model) == [items[2], items[0], items[1]].map(\.uniqueIdentifier))
    }

    @Test
    func theDroppedOrderIsLetGoOnceTheItemsChange() throws {
        let world = World()
        let items = ["A", "B", "C"].map(World.item)
        world.seat(items)
        let commits = Commits()
        let model = commits.model(for: world)
        model.refresh()
        model.move(items[2].uniqueIdentifier, to: .visible, before: items[0].uniqueIdentifier, undoManager: nil)

        world.seat([items[0], items[1]])
        model.refresh()

        #expect(ids(model) == [items[0], items[1]].map(\.uniqueIdentifier))
    }

    @Test
    func anItemReadTwiceGetsOneRowAndSurvivesADrop() {
        let world = World()
        let first = World.item("First")
        let second = World.item("Second")
        world.seat([first, second, World.item(first.tag)])
        let commits = Commits()
        let model = commits.model(for: world)
        model.refresh()
        #expect(ids(model) == [first.uniqueIdentifier, second.uniqueIdentifier])

        model.move(second.uniqueIdentifier, to: .visible, before: first.uniqueIdentifier, undoManager: nil)
        model.refresh()

        #expect(ids(model) == [second.uniqueIdentifier, first.uniqueIdentifier])
        #expect(commits.drops.first?.targetOrder == [second, first])
    }

    @Test
    func aDropOfAnUnknownUnitChangesNothing() {
        let world = World()
        let items = ["A", "B"].map(World.item)
        world.seat(items)
        let commits = Commits()
        let model = commits.model(for: world)
        model.refresh()

        model.move("missing", to: .visible, before: nil, undoManager: nil)

        #expect(ids(model) == items.map(\.uniqueIdentifier))
        #expect(commits.drops.isEmpty)
    }

    @Test
    func aRefusedDropLeavesTheRowsAlone() {
        let world = World()
        let thaw = World.item(.visibleControlItem)
        let other = World.item("Other")
        world.seat([other, thaw])
        let commits = Commits()
        let model = commits.model(for: world)
        model.refresh()

        model.move(thaw.uniqueIdentifier, to: .hidden, before: nil, undoManager: nil)

        #expect(ids(model) == [other.uniqueIdentifier, thaw.uniqueIdentifier])
        #expect(commits.drops.isEmpty)
        #expect(world.appState.layoutFeedback.refusal != nil)
    }

    @Test
    func aStartedModelFollowsTheItemCacheUntilItIsStopped() async {
        let world = World()
        let first = World.item("First")
        world.seat([first])
        let model = LayoutEditorModel(appState: world.appState)
        model.start()
        model.start()
        #expect(ids(model) == [first.uniqueIdentifier])

        let second = World.item("Second")
        world.seat([first, second])
        for _ in 0 ..< 200 where ids(model).count < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(ids(model) == [first.uniqueIdentifier, second.uniqueIdentifier])

        model.stop()
        world.seat([first])
        try? await Task.sleep(for: .milliseconds(100))
        #expect(ids(model).count == 2)
    }
}
