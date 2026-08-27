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

    @Environment(AppState.self) var appState: AppState
    @Bindable var appearanceManager: MenuBarAppearanceManager
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
                SettingsWarningPill(
                    message: "Tip: You can also edit these settings by right-clicking in an empty area of the menu bar.",
                    systemImage: "lightbulb.circle.fill"
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

            ThawBarAppearanceEditor(configuration: $appearanceManager.configuration)

            if appearanceManager.configuration.current.tintKind != .noTint
                || appearanceManager.configuration.shapeKind != .noShape
                || appearanceManager.configuration.current.backgroundKind != .none
            {
                if appearanceManager.isReduceTransparencyEnabled {
                    reduceTransparencyWarning
                }

                SettingsWarningPill(
                    message: "If effects are not visible, disable \"Show menu bar background\" in System Settings \(Constants.menuArrow) Menu Bar",
                    systemImage: "info.circle.fill"
                )
            }

            perSpaceSection
        }
    }

    private var perSpaceSection: some View {
        IceSection {
            Text("Per-Space override")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if appearanceManager.activeSpaceHasOverride {
                    Text("This Space uses a saved override.")
                        .foregroundStyle(.secondary)
                    Button("Remove Override for This Space") {
                        appearanceManager.removeOverrideForActiveSpace()
                    }
                } else {
                    Text("This Space uses the shared appearance.")
                        .foregroundStyle(.secondary)
                    Button("Use Current Appearance for This Space") {
                        appearanceManager.saveOverrideForActiveSpace()
                    }
                }
                if !appearanceManager.spaceOverrides.isEmpty {
                    HStack {
                        Text("Spaces with overrides: \(appearanceManager.spaceOverrides.count)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove All") {
                            appearanceManager.removeAllSpaceOverrides()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            Text("Saves the appearance above for the currently active Space only. Every other Space keeps the shared appearance.")
        }
    }

    /// Shown while Reduce Transparency is on, because the system then draws an
    /// opaque menu bar that hides everything the overlay paints behind it.
    /// Painting on top instead is not an option: it would cover the menu bar
    /// items too. See ``MenuBarOverlayPanel/updateWindowLevel()``.
    private var reduceTransparencyWarning: some View {
        SettingsWarningPill(
            title: "Menu bar effects are hidden by Reduce Transparency",
            message: "macOS draws a solid menu bar while Reduce Transparency is on, so \(Constants.displayName) cannot tint or reshape it. Turn the setting off to see these effects.",
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange,
            actionTitle: "Open Settings",
            action: openReduceTransparencySettings
        )
    }

    private func openReduceTransparencySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Seeing_Display"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
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
        // No wrapping VStack: `IceSection` is a native grouped `Section` and
        // must remain a direct child of the enclosing `IceForm` list, which
        // provides the inter-section spacing.
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
        IceSection(isBordered: false) {
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

    /// The shape the border follows.
    ///
    /// There is no shape to trace on the menu bar when this is `noShape`, so
    /// the menu bar side of the border row is disabled. The Thaw Bar draws its
    /// border around its own panel and is unaffected.
    let shapeKind: MenuBarShapeKind

    /// Whether the Thaw Bar has been given its own appearance.
    ///
    /// Its half of the border row stops doing anything once it has, since the
    /// panel then reads its border out of the override instead.
    let isThawBarOverridden: Bool

    var body: some View {
        // No wrapping VStack: `IceSection` is a native grouped `Section` and
        // must remain a direct child of the enclosing `IceForm` list, which
        // provides the inter-section spacing.
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
                case .adaptive, .adaptiveGradient:
                    // Both derive their colors from the wallpaper, so there
                    // is nothing for the user to pick here.
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
        LabeledContent("Border") {
            HStack {
                Toggle("Menu Bar", isOn: $configuration.borderOnMenuBar)
                    .disabled(shapeKind == .noShape)

                Toggle("\(Constants.displayName) Bar", isOn: $configuration.borderOnThawBar)
                    .disabled(isThawBarOverridden)
            }
            .toggleStyle(.checkbox)
            .frame(height: 24)
        }
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
        IceSection(isBordered: false) {
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
            UnlabeledShapeEditor(
                configuration: $configuration.lightModeConfiguration,
                shapeKind: configuration.shapeKind,
                isThawBarOverridden: configuration.thawBarAppearance.overridesMenuBar
            )
        case .dark:
            UnlabeledShapeEditor(
                configuration: $configuration.darkModeConfiguration,
                shapeKind: configuration.shapeKind,
                isThawBarOverridden: configuration.thawBarAppearance.overridesMenuBar
            )
        }
    }
}

private struct StaticShapeEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        UnlabeledShapeEditor(
            configuration: $configuration.staticConfiguration,
            shapeKind: configuration.shapeKind,
            isThawBarOverridden: configuration.thawBarAppearance.overridesMenuBar
        )
    }
}

// MARK: - Thaw Bar Editor

/// The section that forks the Thaw Bar's appearance away from the menu bar's.
///
/// The two have always matched so they read as one surface, and they still do
/// until the toggle here is switched on. Note that this sits outside the
/// light/dark split: the panel takes one set of values regardless of the
/// system appearance, because a floating panel is not trying to blend into
/// anything that changes underneath it.
private struct ThawBarAppearanceEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    private var appearance: ThawBarAppearance {
        configuration.thawBarAppearance
    }

    /// Turning the override on seeds it from the values already on screen, so
    /// the toggle by itself never changes how the panel looks.
    private var isEnabled: Binding<Bool> {
        Binding(
            get: { configuration.thawBarAppearance.overridesMenuBar },
            set: { isOn in
                if isOn {
                    configuration.thawBarAppearance = ThawBarAppearance(
                        seededFrom: configuration.resolvedThawBarAppearance
                    )
                } else {
                    configuration.thawBarAppearance.overridesMenuBar = false
                }
            }
        )
    }

    var body: some View {
        IceSection("\(Constants.displayName) Bar") {
            Toggle("Use a separate appearance", isOn: isEnabled)
                .annotation("Style the \(Constants.displayName) Bar on its own instead of matching the menu bar.")

            if appearance.overridesMenuBar {
                roundedShapeToggle
                tintPicker
                tintOpacity
                borderToggle
                if appearance.hasBorder {
                    borderColor
                    borderWidth
                }
            }
        }
    }

    private var roundedShapeToggle: some View {
        Toggle("Rounded corners", isOn: $configuration.thawBarAppearance.hasRoundedShape)
    }

    private var tintPicker: some View {
        LabeledContent("Tint") {
            HStack {
                IcePicker("Tint", selection: $configuration.thawBarAppearance.tintKind) {
                    ForEach(ThawBarAppearance.supportedTintKinds) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                }
                .labelsHidden()

                switch appearance.tintKind {
                case .solid:
                    ColorPicker(
                        appearance.tintKind.localized,
                        selection: $configuration.thawBarAppearance.tintColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                case .gradient:
                    IceGradientPicker(
                        appearance.tintKind.localized,
                        gradient: $configuration.thawBarAppearance.tintGradient,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                default:
                    EmptyView()
                }
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var tintOpacity: some View {
        if appearance.tintKind != .noTint {
            LabeledContent("Opacity") {
                IceSlider(
                    value: $configuration.thawBarAppearance.tintOpacity,
                    in: 0 ... 1,
                    step: 0.05,
                    showsValue: false
                ) {
                    Text(appearance.tintOpacity, format: .percent.precision(.fractionLength(0)))
                }
            }
        }
    }

    private var borderToggle: some View {
        Toggle("Border", isOn: $configuration.thawBarAppearance.hasBorder)
    }

    private var borderColor: some View {
        ColorPicker(
            "Border Color",
            selection: $configuration.thawBarAppearance.borderColor,
            supportsOpacity: true
        )
    }

    private var borderWidth: some View {
        IcePicker(
            "Border Width",
            selection: $configuration.thawBarAppearance.borderWidth
        ) {
            Text(verbatim: "1").tag(1.0)
            Text(verbatim: "2").tag(2.0)
            Text(verbatim: "3").tag(3.0)
        }
    }
}

// MARK: - Preview Button

private struct PreviewButton: View {
    @Environment(AppState.self) private var appState: AppState
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
