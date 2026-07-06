//
//  TourMockups.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Observation
import SwiftUI

/// The demo menu bar's background treatment — mirrors Thaw's real
/// `MenuBarShapeKind` options. Real Thaw calls these "Full" and "Split" (a
/// single bar-wide shape vs. two independent leading/trailing shapes); this
/// demo labels the split option "Pills" since that's what it looks like —
/// two separate floating capsules with a gap between them.
private enum DemoBarStyle {
    case regular
    case gradient
    case pills

    var labelTint: Color {
        switch self {
        case .regular: .primary
        case .gradient, .pills: .white
        }
    }
}

/// A stand-in macOS menu bar: app label on the left, a cluster of "hidden"
/// items that can fade in/out, a tappable divider (Thaw's control item), and
/// a trailing cluster of always-visible items plus a clock. Shared by the
/// management, appearance, hotkeys, and profiles slides so they all read as
/// the same bar changing behavior, rather than four unrelated mockups.
///
/// `.pills` renders as two independent capsules (leading label, trailing
/// controls) with a real gap between them — matching Thaw's actual "Split"
/// shape kind, where the leading and trailing sides are separate shapes
/// rather than one bar-wide one.
private struct DemoMenuBar: View {
    var hiddenSymbols: [String]
    var hiddenShown: Bool
    var trailingSymbols: [String]
    var style: DemoBarStyle = .regular
    var onDividerTap: (() -> Void)?

    private var hiddenItemsCluster: some View {
        HStack(spacing: 8) {
            ForEach(hiddenSymbols, id: \.self) { symbol in
                GlassIconBubble(symbol: symbol, size: 24, tint: style.labelTint, showBackground: false)
            }
        }
        .opacity(hiddenShown ? 1 : 0)
        .offset(x: hiddenShown ? 0 : 16)
        .animation(.spring(duration: 0.45, bounce: 0.15), value: hiddenShown)
    }

