//
//  GroupFolders.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation

/// Folder groups move members to Hidden and open them in a dedicated Thaw Bar; their Thaw-owned icons cannot hide individually.
/// Folder state stays outside MenuBarItemGroup to preserve the prebuilt runtime kit's layout.
@MainActor
@Observable
final class GroupFolders {
    struct Style: Equatable {
        static let defaultSymbol = "folder"

        /// Public SF Symbols legible at menu bar size, with folder-like shapes first.
        static let symbols = [
            "folder", "folder.fill", "tray.full", "archivebox", "shippingbox",
            "briefcase", "bag", "star", "heart", "bolt", "flag", "tag",
            "bookmark", "bell", "gearshape", "hammer", "paintbrush", "music.note",
            "gamecontroller", "cloud", "leaf", "circle.grid.2x2", "square.stack",
        ]

        var symbol = defaultSymbol
        /// nil draws the icon as a template, in the menu bar's own color.
        var color: NSColor?
    }

    /// Thaw.Proxy. excludes folder icons from new-item relocation and search.
    static nonisolated let autosavePrefix = ThawBarOnlyProxies.autosavePrefix + "Folder."
    /// Autosave name to the folder's name, readable off the main actor for
    /// MenuBarItem.displayName.
    static nonisolated let labelsKey = "MenuBarItemGroupManager.folderLabels"
    private static let foldersKey = "MenuBarItemGroupManager.folderGroups"

    private static let stylesKey = "MenuBarItemGroupManager.folderStyles"

