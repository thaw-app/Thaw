//
//  MenuBarAppearanceEditor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Shared by the Appearance pane and standalone popover; Location selects the surrounding chrome.
struct MenuBarAppearanceEditor: View {
    enum Location {
        /// Inside the settings window, alongside the other panes.
        case settings
        /// The standalone popover supplies its own title and bottom bar.
        case panel
    }

    @Environment(AppState.self) var appState
    @Bindable var appearanceManager: MenuBarAppearanceManager
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isResetAlertPresented = false
    @State private var editingAppearance = SystemAppearance.current
    @State private var systemAppearance = SystemAppearance.current
    @State private var reducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    let location: Location
    let onDone: (() -> Void)?

    /// Read shorthand only; bindings go through $appearanceManager.configuration.
    private var configuration: MenuBarAppearanceConfigurationV2 {
        appearanceManager.configuration
    }

    private var hasShape: Bool {
        configuration.shapeKind != .noShape
    }

    private var isMenuBarHiddenBySystem: Bool {
        appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults
    }

    private var hasCustomConfiguration: Bool {
        configuration != .defaultConfiguration
    }

    var body: some View {
        switch location {
        case .settings:
            editor
        case .panel:
            EditorPanelChrome("Appearance") {
                editor
            } bottomBar: {
                panelBottomBar
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if isMenuBarHiddenBySystem {
            hiddenMenuBarNotice
        } else {
            editorForm
                .scrollEdgeEffectStyle(.automatic, for: .vertical)
        }
    }

    /// Auto-hiding leaves no menu bar for Thaw to paint, so replace the editor with a notice.
    private var hiddenMenuBarNotice: some View {
        VStack(spacing: ThawSpacing.base) {
            Text("\(Constants.displayName) can’t change the look of a menu bar that macOS hides automatically.")
            Text("Turn off “Automatically hide and show the menu bar” in System Settings \(Constants.menuArrow) Menu Bar.")
                .foregroundStyle(ThawInk.supporting)
        }
        .font(ThawType.body)
        .multilineTextAlignment(.center)
        .padding(ThawSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorForm: some View {
        ThawForm {
            // Warn about unsaved didSet changes and Reduce Transparency's solid bar covering the custom look.
            if reducesTransparency {
                SettingsWarningPill(
                    title: "Reduce Transparency is on",
                    message: "macOS draws the menu bar solid while it's on, which covers this look. Turn it off to see your changes.",
                    systemImage: "circle.lefthalf.filled",
                    actionTitle: "Open Accessibility Settings",
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }

            if let failure = appearanceManager.lastPersistenceFailure {
                SettingsWarningPill(
                    title: "Appearance change wasn’t saved",
                    message: "\(failure) The menu bar shows it now, but it will be back to the last saved appearance after \(Constants.displayName) restarts.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }

            if configuration.isDynamic {
                appearanceModePicker
            }

            // Shape determines which fill controls are available.
            ThawSection {
                Text("Shape")
            } content: {
                MenuBarShapePicker(configuration: $appearanceManager.configuration)
                insetToggle
            } footer: {
                Text("Your menu bar changes as you edit.")
            }

            if hasShape {
                fillSection(
                    "Inside the shape",
                    footer: "Fills the shape.",
                    kind: .shapeFill
                )
                fillSection(
                    "Behind the shape",
                    footer: "Fills the whole menu bar. The shape is drawn on top.",
                    kind: .background
                )
            } else {
                fillSection(
                    "Menu bar",
                    footer: "Fills the whole menu bar.",
                    kind: .background
                )
            }

            if case .settings = location {
                screenCornersSection
            }

            advancedSection
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            reducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
        .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { _ in
            systemAppearance = .current
        }
        .onChange(of: configuration.isDynamic) { _, isDynamic in
            if isDynamic {
                editingAppearance = systemAppearance
            }
        }
        .alert("Reset Appearance", isPresented: $isResetAlertPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { appearanceManager.configuration = .defaultConfiguration }
        } message: {
            Text("Your menu bar’s shape, colors and border go back to the defaults. This can’t be undone.")
        }
    }

    /// Keep look-selection policy at the end so appearance editing leads the pane.
    private var advancedSection: some View {
        ThawSection {
            Text("Advanced")
        } content: {
            dynamicAppearanceToggle
            if case .settings = location {
                perSpaceControls
                if hasCustomConfiguration {
                    Button("Reset Appearance…", role: .destructive) {
                        isResetAlertPresented = true
                    }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                if isAnyEffectActive {
                    Text("If a change doesn’t show, turn off “Show menu bar background” in System Settings \(Constants.menuArrow) Menu Bar.")
                }
                if case .settings = location, appState.settings.advanced.enableSecondaryContextMenu {
                    Text("Right-click an empty part of the menu bar to edit the look without opening Settings.")
                }
            }
        }
    }

    private var isAnyEffectActive: Bool {
        configuration.current.tintKind != .noTint
            || configuration.shapeKind != .noShape
            || configuration.current.backgroundKind != .none
    }

    private var perSpaceControls: some View {
        LabeledContent("This Space") {
            VStack(alignment: .trailing, spacing: ThawSpacing.tight) {
                if appearanceManager.activeSpaceHasOverride {
                    Button("Stop Using Own Look") {
                        appearanceManager.removeOverrideForActiveSpace()
                    }
                } else {
                    Button("Give This Space Its Own Look") {
                        appearanceManager.saveOverrideForActiveSpace()
                    }
                }
                if appearanceManager.spaceOverrides.count > 1 {
                    Button("Remove from All \(appearanceManager.spaceOverrides.count) Spaces") {
                        appearanceManager.removeAllSpaceOverrides()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .annotation("Saves the look above for the Space you're on. Every other Space keeps the shared look.")
    }

    /// Corners are global across displays, unlike the per-appearance and per-Space menu bar look.
    private var screenCornersSection: some View {
        @Bindable var general = appState.settings.general
        return ThawSection {
            Text("Screen corners")
        } content: {
            Toggle("Round screen corners", isOn: $general.roundScreenCorners)
            if general.roundScreenCorners {
                LabeledContent("Radius") {
                    ThawSlider(value: $general.screenCornerRadius, in: 4 ... 24, step: 1) {
                        Text("\(Int(general.screenCornerRadius)) pt")
                    }
                }
            }
        } footer: {
            Text("Draws black over the corners of every display, so they look rounded.")
        }
    }

    private var dynamicAppearanceToggle: some View {
        Toggle("Separate looks for Light and Dark Mode", isOn: $appearanceManager.configuration.isDynamic)
            .annotation("Choose which one you're editing at the top of this pane.")
    }

    private var appearanceModePicker: some View {
        ThawSection {
            LabeledContent("Editing") {
                HStack(spacing: 8) {
                    Picker("Appearance mode", selection: $editingAppearance) {
                        Text("Light").tag(SystemAppearance.light)
                        Text("Dark").tag(SystemAppearance.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    if systemAppearance != editingAppearance {
                        HoldToPreviewButton(previewedAppearance: editingAppearance)
                    }

                    Button(editingAppearance == .light ? "Copy from Dark" : "Copy from Light") {
                        copyFromOppositeAppearance()
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
        }
    }

    /// Bind to static settings or the picked light/dark mode when dynamic appearance is enabled.
    private var editedPartialConfiguration: Binding<MenuBarAppearancePartialConfiguration> {
        let keyPath: WritableKeyPath<MenuBarAppearanceConfigurationV2, MenuBarAppearancePartialConfiguration> =
            if !configuration.isDynamic {
                \.staticConfiguration
            } else {
                switch editingAppearance {
                case .light: \.lightModeConfiguration
                case .dark: \.darkModeConfiguration
                }
            }
        return Binding(
            get: { appearanceManager.configuration[keyPath: keyPath] },
            set: { appearanceManager.configuration[keyPath: keyPath] = $0 }
        )
    }

    private func copyFromOppositeAppearance() {
        switch editingAppearance {
        case .light:
            appearanceManager.configuration.lightModeConfiguration =
                appearanceManager.configuration.darkModeConfiguration
        case .dark:
            appearanceManager.configuration.darkModeConfiguration =
                appearanceManager.configuration.lightModeConfiguration
        }
    }

    /// The bottom bar's contents; EditorPanelChrome lays them out.
    @ViewBuilder
    private var panelBottomBar: some View {
        Button("Done") {
            if let onDone {
                onDone()
            } else {
                dismissWindow()
            }
        }
        .keyboardShortcut(.defaultAction)

        Spacer()

        if !isMenuBarHiddenBySystem, hasCustomConfiguration {
            Button("Reset…") {
                isResetAlertPresented = true
            }
        }
    }

    /// Background and shape fill share controls, differing only in title and footer.
    private func fillSection(_ title: LocalizedStringKey, footer: LocalizedStringKey, kind: AppearanceFillKind) -> some View {
        ThawSection {
            Text(title)
        } content: {
            UnlabeledAppearanceFillEditor(
                configuration: editedPartialConfiguration,
                fillKind: kind
            )
        } footer: {
            Text(footer)
        }
    }

    @ViewBuilder
    private var insetToggle: some View {
        if hasShape {
            Toggle("Inset on notched displays", isOn: $appearanceManager.configuration.isInset)
                .annotation("Shrinks the shape slightly so it sits below the notch.")
        }
    }
}

// MARK: - Appearance Fill Editor

private enum AppearanceFillKind {
    case background
    case shapeFill
}

/// Maps parallel background and shape-fill fields so shared controls need no per-kind switches.
private struct FillSurfaceFields {
    typealias Configuration = MenuBarAppearancePartialConfiguration

    /// Accessibility label, hidden visually because the surrounding section already names the surface.
    let colorLabel: LocalizedStringKey

    let opacity: WritableKeyPath<Configuration, Double>
    let glassStyle: WritableKeyPath<Configuration, MenuBarGlassStyle>
    let glassIsColored: WritableKeyPath<Configuration, Bool>
    let usesAccentColor: WritableKeyPath<Configuration, Bool>
    let glassFollowsSystem: WritableKeyPath<Configuration, Bool>
    let color: WritableKeyPath<Configuration, CGColor>
    let gradient: WritableKeyPath<Configuration, ThawGradient>
    let hasShadow: WritableKeyPath<Configuration, Bool>
    let hasBorder: WritableKeyPath<Configuration, Bool>
    let borderColor: WritableKeyPath<Configuration, CGColor>
    let borderWidth: WritableKeyPath<Configuration, Double>
    /// Only the shape's border has a style; the background's is a single rule.
    var borderStyle: WritableKeyPath<Configuration, MenuBarBorderStyle>?
}

/// Shared style cases keep editor visibility logic independent of the surface kind.
private enum FillStyle {
    case none
    case solid
    case gradient
    case glass
    case adaptive
}

/// Background and shape fill share controls backed by parallel configuration fields.
private struct UnlabeledAppearanceFillEditor: View {
    @Binding var configuration: MenuBarAppearancePartialConfiguration
    let fillKind: AppearanceFillKind

    var body: some View {
        stylePicker
        if style == .gradient {
            gradientAngleSlider
        }
        if style == .glass {
            glassStylePicker
        }
        if showsGlassColor {
            glassTintControls
        }
        if showsOpacity {
            opacitySlider
        }
        // No style means no surface to shade or outline.
        if style != .none {
            Toggle("Shadow", isOn: binding(fields.hasShadow))
            // Keep border controls together without repeating the label on a second row.
            LabeledContent("Border") {
                HStack(spacing: ThawSpacing.base) {
                    if configuration[keyPath: fields.hasBorder] {
                        if let borderStyle = fields.borderStyle {
                            borderStylePicker(borderStyle)
                        }
                        borderWidthPicker
                        ColorPicker("Border color", selection: binding(fields.borderColor), supportsOpacity: true)
                            .labelsHidden()
                    }
                    Toggle("Border", isOn: binding(fields.hasBorder))
                        .labelsHidden()
                }
            }
        }
    }

    private var stylePicker: some View {
        LabeledContent("Style") {
            HStack {
                Group {
                    switch fillKind {
                    case .background:
                        ThawPicker("Background", selection: $configuration.backgroundKind) {
                            ForEach(MenuBarBackgroundKind.allCases, id: \.self) { kind in
                                Text(kind.localized).tag(kind)
                            }
                        }
                    case .shapeFill:
                        ThawPicker("Shape fill", selection: $configuration.tintKind) {
                            ForEach(MenuBarTintKind.allCases) { kind in
                                Text(kind.localized).tag(kind)
                            }
                        }
                    }
                }
                .labelsHidden()

                fillColorControls
            }
            .frame(height: 24)
        }
    }

    /// Only solid and gradient own colors; glass and adaptive derive them, and none paints nothing.
    @ViewBuilder
    private var fillColorControls: some View {
        switch style {
        case .solid:
            accentAwareColorPicker(fields.colorLabel)
        case .gradient:
            ThawGradientPicker(fields.colorLabel, gradient: binding(fields.gradient), supportsOpacity: false)
                .labelsHidden()
        case .none, .glass, .adaptive:
            EmptyView()
        }
    }

    private var gradientAngleSlider: some View {
        LabeledContent("Angle") {
            ThawSlider(
                value: binding(fields.gradient).angle,
                in: 0 ... 360,
                step: 1,
                showsValue: false
            ) {
                Text("\(Int(configuration[keyPath: fields.gradient].angle.rounded()))°")
            }
            .help("0° runs top to bottom, 90° left to right")
        }
    }

    private var glassStylePicker: some View {
        LabeledContent("Effect") {
            ThawPicker("Glass Style", selection: glassChoice) {
                Text("Match System").tag(GlassChoice.matchSystem)
                ForEach(MenuBarGlassStyle.allCases, id: \.self) { style in
                    Text(style.localized).tag(GlassChoice.style(style))
                }
            }
            .labelsHidden()
            .help("Match System follows Liquid Glass in System Settings \(Constants.menuArrow) Appearance: Regular while it's Tinted, Clear while it's Clear.")
        }
    }

    /// Store system-following as a separate flag so builds without that choice can still read the style.
    private enum GlassChoice: Hashable {
        case matchSystem
        case style(MenuBarGlassStyle)
    }

    private var glassChoice: Binding<GlassChoice> {
        Binding(
            get: {
                configuration[keyPath: fields.glassFollowsSystem]
                    ? .matchSystem
                    : .style(configuration[keyPath: fields.glassStyle])
            },
            set: { choice in
                switch choice {
                case .matchSystem:
                    configuration[keyPath: fields.glassFollowsSystem] = true
                    configuration[keyPath: fields.glassStyle] = MenuBarAppearanceManager.systemGlassIsTinted ? .regular : .clear
                case let .style(style):
                    configuration[keyPath: fields.glassFollowsSystem] = false
                    configuration[keyPath: fields.glassStyle] = style
                }
            }
        )
    }

    @ViewBuilder
    private var glassTintControls: some View {
        Toggle("Tint the glass", isOn: binding(fields.glassIsColored))
        if configuration[keyPath: fields.glassIsColored] {
            LabeledContent("Tint color") {
                accentAwareColorPicker("Tint color")
            }
        }
    }

    /// Hide the color well when following the accent, since System Settings supplies the color.
    private func accentAwareColorPicker(_ label: LocalizedStringKey) -> some View {
        HStack(spacing: ThawSpacing.base) {
            Toggle("Accent", isOn: binding(fields.usesAccentColor))
                .toggleStyle(.checkbox)
                .help("Follow the accent color set in System Settings \(Constants.menuArrow) Appearance")
            if !configuration[keyPath: fields.usesAccentColor] {
                ColorPicker(label, selection: binding(fields.color), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    private var opacitySlider: some View {
        LabeledContent("Opacity") {
            ThawSlider(
                value: binding(fields.opacity),
                in: 0 ... 1,
                step: 0.05,
                showsValue: false
            ) {
                Text(configuration[keyPath: fields.opacity], format: .percent.precision(.fractionLength(0)))
            }
        }
    }

    private func borderStylePicker(_ keyPath: WritableKeyPath<MenuBarAppearancePartialConfiguration, MenuBarBorderStyle>) -> some View {
        Picker("Border style", selection: binding(keyPath)) {
            ForEach(MenuBarBorderStyle.allCases, id: \.self) { style in
                Text(style.localized).tag(style)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var borderWidthPicker: some View {
        Picker("Border width", selection: binding(fields.borderWidth)) {
            Text("1 pt").tag(1.0)
            Text("2 pt").tag(2.0)
            Text("3 pt").tag(3.0)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    // MARK: Surface plumbing

    private var fields: FillSurfaceFields {
        switch fillKind {
        case .background:
            FillSurfaceFields(
                colorLabel: "Background",
                opacity: \.backgroundOpacity,
                glassStyle: \.backgroundGlassStyle,
                glassIsColored: \.backgroundGlassIsColored,
                usesAccentColor: \.backgroundUsesAccentColor,
                glassFollowsSystem: \.backgroundGlassFollowsSystem,
                color: \.backgroundColor,
                gradient: \.backgroundGradient,
                hasShadow: \.backgroundHasShadow,
                hasBorder: \.backgroundHasBorder,
                borderColor: \.backgroundBorderColor,
                borderWidth: \.backgroundBorderWidth
            )
        case .shapeFill:
            FillSurfaceFields(
                colorLabel: "Shape fill",
                opacity: \.tintOpacity,
                glassStyle: \.tintGlassStyle,
                glassIsColored: \.tintGlassIsColored,
                usesAccentColor: \.tintUsesAccentColor,
                glassFollowsSystem: \.tintGlassFollowsSystem,
                color: \.tintColor,
                gradient: \.tintGradient,
                hasShadow: \.hasShadow,
                hasBorder: \.hasBorder,
                borderColor: \.borderColor,
                borderWidth: \.borderWidth,
                borderStyle: \.borderStyle
            )
        }
    }

    /// The selected style, folded across the two kind enums.
    private var style: FillStyle {
        switch fillKind {
        case .background:
            switch configuration.backgroundKind {
            case .none: .none
            case .solid: .solid
            case .gradient: .gradient
            case .glass: .glass
            case .adaptive: .adaptive
            }
        case .shapeFill:
            switch configuration.tintKind {
            case .noTint: .none
            case .solid: .solid
            case .gradient: .gradient
            case .glass: .glass
            case .adaptive, .adaptiveGradient: .adaptive
            }
        }
    }

    /// Glass opacity controls tint strength, so show it only for tinted glass.
    private var showsOpacity: Bool {
        switch style {
        case .none: false
        case .glass: showsGlassColor && configuration[keyPath: fields.glassIsColored]
        case .solid, .gradient, .adaptive: true
        }
    }

    private var showsGlassColor: Bool {
        style == .glass && configuration[keyPath: fields.glassStyle].usesTint
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<MenuBarAppearancePartialConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { configuration[keyPath: keyPath] },
            set: { configuration[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Preview Button

/// Holding previews the inactive appearance mode on the real menu bar.
private struct HoldToPreviewButton: View {
    @Environment(AppState.self) private var appState

    let previewedAppearance: SystemAppearance

    var body: some View {
        Button("Hold to Preview") {
            // Intentionally empty: pressing, not clicking, drives the preview.
        }
        .buttonStyle(
            PressReportingButtonStyle { isPressed in
                let manager = appState.appearanceManager
                manager.previewConfiguration = isPressed ? previewConfiguration(of: manager) : nil
            }
        )
    }

    private func previewConfiguration(of manager: MenuBarAppearanceManager) -> MenuBarAppearancePartialConfiguration {
        switch previewedAppearance {
        case .light: manager.configuration.lightModeConfiguration
        case .dark: manager.configuration.darkModeConfiguration
        }
    }
}

/// Reports press and release to drive continuous previews rather than one-shot actions.
private struct PressReportingButtonStyle: ButtonStyle {
    let onPressChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .thawGlass(.control, in: Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChange(isPressed)
            }
    }
}

// MARK: - Thaw Bar Appearance Editor

/// The Thaw Bar's own look, shown on the Thaw Bar pane next to its preview.
struct ThawBarAppearanceEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    private var fillConfiguration: Binding<MenuBarAppearancePartialConfiguration> {
        Binding(
            get: { configuration.thawBarAppearance.fillConfiguration },
            set: { configuration.thawBarAppearance.fillConfiguration = $0 }
        )
    }

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
        ThawSection("Look") {
            Toggle("Own look", isOn: isEnabled)
                .annotation("Off, the \(Constants.displayName) Bar uses the menu bar's look from the Appearance pane.")

            if configuration.thawBarAppearance.overridesMenuBar {
                Toggle("Rounded corners", isOn: $configuration.thawBarAppearance.hasRoundedShape)
            }
        }
        if configuration.thawBarAppearance.overridesMenuBar {
            ThawSection {
                Text("Fill")
            } content: {
                UnlabeledAppearanceFillEditor(configuration: fillConfiguration, fillKind: .background)
            }
            ThawSection {
                Text("Tint")
            } content: {
                UnlabeledAppearanceFillEditor(configuration: fillConfiguration, fillKind: .shapeFill)
            } footer: {
                Text("Drawn over the fill.")
            }
        }
    }
}
