//
//  LayoutMultiSelectTip.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import TipKit

/// Tells upgraders that Layout can now select and move several items, never over the limitations card.
/// It has no display limit, since the pane rebuilds as it loads; the close button or a first multi-selection retires it.
struct LayoutMultiSelectTip: Tip {
    /// The first version with multi-select. Anyone whose last version is older is an upgrader.
    nonisolated static let introducedIn = "3.0.0-alpha.10"

    /// The first beta with multi-select. Betas sort after every alpha, so the beta line needs its own cutoff.
    nonisolated static let betaIntroducedIn = "3.0.0-beta.3"

    /// Set at launch when the previous version predates multi-select, and kept in the datastore so later launches
    /// and the Settings process still see it.
    @Parameter static var isUpgrade: Bool = false

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
        ]
    }

    /// Whether a launch whose last recorded version is previousVersion counts as an upgrade from before multi-select.
    /// No recorded version means a new install, or a first launch that went through onboarding, so it does not count.
    nonisolated static func isUpgrade(previousVersion: String?) -> Bool {
        guard let previousVersion, !previousVersion.isEmpty else { return false }
        if previousVersion.contains("-beta") {
            return ReleaseVersionOrder.precedes(previousVersion, betaIntroducedIn)
        }
        return ReleaseVersionOrder.precedes(previousVersion, introducedIn)
    }
}
