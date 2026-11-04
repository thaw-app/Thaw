//  Adapted from Barometer (https://github.com/mackid1993/Barometer)
//  Copyright (Barometer) © 2026 mackid1993. Used with permission.
//  Licensed under the GNU GPLv3
//
//  StatusItemPublisher.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI

/// Publishes a composed status icon as a real menu bar item, independent from
/// Thaw's own control items. Adapted from Barometer's StatusItemRegistry pattern
/// (multi-item publishing with stable autosave names) with permission.
///
/// One item at a time for the prototype. The autosave name "Thaw.Widget.Preview"
/// keeps AppKit's persistence slot stable so the preview does not jump between
/// toggles, and never collides with Thaw's own "Thaw.ControlItem.*" names.
@MainActor
final class StatusItemPublisher: NSObject {
    static let shared = StatusItemPublisher()

    static let autosaveName = MenuBarItemTag.thawWidgetIdentifier
    private var statusItem: NSStatusItem?

    /// Whether a preview item is currently on the bar.
    var isPublished: Bool {
        statusItem?.isVisible == true
    }

    /// Creates (or reuses) a status item and sets its image to the rendered
    /// composition. The item appears immediately.
    func publish(_ state: StatusIconPreviewState) {
        guard !state.composition.isEmpty else {
            hide()
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = Self.autosaveName
            item.behavior = []
            item.isVisible = false
            item.button?.imagePosition = .imageOnly
            item.button?.imageScaling = .scaleProportionallyDown
            statusItem = item
        }
        if let button = statusItem?.button {
            Self.configure(button, for: state)
        }
        statusItem?.menu = makeMenu(for: state)
        if statusItem?.isVisible != true {
            statusItem?.isVisible = true
        }
    }

    /// Draws the readings and describes them to VoiceOver. The identifier stays fixed, because
    /// Thaw names its own items by it and the label changes with every reading.
    static func configure(_ button: NSButton, for state: StatusIconPreviewState) {
        button.image = render(CompositeStatusIcon(composition: state.composition, samples: state.samples), size: 22)
        button.setAccessibilityIdentifier(autosaveName)
        button.setAccessibilityLabel(state.accessibilityDescription)
        button.toolTip = state.accessibilityDescription
    }

    /// Also used by tests to verify that a click exposes the same snapshot as the image.
    func makeMenu(for state: StatusIconPreviewState) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for title in [state.title] + state.details {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if state.composition.center == .wifi || state.composition.activeSources.contains(.wifi) {
            menu.addItem(.separator())
            let settingsItem = NSMenuItem(
                title: String(localized: "Open Network Settings…"),
                action: #selector(openNetworkSettings),
                keyEquivalent: ""
            )
            settingsItem.target = self
            menu.addItem(settingsItem)
        }
        return menu
    }

    @objc private func openNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Hides the preview item without destroying it (so a re-publish is instant).
    func hide() {
        statusItem?.isVisible = false
    }

    /// Renders a SwiftUI view hierarchy into an NSImage at the given point size.
    static func render(
        _ view: some View,
        size: CGFloat
    ) -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: size, height: size).environment(\.colorScheme, .light))
        renderer.scale = 2.0
        renderer.isOpaque = false
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}
