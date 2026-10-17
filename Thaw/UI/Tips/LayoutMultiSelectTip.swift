//
//  LayoutMultiSelectTip.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import TipKit

/// Tells people who upgraded from a version without multi-select that Layout can now select and move several items.
///
/// It shows only to upgraders, never over the Layout pane's first-visit limitations card, and at most once.
/// The first selection of two or more items retires it.
struct LayoutMultiSelectTip: Tip {
    /// The first version with multi-select. Anyone whose last version is older is an upgrader.
    nonisolated static let introducedIn = "3.0.0-alpha.10"

    /// Set at launch when the previous version predates multi-select, and kept in the datastore so later launches
    /// and the Settings process still see it.
    @Parameter static var isUpgrade: Bool = false

    /// Mirrors the pane's limitations card. Transient because each pane that shows the tip sets it as it appears,
    /// and true until then so the tip cannot spend its one showing in the moment before the pane reports.
    @Parameter(.transient) static var isLimitationsCardShowing: Bool = true

    nonisolated static let titleResource = LocalizedStringResource(
        "New: select several items",
        comment: "Title of the Layout tip that announces selecting several menu bar items at once"
    )

    nonisolated static let messageResource = LocalizedStringResource(
        "⌘-click or ⇧-click icons, then drag one or right-click to move them all.",
        comment: "Message of the Layout tip that announces selecting several menu bar items at once"
    )

    nonisolated static let symbolName = "cursorarrow.click.2"

    var title: Text {
        Text(Self.titleResource)
    }

    var message: Text? {
        Text(Self.messageResource)
    }

    var image: Image? {
        Image(systemName: Self.symbolName)
    }

    var rules: [Rule] {
        [
            #Rule(Self.$isUpgrade) { $0 == true },
            #Rule(Self.$isLimitationsCardShowing) { $0 == false },
        ]
    }

    /// One showing is enough for a feature announcement; the configured immediate frequency lets it appear at once.
    var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    /// Whether a launch whose last recorded version is previousVersion counts as an upgrade from before multi-select.
    /// No recorded version means a new install, or a first launch that went through onboarding, so it does not count.
    nonisolated static func isUpgrade(previousVersion: String?) -> Bool {
        guard let previousVersion, !previousVersion.isEmpty else { return false }
        return ReleaseVersionOrder.precedes(previousVersion, introducedIn)
    }
}
