//
//  ThawHUD.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// A small confirmation capsule under the menu bar, for verbs that otherwise
/// succeed invisibly.
///
/// Most actions carry their own feedback. A few do not: Zen mode toggled
/// from a hotkey, a Control Center button, a Shortcuts action applying a
/// profile with no window open. Without an acknowledgment the user presses
/// the key again to find out whether the first press landed.
///
/// The panel copies DisplayIdentifyOverlay deliberately, for the same
/// reasons. It is non-activating, because the hotkey was pressed inside
/// another app and that app keeps key. It sets ignoresMouseEvents, so clicks
/// pass through to whatever is underneath, including the menu bar the user
/// may be reaching for. It does not animate (animationBehavior = .none), so
/// it is Reduce Motion-safe by construction rather than by a branch that
/// could rot.
///
/// A single reused panel: a second show(symbol:text:) replaces the content
/// and restarts the timer, so a held hotkey never stacks capsules.
@MainActor
enum ThawHUD {
    /// How long a confirmation stays up. Long enough to read two words after
    /// the eye moves to it, short enough that it is gone before it becomes
    /// something to dismiss.
    static let duration: Duration = .milliseconds(1200)

    /// The live panel. Retained here because an NSPanel that nobody owns is
    /// released out from under its own dismissal.
    private static var panel: NSPanel?

    /// The in-flight dismissal, cancelled and replaced when a second HUD
    /// arrives before the previous one has expired.
    private static var dismissal: Task<Void, Never>?

    /// Shows a confirmation capsule and dismisses it after duration.
    ///
    /// - Parameters:
    ///   - symbol: An SF Symbol name. It carries the verb at a glance, before
    ///     the text is read.
    ///   - text: One to four words describing what just happened ("Zen on",
    ///     "Hidden items shown"). The capsule sizes to its text, so longer
    ///     copy belongs in a notification.
    ///   - screen: The display to show the capsule on, or nil to follow the
    ///     pointer, where a gesture just happened. Event-driven callers pass
    ///     a screen because the event can land while the pointer is on
    ///     another display.
    ///   - placement: Where along the top of that display the capsule sits.
    ///     Confirmations use the center, where the eye already is.
    ///     Event-driven callers pass the user's choice, because an
    ///     unrequested banner in the center of a wide display covers the work.
    static func show(
        symbol: String,
        text: LocalizedStringKey,
        on screen: NSScreen? = nil,
        placement: ThawHUDPlacement = .center
    ) {
        dismissal?.cancel()

        guard let screen = screen ?? NSScreen.screenWithMouse ?? NSScreen.main else {
            return
        }

        let panel = panel ?? makePanel()
        Self.panel = panel

        let host = NSHostingView(rootView: ThawHUDCard(symbol: symbol, text: text))
        panel.contentView = host
        panel.setFrame(frame(for: host, on: screen, placement: placement), display: true)
        panel.orderFront(nil)

        dismissal = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Tears the panel down. Idempotent, a cancelled dismissal that raced a
    /// second show simply finds nothing to close.
    static func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Places the capsule just below the menu bar, at placement along it.
    ///
    /// Under the bar rather than mid-screen because that is where the change
    /// happened: the eye is already at the top of the display when a menu bar
    /// verb runs. The width comes from the hosting view's fitting size, so a
    /// two-word label gets a two-word capsule.
    private static func frame(
        for host: NSView,
        on screen: NSScreen,
        placement: ThawHUDPlacement
    ) -> NSRect {
        let fitting = host.fittingSize
        let size = CGSize(width: max(fitting.width, 120), height: max(fitting.height, 34))
        let gap: CGFloat = 8
        return NSRect(
            x: placement.originX(screenFrame: screen.frame, width: size.width),
            y: screen.frame.maxY - screen.getMenuBarHeightEstimate() - gap - size.height,
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
        // Above ordinary windows and full-screen apps, below the menu bar
        // overlays Thaw itself drives, a confirmation annotates the desktop,
        // it is not menu bar chrome.
        panel.level = .statusBar
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        // A label, never a target: clicks fall through to whatever is behind.
        panel.ignoresMouseEvents = true
        return panel
    }
}

/// The capsule itself: symbol beside text, on the shared panel glass so it
/// reads as Thaw's chrome rather than as an OS alert.
private struct ThawHUDCard: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(ThawType.symbol.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(ThawType.heading)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .fixedSize()
        .thawGlass(.panel, in: Capsule(style: .continuous))
        // The panel is non-activating and ignores the mouse; VoiceOver reaches
        // the same state through the settings pane and the menu bar itself.
        .accessibilityHidden(true)
    }
}
