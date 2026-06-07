//
//  OnboardingMockups.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - Shared desktop pieces

private struct DesktopBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0x6e / 255, green: 0xab / 255, blue: 0xef / 255),
                Color(red: 0x3e / 255, green: 0x5a / 255, blue: 0xc1 / 255),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Menu bar tint and label colors that mirror how the real macOS menu bar
/// switches between a translucent dark material (dark mode) and a
/// translucent light material (light mode).
struct MenuBarTint {
    let colorScheme: ColorScheme

    var background: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.6)
    }

    var label: Color {
        colorScheme == .dark ? .white : .black
    }
}

private struct AppMenuLabels: View {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.logo")
                .font(.system(size: 11))
            Text(verbatim: "Finder")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle((tint ?? MenuBarTint(colorScheme: colorScheme).label).opacity(0.75))
        .padding(.leading, 12)
    }
}

/// The demo menu bar status items, split into the symbols that live in the
/// hidden section (left of the divider) and the always-visible ones. Shared by
/// the management and hotkeys mockups so both tell the same story.
enum MenuBarDemoItems {
    static let hidden = ["wifi", "battery.100", "speaker.wave.2"]
}

/// Mirrors the rightmost native macOS menu bar items — Control Center, then
/// the clock — so every mockup ends on the same recognizable anchor. The
/// clock shows only the hour and minute, matching a 24-hour-style reading
/// without the AM/PM suffix.
private struct MenuBarClockGroup: View {
    let tint: Color

    private var timeString: String {
        Date.now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "switch.2")
                .font(.system(size: 10))
            Text(timeString)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
    }
}

/// A horizontal row of menu bar status icons rendered at the shared demo size.
private struct MenuBarIconRow: View {
    let symbols: [String]
    let color: Color
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(symbols, id: \.self) { sym in
                Image(systemName: sym).font(.system(size: 10))
            }
        }
        .foregroundStyle(color)
    }
}

/// The Thaw control-item divider, styled after the "Dot" IceIcon
/// (DotFill / DotStroke) — a small filled circle between menu bar sections.
private struct MenuBarDividerDot: View {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color?

    var body: some View {
        Circle()
            .fill(tint ?? MenuBarTint(colorScheme: colorScheme).label)
            .frame(width: 6, height: 6)
    }
}

/// Dark capsule HUD for interactive controls overlaid on the desktop (not zoomed).
struct ControlHUD<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
    }
}

@MainActor
func delay(_ seconds: Double, action: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
}

/// Drives the scripted, auto-playing animation steps of a mockup. Each call to
/// `restart()` bumps a generation token; steps scheduled against an older token
/// are silently dropped, so re-entering a slide cleanly cancels any animation
/// still in flight from a previous visit.
@MainActor
final class MockupTimeline {
    private var generation = 0

    @discardableResult
    func restart() -> Int {
        generation += 1
        return generation
    }

    /// Runs `action` after `seconds`, unless the timeline has restarted since
    /// `generation` was captured.
    func schedule(after seconds: Double, generation gen: Int, _ action: @escaping @MainActor () -> Void) {
        delay(seconds) { [weak self] in
            guard let self, self.generation == gen else { return }
            action()
        }
    }
}

/// Where — and how far — a slide's mockup zooms into its MacBook screen.
/// `corner` is expressed in the zoomed view's own unit coordinates
/// (0,0 = top-leading, 1,1 = bottom-trailing) and names the feature the
/// camera should push into.
struct OnboardingZoomSpec {
    var scale: CGFloat
    var corner: UnitPoint

    static let none = OnboardingZoomSpec(scale: 1, corner: .center)

    /// The MacBook zooms in once, on the first feature slide, and then holds
    /// that framing for the rest of the tour — only the screen content and HUD
    /// crossfade between slides, so a single shared target keeps the laptop
    /// from jumping around.
    static let featureTour = OnboardingZoomSpec(scale: 2.0, corner: UnitPoint(x: 1.1, y: 0.0))
}

