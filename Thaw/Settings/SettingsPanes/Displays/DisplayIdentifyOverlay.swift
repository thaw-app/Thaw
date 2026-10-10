//
//  DisplayIdentifyOverlay.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// Identify physical displays when identical thumbnails or desk arrangement make selection ambiguous.
/// Panels preserve focus, pass clicks through, and avoid animation for Reduce Motion.
@MainActor
enum DisplayIdentifyOverlay {
    /// Retain panels through dismissal and reuse them on repeated Identify rather than stacking.
    private static var panels: [CGDirectDisplayID: NSPanel] = [:]
    /// Replace pending dismissal when Identify is pressed again before the flash ends.
    private static var dismissal: Task<Void, Never>?

    /// Share left-to-right numbering with the selector so thumbnail and overlay numbers agree.
    static func displayNumbers() -> [CGDirectDisplayID: Int] {
        let ordered = NSScreen.managedScreens.sorted { $0.frame.minX < $1.frame.minX }
        var numbers: [CGDirectDisplayID: Int] = [:]
        for (index, screen) in ordered.enumerated() {
            numbers[screen.displayID] = index + 1
        }
        return numbers
    }

    /// - Parameter duration: Time to keep overlays visible; the default allows a glance across the desk.
    static func flash(duration: Duration = .milliseconds(1500)) {
        dismissal?.cancel()

        let numbers = displayNumbers()
        for screen in NSScreen.managedScreens {
            let cgID = screen.displayID
            let name = screen.localizedName.trimmingCharacters(in: .whitespaces)
            let panel = panels[cgID] ?? makePanel()
            panels[cgID] = panel
            panel.contentView = NSHostingView(
                rootView: DisplayIdentifyCard(
                    number: numbers[cgID],
                    name: name.isEmpty ? String(localized: "Display") : name
                )
            )
            panel.setFrame(frame(centeredOn: screen), display: true)
            panel.orderFront(nil)
        }

        dismissal = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            dismissAll()
        }
    }

    /// Idempotent teardown if a cancelled dismissal races another flash.
    static func dismissAll() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    /// Use a fixed card size rather than screen-proportional labels for comparable display identification.
    private static func frame(centeredOn screen: NSScreen) -> NSRect {
        let size = CGSize(width: 320, height: 132)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above ordinary and full-screen windows, below Thaw's menu bar overlays.
        panel.level = .statusBar
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        // A label, never a target: clicks fall through to whatever is behind.
        panel.ignoresMouseEvents = true
        return panel
    }
}

/// Shared panel glass identifies this as Thaw chrome rather than a system alert.
private struct DisplayIdentifyCard: View {
    let number: Int?
    let name: String

    /// Larger than largeTitle for reading across the room; still scales with the user's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 6) {
            if let number {
                Text(verbatim: "\(number)")
                    .font(.system(size: numberSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            Text(name)
                .font(ThawType.heading)
                .foregroundStyle(ThawInk.supporting)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.panel, style: .continuous))
        .accessibilityHidden(true)
    }
}
