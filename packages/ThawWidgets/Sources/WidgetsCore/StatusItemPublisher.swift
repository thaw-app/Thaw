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

/// Puts the composed widget icon in the menu bar as a real status item.
/// Adapted from Barometer's StatusItemRegistry pattern (multi-item publishing
/// with stable autosave names) with permission.
///
/// The autosave name is still "Thaw.Widget.Preview" from when the icon was a
/// preview in Thaw, so an icon the user already placed keeps its position.
@MainActor
final class StatusItemPublisher: NSObject {
    static let shared = StatusItemPublisher()

    static let autosaveName = MenuBarItemTag.thawWidgetIdentifier
    private var statusItem: NSStatusItem?
    /// What the icon shows now.
    var lastState: StatusIconPreviewState?
    private var appearanceObservation: NSKeyValueObservation?
    /// Whether the icon was last drawn for a dark menu bar.
    private var renderedDark: Bool?
    /// What the image on the button was drawn from.
    private var rendered: StatusIconDrawnContent?
    private var menuTitles: [String] = []
    private var hasContent = false
    /// Thaw's choice to hide the icon, which outlives every reading published after it.
    var isHiddenByThaw = false {
        didSet {
            if oldValue != isHiddenByThaw {
                applyVisibility()
            }
        }
    }

    /// Creates (or reuses) a status item and sets its image to the rendered
    /// composition. The item appears immediately.
    func publish(_ state: StatusIconPreviewState) {
        guard !state.composition.isEmpty else {
            hide()
            return
        }
        hasContent = true
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = Self.autosaveName
            item.behavior = []
            item.isVisible = false
            item.button?.imagePosition = .imageOnly
            item.button?.imageScaling = .scaleProportionallyDown
            statusItem = item
            appearanceObservation = item.button.map(observeAppearance(of:))
        }
        lastState = state
        if let button = statusItem?.button {
            // A new image makes AppKit snapshot the item again, so it is set only when the picture changes.
            // A reading often changes its text alone, as Wi-Fi strength does between bars.
            let dark = Self.isDark(button)
            if state.drawn != rendered || dark != renderedDark {
                button.image = Self.image(for: state, darkMenuBar: dark)
                rendered = state.drawn
                renderedDark = dark
            }
            Self.describe(button, for: state)
        }
        let titles = [state.title] + state.details
        if titles != menuTitles || statusItem?.menu == nil {
            statusItem?.menu = makeMenu(for: state)
            menuTitles = titles
        }
        applyVisibility()
    }

    static func shows(hasContent: Bool, hiddenByThaw: Bool) -> Bool {
        hasContent && !hiddenByThaw
    }

    private func applyVisibility() {
        let visible = Self.shows(hasContent: hasContent, hiddenByThaw: isHiddenByThaw)
        if statusItem?.isVisible != visible {
            statusItem?.isVisible = visible
        }
    }

    /// A coloured icon is drawn in the menu bar's ink, so it's redrawn when the bar turns light or dark.
    func observeAppearance(of button: NSButton) -> NSKeyValueObservation {
        button.observe(\.effectiveAppearance) { [weak self] button, _ in
            MainActor.assumeIsolated { self?.appearanceChanged(of: button) }
        }
    }

    /// AppKit sets the appearance again each time it snapshots the item, and a template follows the
    /// bar by itself, so only a coloured icon whose bar really turned light or dark is redrawn.
    func appearanceChanged(of button: NSButton) {
        guard let state = lastState else { return }
        let dark = Self.isDark(button)
        guard dark != renderedDark else { return }
        renderedDark = dark
        guard state.style.hasColor(composition: state.composition, samples: state.samples) else { return }
        button.image = Self.image(for: state, darkMenuBar: dark)
    }

    static func isDark(_ button: NSButton) -> Bool {
        button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Draws the readings and describes them to VoiceOver. The identifier stays fixed, because
    /// Thaw names its own items by it and the label changes with every reading.
    static func configure(_ button: NSButton, for state: StatusIconPreviewState) {
        button.image = image(for: state, darkMenuBar: isDark(button))
        describe(button, for: state)
    }

    /// Describes the readings to VoiceOver and the tooltip, leaving the picture alone.
    static func describe(_ button: NSButton, for state: StatusIconPreviewState) {
        let description = state.accessibilityDescription
        button.setAccessibilityIdentifier(autosaveName)
        guard button.toolTip != description else { return }
        button.setAccessibilityLabel(description)
        button.toolTip = description
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
        if state.composition.center.showsNetwork(for: state.samples) || state.composition.activeSources.contains(.wifi) {
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
        hasContent = false
        applyVisibility()
    }

    /// A template that follows the menu bar, or in the bar's own ink once a reading is coloured, since a template drops colour.
    static func image(for state: StatusIconPreviewState, darkMenuBar: Bool) -> NSImage {
        let icon = CompositeStatusIcon(composition: state.composition, samples: state.samples, style: state.style)
        let isColored = state.style.hasColor(composition: state.composition, samples: state.samples)
        return render(icon, size: 22, scheme: isColored && darkMenuBar ? .dark : .light, isTemplate: !isColored)
    }

    /// Renders a SwiftUI view hierarchy into an NSImage at the given point size.
    static func render(
        _ view: some View,
        size: CGFloat,
        scheme: ColorScheme = .light,
        isTemplate: Bool = true
    ) -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: size, height: size).environment(\.colorScheme, scheme))
        renderer.scale = 2.0
        renderer.isOpaque = false
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = isTemplate
        return image
    }
}
