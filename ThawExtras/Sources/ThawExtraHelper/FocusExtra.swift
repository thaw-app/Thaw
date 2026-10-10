//
//  FocusExtra.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The Focus stand-in: shows the active mode's symbol, and lists the modes in
/// its menu so one can be turned on or off without the original.
@MainActor
final class FocusExtra: NSObject {
    private let source = FocusSource()
    private let access = FocusDatabaseAccess()
    private let onChange: (_ symbol: String, _ label: String) -> Void
    private var snapshot: FocusSnapshot = .unavailable
    private var pollTask: Task<Void, Never>?

    /// Matches the original's own refresh. Focus changes from other devices
    /// and from schedules have no notification this process can observe.
    private static let pollInterval: Duration = .seconds(2)

    init(onChange: @escaping (_ symbol: String, _ label: String) -> Void) {
        self.onChange = onChange
    }

    func start() {
        access.activate()
        onChange("moon", String(localized: "Focus"))
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refresh() async {
        let next = await source.read()
        guard next != snapshot else { return }
        snapshot = next
        switch next {
        case .unavailable, .inactive:
            onChange("moon", String(localized: "Focus"))
        case let .active(mode, _):
            // Some Focus symbols are private to the system and do not resolve
            // here (Work's person.lanyardcard.fill), so fall back to the moon.
            let symbol = mode?.symbolName.flatMap { name in
                NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? nil : name
            } ?? "moon.fill"
            onChange(symbol, mode?.name ?? String(localized: "Focus"))
        }
    }

    func populate(_ menu: NSMenu) {
        let modes = snapshot.availableModes
        let active = snapshot.activeMode
        if modes.isEmpty {
            // The Focus service answers only entitled apps; say so rather than
            // guess "off".
            let title = switch snapshot {
            case .unavailable: String(localized: "Focus status isn't available to Thaw")
            case .inactive: String(localized: "Focus is off")
            case let .active(mode, _): mode.map { String(localized: "\($0.name) is on") }
                ?? String(localized: "Focus is on")
            }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            if case .unavailable = snapshot {
                let allow = NSMenuItem(
                    title: String(localized: "Allow Access to Focus…"),
                    action: #selector(requestAccess),
                    keyEquivalent: ""
                )
                allow.target = self
                menu.addItem(allow)
            }
        }
        for mode in modes {
            let item = NSMenuItem(title: mode.name, action: #selector(toggle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.id
            item.state = mode.id == active?.id ? .on : .off
            if let symbol = mode.symbolName {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(
            title: String(localized: "Focus Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let mode = snapshot.availableModes.first(where: { $0.id == id })
        else { return }
        let turnOff = snapshot.activeMode?.id == id
        Task {
            _ = turnOff ? await source.deactivate() : await source.activate(mode)
            await refresh()
        }
    }

    @objc private func requestAccess() {
        guard access.request() else { return }
        Task { await refresh() }
    }

    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
