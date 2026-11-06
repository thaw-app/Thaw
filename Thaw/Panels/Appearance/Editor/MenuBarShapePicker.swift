//
//  MenuBarShapePicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Sets how round the shape's corners are and the margins around it. The editor
/// picks the shape itself, in the section's header.
struct MenuBarShapePicker: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        if configuration.shapeKind != .noShape {
            cornersRow
            marginsRow
        }
    }

    // MARK: Corners

    /// The info of every part of the shape: one for Full, two for Split and Notch.
    private var parts: [MenuBarFullShapeInfo] {
        switch configuration.shapeKind {
        case .noShape: []
        case .full: [configuration.fullShapeInfo]
        case .split: [configuration.splitShapeInfo.leading, configuration.splitShapeInfo.trailing]
        case .notch: [configuration.notchShapeInfo.leading, configuration.notchShapeInfo.trailing]
        }
    }

    /// One roundness for every end, from square to round. A shape with any
    /// round end reads as its roundness; one with only square ends reads as 0.
    private var roundness: Binding<Double> {
        Binding(
            get: { MenuBarShapeRoundness.value(of: parts) },
            set: { value in
                let info = MenuBarShapeRoundness.info(for: value)
                configuration.fullShapeInfo = info
                configuration.splitShapeInfo = MenuBarSplitShapeInfo(leading: info, trailing: info)
                configuration.notchShapeInfo.leading = info
                configuration.notchShapeInfo.trailing = info
            }
        )
    }

    private var cornersRow: some View {
        LabeledContent("Corners") {
            HStack(spacing: ThawSpacing.base) {
                Text("Square")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ThawSlider(value: roundness, in: 0 ... 1) {
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

    // MARK: Margins

    private var marginsRow: some View {
        LabeledContent("Margins") {
            HStack(spacing: ThawSpacing.base) {
                margin("Left", value: $configuration.leftMargin)
                if configuration.shapeKind == .notch {
                    margin("Notch", value: $configuration.notchMargin)
                }
                margin("Right", value: $configuration.rightMargin, reversed: true)
            }
            .frame(maxWidth: 360)
        }
    }

    private func margin(_ label: LocalizedStringResource, value: Binding<Double>, reversed: Bool = false) -> some View {
        ThawSlider(label, value: value, in: 0 ... 15, step: 1, reversed: reversed, showsValue: true, unit: "pt")
    }
}

/// Reads and writes the Corners slider as end caps and a roundness.
nonisolated enum MenuBarShapeRoundness {
    /// The slider's value for a shape made of these parts.
    static func value(of parts: [MenuBarFullShapeInfo]) -> Double {
        let rounded = parts.filter { $0.leadingEndCap == .round || $0.trailingEndCap == .round }
        return rounded.map(\.roundness).max() ?? 0
    }

    /// The part every end gets for a slider value: square ends at 0, round
    /// ends curved by the value above it.
    static func info(for value: Double) -> MenuBarFullShapeInfo {
        let value = value.clamped(to: 0 ... 1)
        let cap: MenuBarEndCap = value > 0 ? .round : .square
        return MenuBarFullShapeInfo(leadingEndCap: cap, trailingEndCap: cap, roundness: value)
    }
}

/// The shape kinds as tabs in the strip, each named with a symbol for its outline.
extension MenuBarShapeKind: ThawTab {
    var title: LocalizedStringResource {
        localized
    }

    var systemImage: String {
        switch self {
        case .noShape: "rectangle.slash"
        case .full: "capsule"
        case .split: "rectangle.split.2x1"
        case .notch: "macbook"
        }
    }
}
