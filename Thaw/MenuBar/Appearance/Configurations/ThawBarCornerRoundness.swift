//
//  ThawBarCornerRoundness.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Reads and writes the Thaw Bar's own corner roundness, 0 for square to 1 for round.
///
/// Older versions saved a rounded-corners toggle, so a look without a roundness reads the toggle,
/// and saving still writes it for them.
nonisolated enum ThawBarCornerRoundness {
    private enum Keys: CodingKey {
        case cornerRoundness
        case hasRoundedShape
    }

    static func decode(from decoder: any Decoder) throws -> Double {
        let stored = try decoder.container(keyedBy: Keys.self)
        if let roundness = try? stored.decodeIfPresent(Double.self, forKey: .cornerRoundness) {
            return roundness.isFinite ? min(max(roundness, 0), 1) : 0
        }
        return (try? stored.decodeIfPresent(Bool.self, forKey: .hasRoundedShape)) == true ? 1 : 0
    }

    static func encode(_ roundness: Double, to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(roundness, forKey: .cornerRoundness)
        try values.encode(roundness > 0, forKey: .hasRoundedShape)
    }
}

nonisolated extension ThawBarAppearance {
    /// Whether the corners are rounded at all. Setting it picks square or fully round.
    var hasRoundedShape: Bool {
        get { cornerRoundness > 0 }
        set { cornerRoundness = newValue ? 1 : 0 }
    }
}

nonisolated extension ResolvedThawBarAppearance {
    var hasRoundedShape: Bool {
        cornerRoundness > 0
    }

    init(hasRoundedShape: Bool, fillConfiguration: MenuBarAppearancePartialConfiguration) {
        self.init(cornerRoundness: hasRoundedShape ? 1 : 0, fillConfiguration: fillConfiguration)
    }
}

nonisolated extension MenuBarAppearanceConfigurationV2 {
    /// The menu bar shape's Corners slider value, 0 when there is no shape.
    var shapeRoundness: Double {
        switch shapeKind {
        case .noShape: 0
        case .full: MenuBarShapeRoundness.value(of: [fullShapeInfo])
        case .split: MenuBarShapeRoundness.value(of: [splitShapeInfo.leading, splitShapeInfo.trailing])
        case .notch: MenuBarShapeRoundness.value(of: [notchShapeInfo.leading, notchShapeInfo.trailing])
        }
    }
}

/// The Thaw Bar's own Corners slider, from square to round, like the menu bar shape's.
struct ThawBarCornersSlider: View {
    @Binding var roundness: Double

    var body: some View {
        LabeledContent("Corners") {
            HStack(spacing: ThawSpacing.base) {
                Text("Square")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ThawSlider(value: $roundness, in: 0 ... 1) {
                    EmptyView()
                }
                .accessibilityLabel("Corners")
                Text("Round")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: 360)
        }
    }
}
