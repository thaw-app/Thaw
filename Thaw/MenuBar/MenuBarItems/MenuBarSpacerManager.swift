//
//  MenuBarSpacerManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import SwiftUI

// MARK: - MenuBarSpacerManager

/// Owns the user's spacer items: status items that only occupy width between
/// real items. Users position them like any other item.
@MainActor
@Observable
final class MenuBarSpacerManager {
    /// Not under `Thaw.ControlItem.`, which marks Thaw's immovable anchors.
    /// Spacers are ordinary items: draggable, reorderable, concealable.
    static nonisolated let autosavePrefix = "Thaw.Spacer."

    /// Whether a cached tag is a user-created spacer. Section-divider spacers
    /// are separate: they sit under a control-item identifier.
    static nonisolated func isSpacerTag(_ tag: MenuBarItemTag) -> Bool {
        tag.namespace == .thaw && tag.title.hasPrefix(autosavePrefix)
    }

    /// Whether one of the live spacer status items owns this window.
    ///
    /// Reliable right after creation, when the cached tag can still read as a
    /// generic "Item-0" until the title lands.
    func ownsWindowID(_ windowID: CGWindowID) -> Bool {
        statusItems.values.contains { item in
            guard
                let windowNumber = item.button?.window?.windowNumber,
                let ownedWindowID = MenuBarItemManager.windowServerID(
                    windowNumber: windowNumber
                )
            else {
                return false
            }
            return ownedWindowID == windowID
        }
    }

    private let diagLog = DiagLog(category: "MenuBarSpacerManager")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The user's spacers, in creation order. Persisted; the on-screen order
    /// is whatever the user drags them to, owned by AppKit's autosave.
    private(set) var spacers: [MenuBarSpacer] = []

    private var statusItems: [UUID: NSStatusItem] = [:]
    /// The spacer state each live status item was last configured with.
    private var applied: [UUID: MenuBarSpacer] = [:]

    func performSetup(with _: AppState) {
        loadInitialState()
        reconcileStatusItems()
    }

    private func loadInitialState() {
        guard let data = Defaults.data(forKey: .menuBarSpacers) else {
            return
        }
        do {
            spacers = try decoder.decode([MenuBarSpacer].self, from: data)
        } catch {
            diagLog.error("Error decoding spacers: \(error)")
        }
    }

    private func persist() {
        // Clear the key rather than store an empty array.
        guard !spacers.isEmpty else {
            Defaults.set(nil, forKey: .menuBarSpacers)
            return
        }
        do {
            try Defaults.set(encoder.encode(spacers), forKey: .menuBarSpacers)
        } catch {
            diagLog.error("Error encoding spacers: \(error)")
        }
    }

    // MARK: Mutations

    func addSpacer() {
        spacers.append(MenuBarSpacer())
        persist()
        reconcileStatusItems()
    }

    func removeSpacer(id: UUID) {
        spacers.removeAll { $0.id == id }
        persist()
        reconcileStatusItems()
    }

    func setWidth(_ width: CGFloat, for id: UUID) {
        guard let index = spacers.firstIndex(where: { $0.id == id }) else {
            return
        }
        spacers[index].width = width.clamped(to: MenuBarSpacer.minWidth ... MenuBarSpacer.maxWidth)
        persist()
        reconcileStatusItems()
    }

    func setColor(_ cgColor: CGColor?, for id: UUID) {
        guard let index = spacers.firstIndex(where: { $0.id == id }) else {
            return
        }
        spacers[index].color = cgColor.map { IceColor(cgColor: $0) }
        persist()
        reconcileStatusItems()
    }

    // MARK: Status Items

    private static func autosaveName(for id: UUID) -> String {
        autosavePrefix + id.uuidString
    }

    /// The button needs a real image even when transparent; a contentless
    /// button is composited as nothing.
    private static func spacerImage(width: CGFloat, color: IceColor?) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: 16), flipped: false) { rect in
            if let color, let fill = NSColor(cgColor: color.cgColor) {
                fill.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func assertWindowTitle(for id: UUID, attempt: Int) {
        guard let item = statusItems[id] else {
            return
        }
        let name = Self.autosaveName(for: id)
        if let window = item.button?.window {
            window.title = name
        } else if attempt < 20 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.assertWindowTitle(for: id, attempt: attempt + 1)
            }
        } else {
            diagLog.warning("Spacer \(id) never produced a button window; title not set")
        }
    }

    private func reconcileStatusItems() {
        // Also clear autosave leftovers so removed spacers can't affect layout.
        let wanted = Set(spacers.map(\.id))
        for (id, item) in statusItems where !wanted.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems[id] = nil
            applied[id] = nil
            let name = Self.autosaveName(for: id)
            ControlItemDefaults[.preferredPosition, name] = nil
            UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible \(name)")
            UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC \(name)")
            diagLog.info("Removed spacer \(id)")
        }

        for spacer in spacers {
            if let item = statusItems[spacer.id] {
                if applied[spacer.id] != spacer {
                    item.length = spacer.width
                    item.button?.image = Self.spacerImage(width: spacer.width, color: spacer.color)
                    applied[spacer.id] = spacer
                }
                continue
            }

            let name = Self.autosaveName(for: spacer.id)

            // Seed new spacers just left of the Thaw icon so they are never
            // born concealed, and set both visibility switches first.
            if ControlItemDefaults[.preferredPosition, name] == nil {
                let thawIconPosition: CGFloat =
                    ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] ?? 0
                ControlItemDefaults[.preferredPosition, name] = max(thawIconPosition - 1, 0)
            }
            UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(name)")
            UserDefaults.standard.set(true, forKey: "NSStatusItem VisibleCC \(name)")

            let item = NSStatusBar.system.statusItem(withLength: spacer.width)
            item.autosaveName = name
            item.button?.image = Self.spacerImage(width: spacer.width, color: spacer.color)
            item.button?.imageScaling = .scaleNone
            item.button?.toolTip = String(localized: "\(Constants.displayName) spacer")
            statusItems[spacer.id] = item
            // The button window often doesn't exist yet, and without a title
            // the cache tags the spacer as "Item-0". Retry until it's up.
            assertWindowTitle(for: spacer.id, attempt: 0)
            applied[spacer.id] = spacer
            diagLog.info("Created spacer \(spacer.id), width=\(Int(spacer.width))pt")
        }
    }
}