    @ObservationIgnored private let diagLog = DiagLog(category: "GroupFolders")
    @ObservationIgnored private weak var appState: AppState?
    private var folderIDs: Set<UUID>
    private var styles: [UUID: Style]
    @ObservationIgnored private var statusItems: [UUID: NSStatusItem] = [:]
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.foldersKey) ?? []
        folderIDs = Set(stored.compactMap(UUID.init(uuidString:)))
        styles = Self.loadStyles()
    }

    func style(for id: UUID) -> Style {
        styles[id] ?? Style()
    }

    func setStyle(_ style: Style, for id: UUID) {
        styles[id] = style == Style() ? nil : style
        persist()
        applyStyle(to: id)
    }

    private static func loadStyles() -> [UUID: Style] {
        let stored = UserDefaults.standard.dictionary(forKey: stylesKey) as? [String: [String: String]] ?? [:]
        var styles: [UUID: Style] = [:]
        for (key, entry) in stored {
            guard let id = UUID(uuidString: key) else { continue }
            styles[id] = Style(
                symbol: entry["symbol"] ?? Style.defaultSymbol,
                color: entry["color"].flatMap(NSColor.init(hexString:))
            )
        }
        return styles
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        observationTask = Task { @MainActor [weak self, groupManager = appState.itemGroupManager] in
            for await _ in Observations({ groupManager.groupSet }) {
                self?.reconcile()
            }
        }
    }

    static nonisolated func label(for tag: MenuBarItemTag) -> String? {
        guard tag.isThawOwnedNamespace, tag.title.hasPrefix(autosavePrefix) else { return nil }
        let labels = UserDefaults.standard.dictionary(forKey: labelsKey) as? [String: String]
        return labels?[tag.title]
    }

    func isFolder(_ origin: MenuBarItemGroupOrigin) -> Bool {
        guard case let .user(id) = origin else { return false }
        return folderIDs.contains(id)
    }

    /// Turns a group into a folder, moving its items to Hidden, or back into
    /// a plain group, moving them to Visible.
    func setFolder(_ isFolder: Bool, for origin: MenuBarItemGroupOrigin, members: [MenuBarItem]) {
        guard let appState,
              let id = appState.itemGroupManager.userGroupID(for: origin, members: members)
        else { return }
        if isFolder {
            folderIDs.insert(id)
        } else {
            folderIDs.remove(id)
        }
        persist()
        reconcile()
        MenuBarSearchItemActions.move(members, to: isFolder ? .hidden : .visible, appState: appState)
        diagLog.info("Group \(id.uuidString) is \(isFolder ? "now" : "no longer") a folder")
    }

    func ownsWindowID(_ windowID: CGWindowID) -> Bool {
        statusItems.values.contains { $0.button?.window?.windowServerID == windowID }
    }

    /// Whether the pointer is on a folder icon, so the panel's outside-click
    /// dismissal leaves that icon's own toggle to it.
    func iconContainsPointer() -> Bool {
        guard let itemManager = appState?.itemManager, let pointer = MouseHelpers.locationCoreGraphics else {
            return false
        }
        return statusItems.keys.contains { id in
            itemManager.barBounds(ofThawItemNamed: Self.autosaveName(for: id))?.contains(pointer) == true
        }
    }

    private func persist() {
        UserDefaults.standard.set(folderIDs.map(\.uuidString).sorted(), forKey: Self.foldersKey)
        var stored: [String: [String: String]] = [:]
        for (id, style) in styles where folderIDs.contains(id) {
            var entry = ["symbol": style.symbol]
            entry["color"] = style.color?.hexString
            stored[id.uuidString] = entry
        }
        UserDefaults.standard.set(stored, forKey: Self.stylesKey)
    }

    private func applyStyle(to id: UUID) {
        guard let button = statusItems[id]?.button else { return }
        let style = style(for: id)
        var image = NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: Style.defaultSymbol, accessibilityDescription: nil)
        if let color = style.color {
            image = image?.withSymbolConfiguration(.init(paletteColors: [color]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
        button.image = image
    }

    private func reconcile() {
        guard let appState else { return }
        let groups = appState.itemGroupManager.groupSet.groups
        let live = Set(groups.map(\.id))
        if !folderIDs.isSubset(of: live) {
            folderIDs.formIntersection(live)
            styles = styles.filter { folderIDs.contains($0.key) }
            persist()
        }
        for (id, statusItem) in statusItems where !folderIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(statusItem)
            statusItems[id] = nil
        }
        var labels: [String: String] = [:]
        for group in groups where folderIDs.contains(group.id) {
            let name = folderName(for: group)
            let statusItem = statusItems[group.id] ?? makeStatusItem(for: group.id)
            statusItem.button?.toolTip = name
            statusItem.button?.setAccessibilityLabel(name)
            labels[Self.autosaveName(for: group.id)] = name
        }
        UserDefaults.standard.set(labels, forKey: Self.labelsKey)
    }

    private func folderName(for group: MenuBarItemGroup) -> String {
        if let name = group.name {
            return name
        }
        let items = appState?.itemManager.managedItems ?? []
        let names = group.memberIdentifiers.compactMap { identifier in
            items.first { MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier) == identifier }?.displayName
        }
        return names.isEmpty
            ? String(localized: "Folder")
            : ListFormatter.localizedString(byJoining: Array(names.prefix(3)))
    }

    private static func autosaveName(for id: UUID) -> String {
        autosavePrefix + id.uuidString
    }

    private func makeStatusItem(for id: UUID) -> NSStatusItem {
        let name = Self.autosaveName(for: id)
        UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(name)")
        UserDefaults.standard.set(true, forKey: "NSStatusItem VisibleCC \(name)")
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = name
        statusItem.button?.setAccessibilityIdentifier(name)
        statusItem.button?.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(iconClicked(_:))
        statusItems[id] = statusItem
        applyStyle(to: id)
        assertWindowTitle(name, for: id, attempt: 0)
        diagLog.info("Created the folder icon for group \(id.uuidString)")
        return statusItem
    }

    /// Without the window title the item cache tags a new icon as a generic
    /// Item-0; the button window often appears only after creation.
    private func assertWindowTitle(_ name: String, for id: UUID, attempt: Int) {
        guard let statusItem = statusItems[id] else { return }
        if let window = statusItem.button?.window {
            window.title = name
        } else if attempt < 20 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.assertWindowTitle(name, for: id, attempt: attempt + 1)
            }
        }
    }

    @objc private func iconClicked(_ sender: NSStatusBarButton) {
        guard let appState,
              let raw = sender.identifier?.rawValue,
              let id = UUID(uuidString: raw),
              let group = appState.itemGroupManager.groupSet.groups.first(where: { $0.id == id })
        else { return }
        let panel = appState.menuBarManager.thawBarPanel
        if panel.isVisible, panel.presentation == .folder, panel.folderMemberIdentifiers == group.memberIdentifiers {
            panel.close()
            return
        }
        guard let screen = sender.window?.screen ?? NSScreen.screenWithActiveMenuBar ?? NSScreen.main else { return }
        panel.show(
            section: .hidden,
            on: screen,
            presentation: .folder,
            folderMembers: group.memberIdentifiers,
            openedFrom: appState.itemManager.barBounds(ofThawItemNamed: Self.autosaveName(for: id))
        )
    }
}

private extension NSColor {
    /// #RRGGBB in sRGB, for storing a color in defaults.
    var hexString: String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            .map { Int(($0 * 255).rounded()).clamped(to: 0 ... 255) }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }

    convenience init?(hexString: String) {
        let hex = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
