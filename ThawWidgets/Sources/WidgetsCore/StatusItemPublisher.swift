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
import SwiftUI

/// Puts the composed widget icon in the menu bar as a real status item.
/// Adapted from Barometer's StatusItemRegistry pattern (multi-item publishing
/// with stable autosave names) with permission.
///
/// The autosave name is still "Thaw.Widget.Preview" from when the icon was a
/// preview in Thaw, so an icon the user already placed keeps its position.
@MainActor
final class StatusItemPublisher: NSObject {
    static let shared = StatusItemPublisher()

    private var statusItem: NSStatusItem?

    /// Creates (or reuses) a status item and sets its image to the rendered
    /// composition. The item appears immediately.
    func publish(_ state: StatusIconPreviewState) {
        guard !state.composition.isEmpty else {
            hide()
            return
        }
        let image = Self.render(
            CompositeStatusIcon(composition: state.composition, samples: state.samples),
            size: 22
        )
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "Thaw.Widget.Preview"
            item.behavior = []
            item.isVisible = false
            item.button?.imagePosition = .imageOnly
            item.button?.imageScaling = .scaleProportionallyDown
            statusItem = item
        }
        statusItem?.button?.image = image
        statusItem?.button?.setAccessibilityLabel(state.accessibilityDescription)
        statusItem?.button?.toolTip = state.accessibilityDescription
        statusItem?.menu = makeMenu(for: state)
        if statusItem?.isVisible != true {
            statusItem?.isVisible = true
        }
    }

    /// The menu a click opens: the same readings the image shows.
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
