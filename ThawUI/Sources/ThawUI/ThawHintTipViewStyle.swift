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
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ThawFirstRunHint(
            image: configuration.image ?? Image(systemName: "lightbulb"),
            title: configuration.title,
            text: configuration.message ?? Text(verbatim: "")
        ) {
            configuration.tip.invalidate(reason: .tipClosed)
        }
    }
}
