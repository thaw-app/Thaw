//
//  MenuBarSpacerManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel
import ThawUI

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
    /// Optional fill; nil renders the spacer as a fully transparent gap.
    var color: ThawColor?

    init(id: UUID = UUID(), width: CGFloat = Self.defaultWidth, color: ThawColor? = nil) {
        self.id = id
        self.width = width.clamped(to: Self.minWidth ... Self.maxWidth)
        self.color = color
    }
}

// MARK: - MenuBarSpacerManager

/// User-positioned gap status items support command-drag and layout-editor moves.
/// macOS 27 requires both NSStatusItem visibility defaults and a real button image for compositing.
@MainActor
@Observable
final class MenuBarSpacerManager {
    /// Avoid "Thaw.ControlItem.", which marks immovable, section-excluded anchors with special right-click handling.
    static nonisolated let autosavePrefix = "Thaw.Spacer."

    /// Migrate this prefix because it identifies spacers as immovable controls.
    private static nonisolated let legacyAutosavePrefix = "Thaw.ControlItem.Spacer."

    /// Whether a cached item tag belongs to one of Thaw's spacers, so
    /// capture consumers (layout editor, search) can identify them.
    static nonisolated func isSpacerTag(_ tag: MenuBarItemTag) -> Bool {
        tag.title.hasPrefix(autosavePrefix)
    }

    /// Match by window while delayed button-window titles leave cached tags as generic "Item-0".
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

    /// Persisted in creation order; AppKit autosave owns user-arranged on-screen order.
    /// loadInitialState() is an ordinary method, so launch restore fires didSet and harmlessly rewrites loaded data.
    private(set) var spacers: [MenuBarSpacer] = [] {
        didSet {
            guard oldValue != spacers else { return }
            do {
                let data = try encoder.encode(spacers)
                Defaults.set(data, forKey: .menuBarSpacers)
                lastPersistenceFailure = nil
            } catch {
                diagLog.error("Error encoding spacers: \(error)")
                lastPersistenceFailure = error.localizedDescription
            }
        }
    }

    /// Exposes didSet write failures to the Layout pane because didSet cannot throw.
    /// Otherwise a visible but unsaved spacer would silently disappear on relaunch; nil means storage is current.
    private(set) var lastPersistenceFailure: String?

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

    // MARK: Mutations

    func addSpacer() {
        spacers.append(MenuBarSpacer())
        reconcileStatusItems()
    }

    func removeSpacer(id: UUID) {
        spacers.removeAll { $0.id == id }
        reconcileStatusItems()
    }

    func setWidth(_ width: CGFloat, for id: UUID) {
        guard let index = spacers.firstIndex(where: { $0.id == id }) else {
            return
        }
        spacers[index].width = width.clamped(to: MenuBarSpacer.minWidth ... MenuBarSpacer.maxWidth)
        reconcileStatusItems()
    }

    func setColor(_ cgColor: CGColor?, for id: UUID) {
        guard let index = spacers.firstIndex(where: { $0.id == id }) else {
            return
        }
        spacers[index].color = cgColor.map { ThawColor(cgColor: $0) }
        reconcileStatusItems()
    }

    // MARK: Status Items

    private static func autosaveName(for id: UUID) -> String {
        autosavePrefix + id.uuidString
    }

    /// macOS 27 requires a real image even for transparent gaps; contentless buttons are not composited.
    private static func spacerImage(width: CGFloat, color: ThawColor?) -> NSImage {
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
            // Migrate any state saved under the legacy control-item prefix.
            let legacyName = Self.legacyAutosavePrefix + spacer.id.uuidString
            if ControlItemDefaults[.preferredPosition, name] == nil,
               let legacyPosition: CGFloat = ControlItemDefaults[.preferredPosition, legacyName]
            {
                ControlItemDefaults[.preferredPosition, name] = legacyPosition
                ControlItemDefaults[.preferredPosition, legacyName] = nil
            }
            UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible \(legacyName)")
            UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC \(legacyName)")

            // Seed right of the Thaw icon to avoid concealed slots; assert both visibility channels before macOS 27 creation.
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
            // Set AX identity so preferred-position moves can verify the spacer instead of a generic "Item-0".
            item.button?.setAccessibilityIdentifier(name)
            statusItems[spacer.id] = item
            // Retry delayed button-window creation; its title prevents generic "Item-0" cache identities.
            assertWindowTitle(for: spacer.id, attempt: 0)
            applied[spacer.id] = spacer
            diagLog.info("Created spacer \(spacer.id), width=\(Int(spacer.width))pt")
        }
    }
}
