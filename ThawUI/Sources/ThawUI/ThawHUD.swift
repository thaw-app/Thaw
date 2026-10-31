//
//  ThawHUD.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// A capsule under the menu bar confirming actions that otherwise succeed invisibly. Its single reused panel
/// never takes key from the app in front, never animates (Reduce Motion) and never stacks under a held hotkey.
@MainActor
public enum ThawHUD {
    /// How tall the menu bar is on a screen. An app that can read it more exactly sets this.
    public static var menuBarHeight: (NSScreen) -> CGFloat = { screen in
        ThawHUDPlacement.menuBarHeight(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, fallback: NSStatusBar.system.thickness)
    }

    /// Long enough to read two words after the eye moves to it, gone before it needs dismissing.
    public static let duration: Duration = .milliseconds(1200)

    /// Retained here: an NSPanel nobody owns is released out from under its own dismissal.
    private static var panel: NSPanel?

    /// Cancelled and replaced when a second HUD arrives before this one expires.
    private static var dismissal: Task<Void, Never>?

    /// Shows a confirmation capsule and dismisses it after displayDuration.
    ///
    /// The text says what just happened, best in one to four words; give a sentence a longer duration. The capsule truncates
    /// it at the screen's width. With no screen it follows the pointer; event-driven callers pass one, as the pointer may be
    /// elsewhere, and the user's placement choice, as a banner in the center covers the work.
    public static func show(
        symbol: String? = nil,
        text: LocalizedStringResource,
        on screen: NSScreen? = nil,
        placement: ThawHUDPlacement = .center,
        displayDuration: Duration = ThawHUD.duration
    ) {
        dismissal?.cancel()

        guard let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return
        }

        let panel = panel ?? makePanel()
        Self.panel = panel

        let host = NSHostingView(rootView: ThawHUDCard(symbol: symbol, text: text))
        panel.contentView = host
        let frame = placement.frame(fitting: host.fittingSize, screenFrame: screen.frame, menuBarHeight: menuBarHeight(screen))
        panel.setFrame(frame, display: true)
        // A confirmation often arrives while another app is in front.
        panel.orderFrontRegardless()

        dismissal = Task {
            try? await Task.sleep(for: displayDuration)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Idempotent: a cancelled dismissal that raced a second show finds nothing to close.
    public static func dismiss() {
        panel?.orderOut(nil)
        panel = nil
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
        // Above ordinary windows and full-screen apps, below menu bar overlays: a confirmation annotates the desktop.
        panel.level = .statusBar
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        // A label, never a target: clicks fall through to whatever is behind.
        panel.ignoresMouseEvents = true
        return panel
    }
}

/// An optional symbol beside text, on panel glass so it doesn't read as an OS alert.
private struct ThawHUDCard: View {
    let symbol: String?
    let text: LocalizedStringResource

    var body: some View {
        HStack(spacing: ThawSpacing.base) {
            if let symbol {
                Image(systemName: symbol)
                    .font(ThawType.symbol.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(ThawType.heading)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, ThawSpacing.gutter)
        .padding(.vertical, 9)
        // The width stays free so text wider than the screen truncates inside the capsule.
        .fixedSize(horizontal: false, vertical: true)
        .thawGlass(.panel, in: Capsule(style: .continuous))
        // The panel is non-activating and ignores the mouse; VoiceOver reaches
        // the same state through the settings pane and the menu bar itself.
        .accessibilityHidden(true)
    }
}
