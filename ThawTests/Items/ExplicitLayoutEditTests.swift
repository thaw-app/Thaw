//
//  ExplicitLayoutEditTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// Manual arrangement moves an item only for an edit the user made in Layout.
/// These pin the decision and the task scoping that keeps automatic passes out.
@Suite("Explicit Layout edits")
struct ExplicitLayoutEditTests {
    private static let allReasons: [LayoutChangeReason] = [
        .externalChange, .userReorder, .profileApply, .revealRestore, .settingChange, .arrivalRestore,
    ]

    @Test("Only the user's reorder may move items in Manual", arguments: allReasons)
    func onlyUserReorderMovesInManual(reason: LayoutChangeReason) {
        #expect(reason.permitsMoveInManualArrangement == (reason == .userReorder))
    }

    @Test("A single move is refused in Manual unless an explicit edit asks for it")
    func singleMoveDecision() {
        #expect(ExplicitLayoutEdit.manualArrangementForbidsMoves(arrangementIsManual: true, isExplicitLayoutEdit: false))
        #expect(!ExplicitLayoutEdit.manualArrangementForbidsMoves(arrangementIsManual: true, isExplicitLayoutEdit: true))
        #expect(!ExplicitLayoutEdit.manualArrangementForbidsMoves(arrangementIsManual: false, isExplicitLayoutEdit: false))
        #expect(!ExplicitLayoutEdit.manualArrangementForbidsMoves(arrangementIsManual: false, isExplicitLayoutEdit: true))
    }

    @Test("A section-order pass needs both the mark and the user's reason in Manual", arguments: allReasons)
    func sectionOrderDecision(reason: LayoutChangeReason) {
        let marked = ExplicitLayoutEdit.manualArrangementForbids(
            arrangementIsManual: true,
            isExplicitLayoutEdit: true,
            reason: reason
        )
        #expect(marked == (reason != .userReorder))
        #expect(
            ExplicitLayoutEdit.manualArrangementForbids(
                arrangementIsManual: true,
                isExplicitLayoutEdit: false,
                reason: reason
            )
        )
        #expect(
            !ExplicitLayoutEdit.manualArrangementForbids(
                arrangementIsManual: false,
                isExplicitLayoutEdit: false,
                reason: reason
            )
        )
    }

    @Test("The mark is off unless an edit is being performed")
    func markIsOffByDefault() {
        #expect(!ExplicitLayoutEdit.isActive)
        let inside = ExplicitLayoutEdit.perform { ExplicitLayoutEdit.isActive }
        #expect(inside)
        #expect(!ExplicitLayoutEdit.isActive)
    }

    @Test("A task started by the edit inherits the mark; a detached one and a sibling do not")
    func markFollowsTheTaskTree() async {
        let (child, detached) = ExplicitLayoutEdit.perform {
            (
                Task { ExplicitLayoutEdit.isActive },
                Task.detached { ExplicitLayoutEdit.isActive }
            )
        }
        let sibling = Task { ExplicitLayoutEdit.isActive }
        #expect(await child.value)
        #expect(await !detached.value)
        #expect(await !sibling.value)
    }

    @Test("The mark survives a suspension and a nested task, as the debounced apply needs")
    func markSurvivesSuspensionAndNesting() async {
        let outer = ExplicitLayoutEdit.perform {
            Task {
                try? await Task.sleep(for: .milliseconds(5))
                return await Task { ExplicitLayoutEdit.isActive }.value
            }
        }
        #expect(await outer.value)
    }

    @Test("Clearing the mark, as a cache pass does, hides it from the work inside")
    func markCanBeClearedForAutomaticWork() async {
        let inside = ExplicitLayoutEdit.perform {
            Task {
                await ExplicitLayoutEdit.$isActive.withValue(false) {
                    await Task { ExplicitLayoutEdit.isActive }.value
                }
            }
        }
        #expect(await !inside.value)
    }

    @MainActor
    @Test("The Layout-edit store follows the mark only in Manual")
    func layoutEditStoreFollowsTheMark() {
        let key = Defaults.Key.menuBarArrangementMode
        let saved = Defaults.integer(forKey: key)
        defer { Defaults.set(saved, forKey: key) }

        Defaults.set(MenuBarArrangementMode.manual.rawValue, forKey: key)
        #expect(MenuBarPositionStoreProvider.current is ReadOnlyPositionStore)
        #expect(MenuBarPositionStoreProvider.forLayoutEdit is ReadOnlyPositionStore)
        let insideEdit = ExplicitLayoutEdit.perform {
            (
                MenuBarPositionStoreProvider.forLayoutEdit is ReadOnlyPositionStore,
                MenuBarPositionStoreProvider.current is ReadOnlyPositionStore
            )
        }
        #expect(!insideEdit.0)
        #expect(insideEdit.1)

        Defaults.set(MenuBarArrangementMode.automatic.rawValue, forKey: key)
        #expect(!(MenuBarPositionStoreProvider.forLayoutEdit is ReadOnlyPositionStore))
    }
}
