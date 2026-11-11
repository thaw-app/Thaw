//
//  OutOfRoomWarningTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("The Layout warning while macOS has no room for items", .serialized, .scratchDefaults)
struct OutOfRoomWarningTests {
    private static let size = CGSize(width: 560, height: 120)

    @Test("The message names the items when Thaw knows them")
    func message() {
        let unnamed = String(localized: OutOfRoomWarning.message(naming: []))
        let named = String(localized: OutOfRoomWarning.message(naming: ["Alpha", "Beta"]))
        #expect(!unnamed.contains("including"))
        #expect(named.contains("Alpha"))
        #expect(named.contains("Beta"))
    }

    @Test("Draws, and draws differently when it names items")
    func draws() throws {
        let plain = OffscreenRender(OutOfRoomWarning(hiddenItemNames: []).frame(width: Self.size.width), size: Self.size)
        let named = OffscreenRender(
            OutOfRoomWarning(hiddenItemNames: ["Alpha", "Beta"]).frame(width: Self.size.width),
            size: Self.size
        )
        let plainPixels = try plain.pixels()
        #expect(plainPixels.contains { $0 != 0 })
        #expect(try named.pixels() != plainPixels)
    }

    @Test("Move to Hidden shows only when the warning names items and the pane can move them")
    func offersMoveToHidden() async throws {
        #expect(!OutOfRoomWarning.offersMove(namedItems: [], canMove: true))
        #expect(!OutOfRoomWarning.offersMove(namedItems: ["Alpha"], canMove: false))
        #expect(OutOfRoomWarning.offersMove(namedItems: ["Alpha"], canMove: true))

        let appState = AppState()
        let bare = OffscreenRender(OutOfRoomWarning(hiddenItemNames: ["Alpha"]).frame(width: Self.size.width), size: Self.size)
        let withAction = OffscreenRender(
            OutOfRoomWarning(hiddenItemNames: ["Alpha"]).frame(width: Self.size.width).environment(appState),
            size: Self.size
        )
        let barePixels = try bare.pixels()
        await withAction.settle { (try? withAction.pixels()) != barePixels }
        #expect(try withAction.pixels() != barePixels, "the button is drawn")
        // No item is out of room in a fresh state, so the move has nothing to do.
        OutOfRoomWarning.moveNotDrawnItemsToHidden(appState: appState)
    }

    @Test("The watcher reports overflow on the bars' display, with the names, and clears when it ends")
    func watcherFollowsOverflow() async {
        let display = CGMainDisplayID()
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.Alpha"), title: "Alpha", instanceIndex: 0),
            windowID: 1,
            ownerPID: 999_999,
            sourcePID: 999_999,
            bounds: CGRect(x: 100, y: 3, width: 24, height: 24),
            title: "Alpha",
            isOnScreen: true
        )
        var cache = MenuBarItemCache(displayID: display)
        cache[.visible] = [item]
        let manager = MenuBarItemManager()
        manager.itemCache = cache
        manager.itemsNotShownOnBarTags = [item.tag]
        let presence = NativeOverflowPresence()

        var reported: (isOutOfRoom: Bool, names: [String]) = (true, ["stale"])
        let render = OffscreenRender(
            Color.clear.modifier(OutOfRoomSync(itemManager: manager, presence: presence) { reported = ($0, $1) }),
            size: Self.size
        )
        await render.settle { !reported.isOutOfRoom }
        #expect(!reported.isOutOfRoom)
        #expect(reported.names.isEmpty)

        presence.refresh(displays: [display]) { _ in true }
        await render.settle { reported.isOutOfRoom }
        #expect(reported.isOutOfRoom)
        #expect(reported.names == ["Alpha"])

        manager.itemsNotShownOnBarTags = []
        await render.settle { reported.names.isEmpty }
        #expect(reported.isOutOfRoom)
        #expect(reported.names.isEmpty)

        presence.refresh(displays: [display]) { _ in false }
        await render.settle { !reported.isOutOfRoom }
        #expect(!reported.isOutOfRoom)
    }
}