/// Zooms a view into a target corner by scaling about that corner. Anchoring
/// the scale at the target point — rather than scaling from the center and
/// translating afterwards — keeps that point in place as everything around it
/// grows, which guarantees the zoomed content always fully covers the frame
/// (translating a centered zoom toward an off-center point would instead drag
/// the content's far edge into view, exposing the background behind it).
extension View {
    func zoomingIntoCorner(_ zoomed: Bool, scale: CGFloat, corner: UnitPoint) -> some View {
        scaleEffect(zoomed ? scale : 1.0, anchor: corner)
            .animation(.spring(duration: 0.7, bounce: 0.1), value: zoomed)
    }
}

// MARK: - Welcome

struct OnboardingWelcomeMockup: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.4), radius: 28, y: 14)
                    .scaleEffect(appear ? 1 : 0.85)
                    .opacity(appear ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { appear = true }
        }
    }
}

// MARK: - Menu Bar Management

//
// Zooms into the right side of the menu bar. The Thaw capsule divider is the
// tappable toggle — matching ControlItem.HidingState going from
// .hideSection → .showSection. Hidden items (left of divider) fade + slide
// when hidden. The HUD label below floats outside the laptop and stays put
// while the screen zooms in around the divider.

@MainActor
final class ManagementMockupModel: ObservableObject {
    @Published var itemsHidden = true
    private let timeline = MockupTimeline()

    func restart() {
        let gen = timeline.restart()
        itemsHidden = true
        timeline.schedule(after: 1.10, generation: gen) { [weak self] in
            withAnimation(.spring(duration: 0.45)) { self?.itemsHidden = false }
        }
    }

    func toggle() {
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { itemsHidden.toggle() }
    }
}

struct ManagementScreen: View {
    @ObservedObject var model: ManagementMockupModel
    @Environment(\.colorScheme) private var colorScheme

    private var tint: MenuBarTint {
        MenuBarTint(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DesktopBackground()
            menuBar
        }
    }

    private var menuBar: some View {
        HStack(spacing: 0) {
            AppMenuLabels()
            Spacer()

            MenuBarIconRow(symbols: MenuBarDemoItems.hidden, color: .white.opacity(0.85))
                .opacity(model.itemsHidden ? 0 : 1)
                .offset(x: model.itemsHidden ? 16 : 0)
                .animation(.spring(duration: 0.45, bounce: 0.1), value: model.itemsHidden)
                .padding(.trailing, 8)

            Button {
                model.toggle()
            } label: {
                ZStack {
                    Color.clear.frame(width: 22, height: 24)
                    MenuBarDividerDot(tint: .white.opacity(0.85))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)

            MenuBarClockGroup(tint: .white.opacity(0.9))
                .padding(.trailing, 8)
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(tint.background)
    }
}

struct ManagementHUD: View {
    @ObservedObject var model: ManagementMockupModel

    var body: some View {
        ControlHUD {
            Label(
                model.itemsHidden ? "Click divider to reveal" : "Click again to hide",
                systemImage: "hand.tap"
            )
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.85))
            .animation(nil, value: model.itemsHidden)
        }
    }
}

// MARK: - Menu Bar Appearance

//
// Zooms into the styled bar to show off solid, gradient, and rounded looks —
// matching MenuBarTintKind (solid, gradient) and MenuBarShapeKind (capsule).
// The style picker HUD floats unzoomed below the laptop.

@MainActor
final class AppearanceMockupModel: ObservableObject {
    static let styleLabels = ["Default", "Gradient", "Rounded"]

    @Published var styleIndex = 0
    private let timeline = MockupTimeline()

    func restart() {
        let gen = timeline.restart()
        styleIndex = 0
        timeline.schedule(after: 1.10, generation: gen) { [weak self] in self?.selectStyle(1) }
        timeline.schedule(after: 2.85, generation: gen) { [weak self] in self?.selectStyle(2) }
    }

