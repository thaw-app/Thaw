//
//  ThawBarAppearanceEditor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - Thaw Bar section host

/// Appearance controls for the Thaw Bar panel (background, tint, corners,
/// border, shadow), shown inside ``MenuBarAppearanceEditor``.
struct ThawBarAppearanceEditorSection: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        if configuration.isDynamic {
            LabeledThawBarEditor(configuration: $configuration, appearance: .light)
            LabeledThawBarEditor(configuration: $configuration, appearance: .dark)
        } else {
            IceSection("\(Constants.displayName) Bar") {
                UnlabeledThawBarEditor(configuration: $configuration.thawBarStaticConfiguration)
            }
        }
    }
}

// MARK: - Labeled (dynamic) editors

private struct LabeledThawBarEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2
    @State private var textFrame = CGRect.zero

    let appearance: SystemAppearance

    var body: some View {
        IceSection(isBordered: false) {
            labelStack
        } content: {
            UnlabeledThawBarEditor(configuration: binding)
        }
    }

    private var labelStack: some View {
        Text(
            appearance == .light
                ? "\(Constants.displayName) Bar - Light Appearance"
                : "\(Constants.displayName) Bar - Dark Appearance"
        )
        .font(.headline)
        .onFrameChange(update: $textFrame)
        .frame(height: textFrame.height)
    }

    private var binding: Binding<ThawBarAppearancePartialConfiguration> {
        switch appearance {
        case .light: $configuration.thawBarLightModeConfiguration
        case .dark: $configuration.thawBarDarkModeConfiguration
        }
    }
}

// MARK: - Unlabeled editor body

private struct UnlabeledThawBarEditor: View {
    @Binding var configuration: ThawBarAppearancePartialConfiguration

    /// Tint kinds that apply to a freestanding panel. Glass tint is reserved
    /// for the menu bar overlay; the Thaw Bar uses glass as a background kind.
    private static let tintKinds: [MenuBarTintKind] = [
        .noTint, .solid, .gradient, .adaptive,
    ]

    var body: some View {
        backgroundPicker
        if configuration.backgroundKind == .adaptive {
            adaptiveBrightness
            adaptiveGlass
        }
        if configuration.backgroundKind == .solid || configuration.backgroundKind == .gradient || configuration.backgroundKind == .sampled {
            backgroundOpacity
        }
        if configuration.backgroundKind == .glass {
            backgroundGlassStyle
        }

        tintPicker
        if configuration.tintKind != .noTint {
            tintOpacity
        }

        cornerStylePicker

        Toggle("Shadow", isOn: $configuration.hasShadow)

        Toggle("Border", isOn: $configuration.hasBorder)
        if configuration.hasBorder {
            borderColor
            borderWidth
            if !configuration.cornerStyle.isFullyRounded {
                omitTopBorderToggle
            }
        }
    }

    // MARK: Background

