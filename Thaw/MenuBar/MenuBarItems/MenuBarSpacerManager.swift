//
//  MenuBarSpacerManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import SwiftUI

// MARK: - MenuBarSpacer

/// One user-created spacer item.
nonisolated struct MenuBarSpacer: Codable, Identifiable, Equatable {
    /// The narrowest useful spacer; anything below reads as a normal gap.
    static let minWidth: CGFloat = 8
    /// Wide enough to push items past a notch without being a footgun.
    static let maxWidth: CGFloat = 300
    /// A visible, obviously-intentional default gap.
    static let defaultWidth: CGFloat = 40

    let id: UUID
    var width: CGFloat
    /// Optional fill; `nil` renders the spacer as a fully transparent gap.
    var color: IceColor?

    init(id: UUID = UUID(), width: CGFloat = Self.defaultWidth, color: IceColor? = nil) {
        self.id = id
        self.width = width.clamped(to: Self.minWidth ... Self.maxWidth)
        self.color = color
    }

    /// Decodes through the memberwise initializer so the clamp applies to
    /// persisted widths too. A synthesized `init(from:)` assigns `width`
    /// directly, and a downgrade from a build with a larger `maxWidth` reads
    /// back a value wide enough to push other items off the bar.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            width: container.decode(CGFloat.self, forKey: .width),
            color: container.decodeIfPresent(IceColor.self, forKey: .color)
        )
    }
}

// MARK: - MenuBarSpacerManager

/// Owns the user's spacer items: synthetic status items whose only job is
/// occupying width between real items. Users position them like any other
/// item (⌘-drag in the menu bar or via the layout editor).
///
/// The status-item mechanics — the autosave prefix that keeps spacers outside
/// Thaw's own concealment, the two `NSStatusItem Visible*` defaults, and the
/// requirement that the button carry a real image to be composited — are the
/// ones the section-divider spacers validated.
@MainActor
@Observable
final class MenuBarSpacerManager {
    /// Deliberately NOT under `Thaw.ControlItem.` — that prefix marks Thaw's
    /// immovable anchors (never drag sources, special-cased right-click).
    /// Spacers are ordinary items: draggable, reorderable, concealable.
    static nonisolated let autosavePrefix = "Thaw.Spacer."

    /// Whether a cached item tag belongs to one of Thaw's user-created
    /// spacers, so capture consumers (layout editor, search) can identify
    /// them. Distinct from the section-divider spacers, whose autosave names
    /// sit under a control-item identifier and end in `.Spacer.<index>`.
    static nonisolated func isSpacerTag(_ tag: MenuBarItemTag) -> Bool {
        tag.namespace == .thaw && tag.title.hasPrefix(autosavePrefix)
    }

    /// Whether one of the live spacer status items owns this window.
    ///
    /// Identification by window is the reliable path right after creation:
    /// the button window (and thus the cached tag's title) can lag behind,
    /// leaving the tag a generic "Item-0" until the title lands.
    func ownsWindowID(_ windowID: CGWindowID) -> Bool {
        statusItems.values.contains { item in
            guard let windowNumber = item.button?.window?.windowNumber, windowNumber > 0 else {
                return false
            }
            return CGWindowID(windowNumber) == windowID
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
        // An empty set is the default, so clear the key rather than storing
        // an empty array — keeps `defaults read` output honest.
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

    /// A slab at the requested width — transparent when no color is set.
    /// The button must carry a real image either way; a contentless button is
    /// composited as nothing.
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
        // Drop items whose spacer is gone, and clean up the autosave litter
        // so removed spacers can't influence future layout.
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

            // Seed new spacers just left of the Thaw icon — inside the visible
            // region, so a freshly added spacer is never born into a concealed
            // slot — and assert both visibility switches before creation.
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
            // The button window often doesn't exist yet at creation time;
            // without the title, the item cache tags the spacer as a generic
            // "Item-0" and can't identify it. Retry until the window is up.
            assertWindowTitle(for: spacer.id, attempt: 0)
            applied[spacer.id] = spacer
            diagLog.info("Created spacer \(spacer.id), width=\(Int(spacer.width))pt")
        }
    }
}
