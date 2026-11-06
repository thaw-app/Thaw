//
//  TextInputExtra.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Carbon

/// The Input menu stand-in: shows the selected input source's icon, or a
/// keyboard when it has none, and lists the enabled sources in its menu so one
/// can be picked without the original.
@MainActor
final class TextInputExtra: NSObject {
    private let button: NSStatusBarButton
    private var observer: NSObjectProtocol?

    init(button: NSStatusBarButton) {
        self.button = button
        super.init()
    }

    func start() {
        refresh()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
    }

    func populate(_ menu: NSMenu) {
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let currentID = current.flatMap { Self.string($0, kTISPropertyInputSourceID) }
        for source in Self.selectableSources() {
            guard let name = Self.string(source, kTISPropertyLocalizedName) else { continue }
            let item = NSMenuItem(title: name, action: #selector(select(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source
            item.image = Self.icon(for: source)
            item.state = Self.string(source, kTISPropertyInputSourceID) == currentID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let emoji = NSMenuItem(
            title: String(localized: "Show Emoji & Symbols"),
            action: #selector(showCharacterPalette),
            keyEquivalent: ""
        )
        emoji.target = self
        menu.addItem(emoji)
        let settings = NSMenuItem(
            title: String(localized: "Open Keyboard Settings…"),
            action: #selector(openKeyboardSettings),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)
    }

    private func refresh() {
        let label = String(localized: "Input Menu")
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let image = current.flatMap(Self.icon(for:))
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: label)
        button.image = image
        button.toolTip = current.flatMap { Self.string($0, kTISPropertyLocalizedName) } ?? label
        button.setAccessibilityLabel(button.toolTip)
    }

    @objc private func select(_ sender: NSMenuItem) {
        guard let object = sender.representedObject else { return }
        // swiftlint:disable:next force_cast
        TISSelectInputSource((object as! TISInputSource))
    }

    @objc private func showCharacterPalette() {
        NSApp.orderFrontCharacterPalette(nil)
    }

    @objc private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Input sources

    /// The sources the user has enabled and can switch to, as the original
    /// lists them: keyboard layouts and input methods, not palettes.
    private static func selectableSources() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceIsEnabled as String: true,
        ] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        return sources.filter { source in
            let category = string(source, kTISPropertyInputSourceCategory)
            return category == (kTISCategoryKeyboardInputSource as String)
        }
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    /// The source's own icon at menu bar size. Layouts ship an icon file;
    /// input methods may only have an IconRef, which is left to the fallback.
    private static func icon(for source: TISInputSource) -> NSImage? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) else { return nil }
        let url = Unmanaged<CFURL>.fromOpaque(pointer).takeUnretainedValue() as URL
        guard let image = NSImage(contentsOf: url) else { return nil }
        let height: CGFloat = 16
        if image.size.height > 0 {
            image.size = NSSize(width: image.size.width * height / image.size.height, height: height)
        }
        return image
    }
}