    private var backgroundPicker: some View {
        LabeledContent("Background") {
            HStack {
                IcePicker("Background", selection: $configuration.backgroundKind) {
                    ForEach(ThawBarBackgroundKind.allCases) { kind in
                        Text(kind.localized).tag(kind)
                    }
                }
                .labelsHidden()

                switch configuration.backgroundKind {
                case .none, .adaptive, .glass, .sampled:
                    EmptyView()
                case .solid:
                    ColorPicker(
                        "Background",
                        selection: $configuration.backgroundColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                case .gradient:
                    IceGradientPicker(
                        "Background",
                        gradient: $configuration.backgroundGradient,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }
            .frame(height: 24)
        }
        .annotation {
            switch configuration.backgroundKind {
            case .adaptive:
                Text("Live-samples the menu bar and wallpaper. Use Brightness and Glass to fine-tune the match.")
            case .solid:
                Text("Fills the bar with a single color.")
            case .gradient:
                Text("Fills the bar with a gradient.")
            case .glass:
                Text("System liquid glass. Clear shows whatever is behind the bar; Regular is thicker.")
            case .none:
                Text("No fill. Tint, border, and shadow still apply if enabled.")
            case .sampled:
                Text("Same live sample as Match Menu Bar, with an opacity slider.")
            }
        }
    }

    private var adaptiveBrightness: some View {
        LabeledContent("Brightness") {
            IceSlider(
                value: $configuration.adaptiveBrightness,
                in: -1 ... 1,
                step: 0.05,
                showsValue: false
            ) {
                Text(configuration.adaptiveBrightness, format: .percent.precision(.fractionLength(0)))
            }
        }
    }

    private var adaptiveGlass: some View {
        LabeledContent("Glass") {
            IceSlider(
                value: $configuration.adaptiveGlassAmount,
                in: 0 ... 1,
                step: 0.05,
                showsValue: false
            ) {
                Text(configuration.adaptiveGlassAmount, format: .percent.precision(.fractionLength(0)))
            }
        }
    }

    private var backgroundOpacity: some View {
        LabeledContent("Background Opacity") {
            IceSlider(
                value: $configuration.backgroundOpacity,
                in: 0 ... 1,
                step: 0.05,
                showsValue: false
            ) {
                Text(configuration.backgroundOpacity, format: .percent.precision(.fractionLength(0)))
            }
        }
    }

    private var backgroundGlassStyle: some View {
        LabeledContent("Glass Style") {
            IcePicker("Glass Style", selection: $configuration.backgroundGlassStyle) {
                ForEach(MenuBarGlassStyle.allCases, id: \.self) { style in
                    Text(style.localized).tag(style)
                }
            }
            .labelsHidden()
        }
    }

    // MARK: Tint

    private var tintPicker: some View {
        LabeledContent("Tint") {
            HStack {
                IcePicker("Tint", selection: $configuration.tintKind) {
                    ForEach(Self.tintKinds, id: \.self) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                }
                .labelsHidden()

                switch configuration.tintKind {
                case .noTint, .glass, .adaptive:
                    EmptyView()
                case .solid:
                    ColorPicker(
                        "Tint",
                        selection: $configuration.tintColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                case .gradient:
                    IceGradientPicker(
                        "Tint",
                        gradient: $configuration.tintGradient,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }
            .frame(height: 24)
        }
        .annotation("Optional overlay on top of the background. Leave as None to match the sampled menu bar color.")
    }

    private var tintOpacity: some View {
        LabeledContent("Tint Opacity") {
            IceSlider(
                value: $configuration.tintOpacity,
                in: 0 ... 1,
                step: 0.05,
                showsValue: false
            ) {
                Text(configuration.tintOpacity, format: .percent.precision(.fractionLength(0)))
            }
        }
    }

    // MARK: Corners & border

    private var cornerStylePicker: some View {
        LabeledContent("Corners") {
            IcePicker("Corners", selection: $configuration.cornerStyle) {
                ForEach(ThawBarCornerStyle.allCases) { style in
                    Text(style.localized).tag(style)
                }
            }
            .labelsHidden()
        }
        .annotation {
            switch configuration.cornerStyle {
            case .rounded:
                Text("Fully rounded capsule ends.")
            case .square:
                Text("Squared ends. With a border, the top edge is omitted by default so it is not clipped by the display corners.")
            }
        }
    }

    private var borderColor: some View {
        ColorPicker(
            "Border Color",
            selection: $configuration.borderColor,
            supportsOpacity: true
        )
    }

    private var borderWidth: some View {
        IcePicker(
            "Border Width",
            selection: $configuration.borderWidth
        ) {
            Text(verbatim: "1").tag(1.0)
            Text(verbatim: "2").tag(2.0)
            Text(verbatim: "3").tag(3.0)
        }
    }

    private var omitTopBorderToggle: some View {
        Toggle("Omit top border edge", isOn: $configuration.omitTopBorderWhenSquare)
            .annotation("Hides the top stroke so square corners are not clipped by the display's rounded corners.")
    }
}
