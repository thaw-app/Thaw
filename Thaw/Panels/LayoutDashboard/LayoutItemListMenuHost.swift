//
//  LayoutItemListMenuHost.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// The AppKit view behind a list row: a right click shows the bars' own menu for that row,
/// and Return pops the same menu from it. Menus are NSMenus, which SwiftUI can't host.
struct LayoutItemListMenuHost: NSViewRepresentable {
    let rowID: String
    let anchors: LayoutItemListAnchors
    let makeMenu: @MainActor () -> NSMenu?

    func makeNSView(context _: Context) -> MenuView {
        let view = MenuView()
        update(view)
        return view
    }

    func updateNSView(_ view: MenuView, context _: Context) {
        update(view)
    }

    private func update(_ view: MenuView) {
        view.makeMenu = makeMenu
        anchors.register(view, for: rowID)
    }

    final class MenuView: NSView {
        var makeMenu: (@MainActor () -> NSMenu?)?

        override func menu(for _: NSEvent) -> NSMenu? {
            makeMenu?()
        }

        /// Clicks pass to the SwiftUI row; only the right click's menu comes from here.
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
        }

        func popUpMenu() {
            guard let menu = makeMenu?() else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        }
    }
}

/// The rows' menu views by row, so Return can open the focused row's menu.
@MainActor
final class LayoutItemListAnchors {
    private var views = [String: WeakView]()

    private struct WeakView {
        weak var view: LayoutItemListMenuHost.MenuView?
    }

    func register(_ view: LayoutItemListMenuHost.MenuView, for rowID: String) {
        views[rowID] = WeakView(view: view)
        if views.count > 512 {
            views = views.filter { $0.value.view != nil }
        }
    }

    func popUpMenu(for rowID: String) {
        views[rowID]?.view?.popUpMenu()
    }
}