    func selectStyle(_ index: Int) {
        withAnimation(.spring(duration: 0.4)) { styleIndex = index }
    }
}

struct AppearanceScreen: View {
    @ObservedObject var model: AppearanceMockupModel
    @Environment(\.colorScheme) private var colorScheme

    private var tint: MenuBarTint {
        MenuBarTint(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DesktopBackground()
            styledMenuBar
        }
    }

    private func barIcons(tint: Color) -> some View {
        HStack(spacing: 7) {
            MenuBarIconRow(symbols: ["wifi", "battery.100"], color: tint.opacity(0.9), spacing: 7)
            MenuBarDividerDot(tint: tint.opacity(0.85))
            MenuBarClockGroup(tint: tint.opacity(0.9))
        }
    }

    @ViewBuilder
    private var styledMenuBar: some View {
        switch model.styleIndex {
        case 1:
            HStack(spacing: 0) {
                AppMenuLabels(tint: .white)
                Spacer()
                barIcons(tint: .white).padding(.horizontal, 9)
            }
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(
                colors: [.blue.opacity(0.75), .purple.opacity(0.75)],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .transition(.opacity.combined(with: .scale(scale: 0.98)))

        case 2:
            // The "Rounded" style draws no full-width bar — only the pill
            // around the menu bar items floats over the desktop.
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    AppMenuLabels(tint: .white)
                    Spacer()
                }
                .frame(height: 24)
                .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    barIcons(tint: .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(LinearGradient(
                            colors: [.teal.opacity(0.8), .cyan.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .clipShape(Capsule())
                        .padding(.trailing, 6)
                        .padding(.top, 2)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))

        default:
            HStack(spacing: 0) {
                AppMenuLabels(tint: tint.label)
                Spacer()
                barIcons(tint: .white).padding(.horizontal, 9)
            }
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(tint.background)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}

struct AppearanceHUD: View {
    @ObservedObject var model: AppearanceMockupModel

    var body: some View {
        ControlHUD {
            HStack(spacing: 0) {
                ForEach(Array(AppearanceMockupModel.styleLabels.enumerated()), id: \.offset) { i, label in
                    Button(label) {
                        model.selectStyle(i)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: model.styleIndex == i ? .semibold : .regular))
                    .foregroundStyle(model.styleIndex == i ? Color.white : Color.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(model.styleIndex == i ? Color.white.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Hotkeys & Automation

//
// Demonstrates the trigger loop: key combo toast appears, then the hidden
// section snaps open — matching MenuBarSection.show() / .hide() flow.

@MainActor
final class HotkeysMockupModel: ObservableObject {
    @Published var itemsVisible = false
    private let timeline = MockupTimeline()

    func restart() {
        let gen = timeline.restart()
        itemsVisible = false
        timeline.schedule(after: 1.00, generation: gen) { [weak self] in self?.triggerHotkey() }
    }

    func triggerHotkey() {
        withAnimation(.spring(duration: 0.4, bounce: 0.1)) { itemsVisible.toggle() }
    }
}

struct HotkeysScreen: View {
    @ObservedObject var model: HotkeysMockupModel
    @Environment(\.colorScheme) private var colorScheme

    private var tint: MenuBarTint {
        MenuBarTint(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DesktopBackground()
            menuBar
        }
    }

    private var menuBar: some View {
        HStack(spacing: 0) {
            AppMenuLabels()
            Spacer()
            MenuBarIconRow(symbols: MenuBarDemoItems.hidden, color: .white.opacity(0.85))
                .opacity(model.itemsVisible ? 1 : 0)
                .offset(x: model.itemsVisible ? 0 : 14)
                .animation(.spring(duration: 0.4, bounce: 0.1), value: model.itemsVisible)
                .padding(.trailing, 8)
            MenuBarDividerDot(tint: .white.opacity(0.85))
                .padding(.trailing, 8)

            MenuBarClockGroup(tint: .white.opacity(0.9))
                .padding(.trailing, 8)
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(tint.background)
    }
}

struct HotkeysHUD: View {
    @ObservedObject var model: HotkeysMockupModel

    var body: some View {
        ControlHUD {
            Button { model.triggerHotkey() } label: {
                Label {
                    Text(verbatim: "Press ⌃ Space")
                } icon: {
                    Image(systemName: "keyboard")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Profiles

//
// Mirrors ProfileManager's macOS Focus integration: when the system Focus
// mode changes, Thaw auto-activates the linked profile and swaps the entire
// menu bar layout — shown here via a Focus indicator triggering a banner
// and a profile-driven item swap.

@MainActor
final class ProfilesMockupModel: ObservableObject {
    struct FocusMode {
        let name: String
        let symbol: String
        let items: [String]
    }

    /// Each profile shows a different mix of real macOS menu bar status items
    /// (Wi-Fi, Sound, AirPods, Battery, Bluetooth, Do Not Disturb, …) — the
    /// same kind of system icons Thaw actually manages — so swapping profiles
    /// visibly reshuffles the bar rather than showing made-up app icons.
    static let focusModes: [FocusMode] = [
        FocusMode(name: "Work", symbol: "briefcase.fill", items: ["wifi", "airpods", "battery.75"]),
        FocusMode(name: "Personal", symbol: "house.fill", items: ["speaker.wave.2.fill", "airpods", "wifi"]),
        FocusMode(name: "Travel", symbol: "airplane", items: ["wifi.slash", "personalhotspot", "battery.25"]),
    ]

    @Published var focusIndex = 0
    private let timeline = MockupTimeline()

    var active: FocusMode {
        Self.focusModes[focusIndex]
    }

    func restart() {
        let gen = timeline.restart()
        focusIndex = 0
        timeline.schedule(after: 1.10, generation: gen) { [weak self] in self?.switchFocus(to: 1) }
        timeline.schedule(after: 2.85, generation: gen) { [weak self] in self?.switchFocus(to: 2) }
    }

    func switchFocus(to index: Int) {
        guard index != focusIndex else { return }
        withAnimation(.spring(duration: 0.35)) { focusIndex = index }
    }
}

struct ProfilesScreen: View {
    @ObservedObject var model: ProfilesMockupModel
    @Environment(\.colorScheme) private var colorScheme

    private var tint: MenuBarTint {
        MenuBarTint(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DesktopBackground()
            menuBar
        }
    }

    private var menuBar: some View {
        HStack(spacing: 0) {
            AppMenuLabels()
            Spacer()

            MenuBarIconRow(symbols: model.active.items, color: .white.opacity(0.9))
                .id(model.focusIndex)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(.spring(duration: 0.35), value: model.focusIndex)
                .padding(.trailing, 8)

            MenuBarDividerDot(tint: .white.opacity(0.85))
                .padding(.trailing, 8)

            // Mirrors the active Focus mode's own symbol so the menu bar
            // status item visibly updates alongside the showcased profile.
            Image(systemName: model.active.symbol)
                .font(.system(size: 9))
                .foregroundStyle(.white)
                .id(model.focusIndex)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                .animation(.spring(duration: 0.35), value: model.focusIndex)
                .padding(.trailing, 8)

            MenuBarClockGroup(tint: .white.opacity(0.9))
                .padding(.trailing, 8)
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(tint.background)
    }
}

struct ProfilesHUD: View {
    @ObservedObject var model: ProfilesMockupModel

    var body: some View {
        ControlHUD {
            HStack(spacing: 0) {
                ForEach(Array(ProfilesMockupModel.focusModes.enumerated()), id: \.offset) { i, mode in
                    Button {
                        model.switchFocus(to: i)
                    } label: {
                        Label(mode.name, systemImage: mode.symbol)
                            .font(.system(size: 11, weight: model.focusIndex == i ? .semibold : .regular))
                            .foregroundStyle(model.focusIndex == i ? Color.white : Color.white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(model.focusIndex == i ? Color.white.opacity(0.15) : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
