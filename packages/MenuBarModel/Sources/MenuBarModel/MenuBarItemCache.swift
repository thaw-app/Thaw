//
//  MenuBarItemCache.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Shared cache for backends that must not depend on the app's orchestrator.
public struct MenuBarItemCache: Hashable, MenuBarSectionBucketed, Sendable {
    private var storage = [MenuBarSectionName: [MenuBarItem]]()

    /// The display with the active menu bar when this cache was created.
    public let displayID: CGDirectDisplayID?

    public var managedItems: [MenuBarItem] {
        MenuBarSectionName.allCases.reduce(into: []) { result, section in
            guard let items = storage[section] else {
                return
            }
            result.append(contentsOf: items)
        }
    }

    /// Checks buckets without allocating the flattened array on each SwiftUI pass.
    public var isEmpty: Bool {
        storage.values.allSatisfy(\.isEmpty)
    }

    public init(displayID: CGDirectDisplayID?) {
        self.displayID = displayID
    }

    public func managedItems(for section: MenuBarSectionName) -> [MenuBarItem] {
        self[section]
    }

    /// Searches in managedItems order without allocating the flattened inventory.
    public func item(withTag tag: MenuBarItemTag) -> MenuBarItem? {
        for section in MenuBarSectionName.allCases {
            if let item = storage[section]?.first(matching: tag) {
                return item
            }
        }
        return nil
    }

    /// Searches in the same section order as item(withTag:).
    public func item(withWindowID windowID: CGWindowID) -> MenuBarItem? {
        for section in MenuBarSectionName.allCases {
            if let item = storage[section]?.first(where: { $0.windowID == windowID }) {
                return item
            }
        }
        return nil
    }

    public subscript(section: MenuBarSectionName) -> [MenuBarItem] {
        get { storage[section, default: []] }
        set { storage[section] = newValue }
    }
}

/// Control items shared with backends that must not depend on the app's orchestrator.
public struct ControlItemPair: Sendable {
    public let hidden: MenuBarItem
    public let alwaysHidden: MenuBarItem?

    /// Accepts resolved controls; live discovery uses the failable initializer.
    public init(hidden: MenuBarItem, alwaysHidden: MenuBarItem?) {
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
    }

    /// Resolves controls by tag, then process PID and title, then known window IDs.
    /// On macOS 26, Control Center owns item windows and kCGWindowName may differ from NSStatusItem autosaveName.
    public init?(
        items: inout [MenuBarItem],
        hiddenControlItemWindowID: CGWindowID? = nil,
        alwaysHiddenControlItemWindowID: CGWindowID? = nil
    ) {
        if let hidden = items.removeFirst(matching: .hiddenControlItem) {
            self.hidden = hidden
            self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
            return
        }

        let ourPID = ProcessInfo.processInfo.processIdentifier
        let hiddenTitle = ControlItemIdentifier.hidden.rawValue
        let alwaysHiddenTitle = ControlItemIdentifier.alwaysHidden.rawValue

        if let idx = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == hiddenTitle }) {
            self.hidden = items.remove(at: idx)
            if let ahIdx = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == alwaysHiddenTitle }) {
                self.alwaysHidden = items.remove(at: ahIdx)
            } else {
                self.alwaysHidden = nil
            }
            return
        }

        // Use ControlItem window IDs when both tags and titles are unreliable on macOS 26.
        if let hiddenWID = hiddenControlItemWindowID,
           let idx = items.firstIndex(where: { $0.windowID == hiddenWID })
        {
            self.hidden = items.remove(at: idx)
            if let ahWID = alwaysHiddenControlItemWindowID,
               let ahIdx = items.firstIndex(where: { $0.windowID == ahWID })
            {
                self.alwaysHidden = items.remove(at: ahIdx)
            } else {
                self.alwaysHidden = nil
            }
            return
        }

        return nil
    }
}
