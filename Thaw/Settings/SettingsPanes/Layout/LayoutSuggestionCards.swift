//
//  LayoutSuggestionCards.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit
import SwiftUI
import ThawUI

/// Isolate notch-suggestion cache reads to avoid re-diffing the whole form.
struct LayoutSuggestionCards: View {
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager

    /// Bumped on dismissal, so a card disappears at once.
    @State private var dismissals = 0

    private var visibleItems: [MenuBarItem] {
        itemManager.managedItems(for: .visible)
    }

    /// Hints suggest improvements, not failures; closing means "Not now" and suppresses them for a month.
    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = dismissals
        if !LayoutSuggestionDismissal.isQuiet(.itemsBehindNotch) {
            let behindNotch = LayoutSuggestions.itemsBehindNotch(visibleItems, notchRects: MenuBarNotchGeometry.rects)
            if !behindNotch.isEmpty {
                ThawFirstRunHint(
                    systemImage: "rectangle.topthird.inset.filled",
                    behindNotch.count == 1
                        ? "\(LayoutSuggestions.names(of: behindNotch)) is behind the notch. Move it to Hidden and it opens from the \(Constants.displayName) Bar instead."
                        : "\(LayoutSuggestions.names(of: behindNotch)) are behind the notch. Move them to Hidden and they open from the \(Constants.displayName) Bar instead.",
                    actionTitle: "Move to Hidden",
                    action: { MenuBarSearchItemActions.move(behindNotch, to: .hidden, appState: appState) },
                    onDismiss: { dismiss(.itemsBehindNotch) }
                )
            }
        }
        if !LayoutSuggestionDismissal.isQuiet(.littleSnitchScriptingAccess), littleSnitchItemIsMissing {
            ThawFirstRunHint(
                systemImage: "exclamationmark.triangle",
                "Little Snitch is running, but \(Constants.displayName) can’t see its menu bar icon. In Little Snitch’s settings, under Security, turn on “Allow GUI Scripting access to Little Snitch.”",
                actionTitle: "Open Little Snitch",
                action: openLittleSnitch,
                onDismiss: { dismiss(.littleSnitchScriptingAccess) }
            )
        }
    }

    private var littleSnitchItemIsMissing: Bool {
        let isAgentRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: LayoutSuggestions.littleSnitchAgentBundleID)
            .isEmpty
        guard isAgentRunning else { return false }
        return LayoutSuggestions.littleSnitchItemIsMissing(
            runningBundleIDs: [LayoutSuggestions.littleSnitchAgentBundleID],
            items: itemManager.managedItems
        )
    }

    private func openLittleSnitch() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: LayoutSuggestions.littleSnitchAppBundleID
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func dismiss(_ kind: LayoutSuggestionDismissal.Kind) {
        LayoutSuggestionDismissal.dismiss(kind)
        dismissals += 1
    }
}
