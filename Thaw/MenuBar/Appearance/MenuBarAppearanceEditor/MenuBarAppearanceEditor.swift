//
//  MenuBarAppearanceEditor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct MenuBarAppearanceEditor: View {
    enum Location {
        case settings
        case panel
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject var appearanceManager: MenuBarAppearanceManager
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isResetPromptPresented = false

    let location: Location
    let onDone: (() -> Void)?

    var body: some View {
        bodyContent
            .safeAreaBar(edge: .top, spacing: 0) {
                panelHeading
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                bottomBar
            }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotEdit
        } else {
            mainForm
                .scrollEdgeEffectStyle(.automatic, for: .vertical)
                .padding(.top, topPadding)
        }
    }

    @ViewBuilder
    private var panelHeading: some View {
        if case .panel = location {
            Text("Menu Bar Appearance")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
        }
    }

    private var cannotEdit: some View {
        Text("\(Constants.displayName) cannot edit the appearance of automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var mainForm: some View {
        IceForm {
            if
                case .settings = location,
                appState.settings.advanced.enableSecondaryContextMenu
            {
                CalloutBox(
                    "Tip: You can also edit these settings by right-clicking in an empty area of the menu bar.",
                    systemImage: "lightbulb"
                )
            }

            IceSection {
                isDynamicToggle
            }

            if appearanceManager.configuration.isDynamic {
                LabeledBackgroundEditor(configuration: $appearanceManager.configuration, appearance: .light)
                LabeledBackgroundEditor(configuration: $appearanceManager.configuration, appearance: .dark)
            } else {
                UnlabeledBackgroundEditor(configuration: $appearanceManager.configuration.staticConfiguration)
            }

            IceSection("Menu Bar Shape") {
                shapePicker
                isInset
            }

            if appearanceManager.configuration.shapeKind != .noShape {
                if appearanceManager.configuration.isDynamic {
                    LabeledShapeEditor(configuration: $appearanceManager.configuration, appearance: .light)
                    LabeledShapeEditor(configuration: $appearanceManager.configuration, appearance: .dark)
                } else {
                    StaticShapeEditor(configuration: $appearanceManager.configuration)
                }
            }

            if appearanceManager.configuration.current.tintKind != .noTint
                || appearanceManager.configuration.shapeKind != .noShape
                || appearanceManager.configuration.current.backgroundKind != .none
            {
                CalloutBox(
                    "If effects are not visible, disable \"Show menu bar background\" in System Settings \(Constants.menuArrow) Menu Bar",
                    systemImage: "info.circle"
                )
            }
        }
    }

    private var isDynamicToggle: some View {
        Toggle("Use dynamic appearance", isOn: $appearanceManager.configuration.isDynamic)
            .annotation("Apply different settings based on the current system appearance.")
    }

    private var topPadding: CGFloat {
        0
    }

    private var bottomBar: some View {
        HStack {
            if case .panel = location {
                Button("Done") {
                    if let onDone {
                        onDone()
                    } else {
                        dismissWindow()
                    }
                }
            }

            Spacer()

            if
                !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                appearanceManager.configuration != .defaultConfiguration
            {
                Button("Reset") {
                    isResetPromptPresented = true
                }
                .alert("Reset Menu Bar Appearance", isPresented: $isResetPromptPresented) {
                    Button("Cancel", role: .cancel) {
                        isResetPromptPresented = false
                    }
                    Button("Reset", role: .destructive) {
                        appearanceManager.configuration = .defaultConfiguration
                        isResetPromptPresented = false
                    }
                } message: {
                    Text("This action cannot be undone.")
                }
            }
        }
        .buttonBorderShape(.capsule)
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
    }

    private var shapePicker: some View {
        MenuBarShapePicker(configuration: $appearanceManager.configuration)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var isInset: some View {
        if appearanceManager.configuration.shapeKind != .noShape {
            Toggle(
                "Use inset shape on screens with notch",
                isOn: $appearanceManager.configuration.isInset
            )
        }
    }
}

// MARK: - Background Editors

private struct UnlabeledBackgroundEditor: View {
    @Binding var configuration: MenuBarAppearancePartialConfiguration
    var showTitle: Bool = true

    @ViewBuilder
    private var styleSection: some View {
        backgroundPicker
        if configuration.backgroundKind != .none, configuration.backgroundKind != .glass {
            backgroundOpacity
        }
        if configuration.backgroundKind == .glass {
            LabeledContent("Effect") {
                IcePicker("Glass Style", selection: $configuration.backgroundGlassStyle) {
                    ForEach(MenuBarGlassStyle.allCases, id: \.self) { style in
                        Text(style.localized).tag(style)
                    }
                }
                .labelsHidden()
            }
        }
        backgroundShadowToggle
    }

    var body: some View {
        VStack(spacing: .iceFormDefaultSpacing) {
            if showTitle {
                IceSection("Background") {
                    styleSection
                }
            } else {
                IceSection {
                    styleSection
                }
            }
            IceSection {
                backgroundBorderToggle
                if configuration.backgroundHasBorder {
                    backgroundBorderColor
                    backgroundBorderWidth
                }
            }
        }
    }

    private var backgroundPicker: some View {
        LabeledContent("Style") {
            HStack {
                IcePicker("Background", selection: $configuration.backgroundKind) {
                    ForEach(MenuBarBackgroundKind.allCases, id: \.self) { kind in
                        Text(kind.localized).tag(kind)
                    }
                }
                .labelsHidden()

                switch configuration.backgroundKind {
                case .none:
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
                case .glass:
                    EmptyView()
                case .adaptive:
                    EmptyView()
                }
            }
            .frame(height: 24)
        }
    }

    private var backgroundOpacity: some View {
        LabeledContent("Opacity") {
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

    private var backgroundShadowToggle: some View {
        Toggle("Shadow", isOn: $configuration.backgroundHasShadow)
    }

    private var backgroundBorderToggle: some View {
        Toggle("Border", isOn: $configuration.backgroundHasBorder)
    }

    @ViewBuilder
    private var backgroundBorderColor: some View {
        if configuration.backgroundHasBorder {
            ColorPicker(
                "Border Color",
                selection: $configuration.backgroundBorderColor,
                supportsOpacity: true
            )
        }
    }

    @ViewBuilder
    private var backgroundBorderWidth: some View {
        if configuration.backgroundHasBorder {
            IcePicker(
                "Border Width",
                selection: $configuration.backgroundBorderWidth
            ) {
                Text(verbatim: "1").tag(1.0)
                Text(verbatim: "2").tag(2.0)
                Text(verbatim: "3").tag(3.0)
            }
        }
    }
}

private struct LabeledBackgroundEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2
    @State private var currentAppearance = SystemAppearance.current
    @State private var textFrame = CGRect.zero

    let appearance: SystemAppearance

    var body: some View {
        IceSection(options: .plain) {
            labelStack
        } content: {
            UnlabeledBackgroundEditor(configuration: binding, showTitle: false)
        }
        .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { _ in
            currentAppearance = .current
        }
    }

    private var labelStack: some View {
        HStack {
            Text(appearance == .light ? "Background - Light Appearance" : "Background - Dark Appearance")
                .font(.headline)
                .onFrameChange(update: $textFrame)

            if currentAppearance != appearance {
                PreviewButton(appearance: appearance)
            }
        }
        .frame(height: textFrame.height)
    }

    private var binding: Binding<MenuBarAppearancePartialConfiguration> {
        switch appearance {
        case .light: $configuration.lightModeConfiguration
        case .dark: $configuration.darkModeConfiguration
        }
    }
}

// MARK: - Shape Tint Editors

private struct UnlabeledShapeEditor: View {
    @Binding var configuration: MenuBarAppearancePartialConfiguration

    var body: some View {
        VStack(spacing: .iceFormDefaultSpacing) {
            IceSection {
                tintPicker
                tintOpacity
                shadowToggle
            }
            IceSection {
                borderToggle
                borderColor
                borderWidth
            }
        }
    }

    private var tintPicker: some View {
        LabeledContent("Tint") {
            HStack {
                IcePicker("Tint", selection: $configuration.tintKind) {
                    ForEach(MenuBarTintKind.allCases) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                }
                .labelsHidden()

                switch configuration.tintKind {
                case .noTint:
                    EmptyView()
                case .solid:
                    ColorPicker(
                        configuration.tintKind.localized,
                        selection: $configuration.tintColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                case .gradient:
                    IceGradientPicker(
                        configuration.tintKind.localized,
                        gradient: $configuration.tintGradient,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                case .glass:
                    EmptyView()
                case .adaptive:
                    EmptyView()
                }
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var tintOpacity: some View {
        if configuration.tintKind == .glass {
            LabeledContent("Effect") {
                IcePicker("Glass Style", selection: $configuration.tintGlassStyle) {
                    ForEach(MenuBarGlassStyle.allCases, id: \.self) { style in
                        Text(style.localized).tag(style)
                    }
                }
                .labelsHidden()
            }
        } else if configuration.tintKind != .noTint {
            LabeledContent("Opacity") {
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
    }

    private var shadowToggle: some View {
        Toggle("Shadow", isOn: $configuration.hasShadow)
    }

    private var borderToggle: some View {
        Toggle("Border", isOn: $configuration.hasBorder)
    }

    @ViewBuilder
    private var borderColor: some View {
        if configuration.hasBorder {
            ColorPicker(
                "Border Color",
                selection: $configuration.borderColor,
                supportsOpacity: true
            )
        }
    }

    @ViewBuilder
    private var borderWidth: some View {
        if configuration.hasBorder {
            IcePicker(
                "Border Width",
                selection: $configuration.borderWidth
            ) {
                Text(verbatim: "1").tag(1.0)
                Text(verbatim: "2").tag(2.0)
                Text(verbatim: "3").tag(3.0)
            }
        }
    }
}

private struct LabeledShapeEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2
    @State private var currentAppearance = SystemAppearance.current
    @State private var textFrame = CGRect.zero

    let appearance: SystemAppearance

    var body: some View {
        IceSection(options: .plain) {
            labelStack
        } content: {
            partialEditor
        }
        .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { _ in
            currentAppearance = .current
        }
    }

    private var labelStack: some View {
        HStack {
            Text(appearance.titleKey)
                .font(.headline)
                .onFrameChange(update: $textFrame)

            if currentAppearance != appearance {
                PreviewButton(appearance: appearance)
            }
        }
        .frame(height: textFrame.height)
    }

    @ViewBuilder
    private var partialEditor: some View {
        switch appearance {
        case .light:
            UnlabeledShapeEditor(configuration: $configuration.lightModeConfiguration)
        case .dark:
            UnlabeledShapeEditor(configuration: $configuration.darkModeConfiguration)
        }
    }
}

private struct StaticShapeEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        UnlabeledShapeEditor(configuration: $configuration.staticConfiguration)
    }
}

// MARK: - Preview Button

private struct PreviewButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var isPressed = false

    let appearance: SystemAppearance

    private var manager: MenuBarAppearanceManager {
        appState.appearanceManager
    }

    private var previewConfiguration: MenuBarAppearancePartialConfiguration {
        switch appearance {
        case .light:
            manager.configuration.lightModeConfiguration
        case .dark:
            manager.configuration.darkModeConfiguration
        }
    }

    var body: some View {
        Button("Hold to Preview") {
            // Button action is handled by onChange modifier tracking isPressed state
        }
        .buttonStyle(PreviewButtonStyle(isPressed: $isPressed))
        .onChange(of: isPressed) {
            manager.previewConfiguration = isPressed ? previewConfiguration : nil
        }
    }
}

private struct PreviewButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}