    private var dividerButton: some View {
        Button {
            onDividerTap?()
        } label: {
            Circle()
                .fill(style.labelTint.opacity(0.85))
                .frame(width: 6, height: 6)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private var trailingCluster: some View {
        HStack(spacing: 8) {
            ForEach(trailingSymbols, id: \.self) { symbol in
                GlassIconBubble(symbol: symbol, size: 24, tint: style.labelTint, showBackground: false)
            }
            Text(Date.now.formatted(.dateTime.hour().minute()))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(style.labelTint.opacity(0.85))
        }
    }

    var body: some View {
        Group {
            if style == .pills {
                HStack(spacing: 14) {
                    HStack(spacing: 7) {
                        Image(systemName: "apple.logo").font(.system(size: 12, weight: .medium))
                        Text("Finder").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(LinearGradient(colors: [.indigo, .blue], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 3)

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        hiddenItemsCluster
                        dividerButton
                        trailingCluster
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
                }
                .padding(.horizontal, 30)
                .animation(.spring(duration: 0.4), value: hiddenSymbols)
            } else {
                HStack(spacing: 0) {
                    HStack(spacing: 7) {
                        Image(systemName: "apple.logo").font(.system(size: 12, weight: .medium))
                        Text("Finder").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(style.labelTint.opacity(0.85))
                    .padding(.leading, 16)

                    Spacer(minLength: 12)

                    hiddenItemsCluster
                    dividerButton
                    trailingCluster
                        .padding(.trailing, 16)
                }
                .frame(height: 38)
                .frame(maxWidth: .infinity)
                .background {
                    switch style {
                    case .regular:
                        Capsule().fill(.regularMaterial)
                    case .gradient:
                        Capsule().fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    case .pills:
                        EmptyView()
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
                .padding(.horizontal, 30)
                .animation(.spring(duration: 0.4), value: hiddenSymbols)
            }
        }
    }
}

/// The floating glass capsule HUD used below each demo bar to label or drive
/// its interaction — mirrors the "ControlHUD" floating labels in Thaw's real
/// onboarding tour.
private struct SlideHUD<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
    }
}

// MARK: - Menu Bar Management

@MainActor
@Observable
final class ThawManagementMockupModel {
    var itemsHidden = true
    @ObservationIgnored private var restartTask: Task<Void, Never>?

    func restart() {
        restartTask?.cancel()
        itemsHidden = true
        restartTask = Task {
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.45)) { itemsHidden = false }
        }
    }

    func toggle() {
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { itemsHidden.toggle() }
    }
}

struct ManagementSlideMockup: View {
    let model: ThawManagementMockupModel
    var onInteraction: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            DemoMenuBar(
                hiddenSymbols: ["wifi", "battery.100", "speaker.wave.2"],
                hiddenShown: !model.itemsHidden,
                trailingSymbols: ["magnifyingglass"],
                onDividerTap: {
                    onInteraction()
                    model.toggle()
                }
            )
            SlideHUD {
                Label(model.itemsHidden ? "Click to show" : "Click to hide", systemImage: "hand.tap")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Menu Bar Appearance

@MainActor
@Observable
final class ThawAppearanceMockupModel {
    static let styleLabels = ["Default", "Gradient", "Pills"]

    var styleIndex = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?

    func restart() {
        restartTask?.cancel()
        styleIndex = 0
        restartTask = Task {
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            select(1)

            try? await Task.sleep(for: .seconds(1.75))
            guard !Task.isCancelled else { return }
            select(2)
        }
    }

    func select(_ index: Int) {
        withAnimation(.spring(duration: 0.4)) { styleIndex = index }
    }
}

struct AppearanceSlideMockup: View {
    let model: ThawAppearanceMockupModel
    var onInteraction: () -> Void = {}

    private var style: DemoBarStyle {
        switch model.styleIndex {
        case 1: .gradient
        case 2: .pills
        default: .regular
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            DemoMenuBar(
                hiddenSymbols: [],
                hiddenShown: false,
                trailingSymbols: ["wifi", "battery.100"],
                style: style
            )
            SlideHUD {
                HStack(spacing: 0) {
                    ForEach(ThawAppearanceMockupModel.styleLabels, id: \.self) { label in
                        let i = ThawAppearanceMockupModel.styleLabels.firstIndex(of: label) ?? 0
                        Button(label) {
                            onInteraction()
                            model.select(i)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: model.styleIndex == i ? .semibold : .regular))
                        .foregroundStyle(model.styleIndex == i ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(model.styleIndex == i ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Hotkeys & Automation

@MainActor
@Observable
final class ThawHotkeysMockupModel {
    var itemsVisible = false
    @ObservationIgnored private var restartTask: Task<Void, Never>?

    func restart() {
        restartTask?.cancel()
        itemsVisible = false
        restartTask = Task {
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            trigger()
        }
    }

    func trigger() {
        withAnimation(.spring(duration: 0.4, bounce: 0.1)) { itemsVisible.toggle() }
    }
}

struct HotkeysSlideMockup: View {
    let model: ThawHotkeysMockupModel
    var onInteraction: () -> Void = {}

    private func triggerFromUser() {
        onInteraction()
        model.trigger()
    }

    var body: some View {
        VStack(spacing: 18) {
            DemoMenuBar(
                hiddenSymbols: ["wifi", "battery.100", "speaker.wave.2"],
                hiddenShown: model.itemsVisible,
                trailingSymbols: ["magnifyingglass"],
                onDividerTap: triggerFromUser
            )
            SlideHUD {
                Button(action: triggerFromUser) {
                    Label("Press ⌃ Space", systemImage: "keyboard")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(" ", modifiers: .control)
            }
        }
    }
}

// MARK: - Profiles

@MainActor
@Observable
final class ThawProfilesMockupModel {
    struct FocusMode {
        let name: String
        let symbol: String
        let items: [String]
    }

    static let focusModes: [FocusMode] = [
        FocusMode(name: "Work", symbol: "briefcase.fill", items: ["wifi", "airpods", "battery.75"]),
        FocusMode(name: "Personal", symbol: "house.fill", items: ["speaker.wave.2", "airpods", "wifi"]),
        FocusMode(name: "Travel", symbol: "airplane", items: ["wifi.slash", "personalhotspot", "battery.25"]),
    ]

    var focusIndex = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    var active: FocusMode {
        Self.focusModes[focusIndex]
    }

    func restart() {
        restartTask?.cancel()
        focusIndex = 0
        restartTask = Task {
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            select(1)

            try? await Task.sleep(for: .seconds(1.75))
            guard !Task.isCancelled else { return }
            select(2)
        }
    }

    func select(_ index: Int) {
        guard index != focusIndex else { return }
        withAnimation(.spring(duration: 0.35)) { focusIndex = index }
    }
}

struct ProfilesSlideMockup: View {
    let model: ThawProfilesMockupModel
    var onInteraction: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            DemoMenuBar(
                hiddenSymbols: model.active.items,
                hiddenShown: true,
                trailingSymbols: [model.active.symbol]
            )
            .id(model.focusIndex)
            .transition(.opacity)

            SlideHUD {
                HStack(spacing: 0) {
                    ForEach(ThawProfilesMockupModel.focusModes, id: \.name) { mode in
                        let i = ThawProfilesMockupModel.focusModes.firstIndex { $0.name == mode.name } ?? 0
                        Button {
                            onInteraction()
                            model.select(i)
                        } label: {
                            Label(mode.name, systemImage: mode.symbol)
                                .font(.system(size: 12, weight: model.focusIndex == i ? .semibold : .regular))
                                .foregroundStyle(model.focusIndex == i ? Color.primary : Color.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(model.focusIndex == i ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Integrations

/// One integration card. Icon resolution, in order:
/// 1. A bundled asset — the real icon, shipped with the app, so it always
///    renders correctly regardless of what's installed on whatever machine
///    runs this demo (unlike a runtime lookup, which only works on a Mac
///    that happens to have the app installed).
/// 2. A permission-free runtime lookup by name, in case the bundled asset
///    is missing for some reason.
/// 3. An SF Symbol, so the slide still reads fine either way.
private struct IntegrationCard: View {
    let appName: String
    let subtitle: String
    let bundledAssetName: String?
    let fallbackSymbol: String

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let bundledAssetName {
                    Image(bundledAssetName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)

            Text(appName)
                .font(.system(size: 13, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct IntegrationsSlideMockup: View {
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            IntegrationCard(
                appName: "Droppy",
                subtitle: "Install Thaw as a Droplet; stays updated automatically",
                bundledAssetName: "DroppyIcon",
                fallbackSymbol: "arrow.triangle.2.circlepath"
            )
            IntegrationCard(
                appName: "Raycast",
                subtitle: "Toggle hidden items or search, no mouse needed",
                bundledAssetName: "RaycastIcon",
                fallbackSymbol: "bolt.fill"
            )
        }
        .padding(.horizontal, 30)
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { appeared = true }
        }
    }
}
