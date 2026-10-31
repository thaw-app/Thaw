//
//  ThawHintTipViewStyle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import TipKit

/// Draws a TipKit tip as a first-run hint card, without the tip's actions.
/// The close button retires the tip with the tipClosed reason.
public struct ThawHintTipViewStyle: TipViewStyle {
    let dismissLabel: LocalizedStringResource

    public init(dismissLabel: LocalizedStringResource) {
        self.dismissLabel = dismissLabel
    }

    public func makeBody(configuration: Configuration) -> some View {
        ThawFirstRunHint(
            image: configuration.image ?? Image(systemName: "lightbulb"),
            title: configuration.title,
            text: configuration.message ?? Text(verbatim: ""),
            dismissLabel: dismissLabel
        ) {
            configuration.tip.invalidate(reason: .tipClosed)
        }
    }
}
