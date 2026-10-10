//
//  SwapBarManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import SwiftUI
import ThawUI

// MARK: - SwapBarManager

/// Owns the Swap bar: a floating capsule at the bottom of the pointer's
/// display carrying the group swap, the active profile, the section toggles
/// and zen mode. Shown while enableSwapBar is on.
///
/// Follows the pointer between displays and never activates the app, but
/// takes key focus so its controls work from the keyboard.
@MainActor
@Observable
final class SwapBarManager {
    @ObservationIgnored private weak var appState: AppState?

    /// The settings slice this manager observes, injected at setup.
    @ObservationIgnored private var advancedSettings: AdvancedSettings?
    @ObservationIgnored private var panel: SwapBarPanel?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var pointerMonitor: EventMonitor?
    @ObservationIgnored private var currentDisplayID: CGDirectDisplayID?

    /// Read live from settings so the bar tracks the switch.
    private var isEnabled: Bool {
        advancedSettings?.enableSwapBar ?? false
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        advancedSettings = appState.settings.advanced
        cancellables = [
            observeSettingFlips(),
            observeDisplayChanges(),
        ]
    }

    // MARK: Observation

    private func observeSettingFlips() -> AnyCancellable {
        guard let advanced = advancedSettings else { return AnyCancellable {} }
        return advanced.observe(\.enableSwapBar) { [weak self] _ in
            self?.refresh()
        }
    }

    /// A display or Space change moves the bottom edge; re-place rather than
    /// trust the old frame.
    private func observeDisplayChanges() -> AnyCancellable {
        let cancellable = Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.activeSpaceDidChangeNotification
            ),
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        )
        .sink { [weak self] _ in
            self?.currentDisplayID = nil
            self?.reposition()
        }
        return AnyCancellable { cancellable.cancel() }
    }

    private func refresh() {
        if isEnabled {
            show()
        } else {
            hide()
        }
    }

    // MARK: Presentation

    private func show() {
        guard let appState else { return }
        let panel = panel ?? SwapBarPanel()
        self.panel = panel
        panel.present(SwapBarView(appState: appState))
        reposition()
        panel.orderFrontRegardless()

        if pointerMonitor == nil {
            pointerMonitor = EventMonitor.startPassive(
                for: [.mouseMoved],
                scope: .universal
            ) { [weak self] _ in
                self?.followPointerIfNeeded()
            }
        }
    }

    private func hide() {
        pointerMonitor?.stop()
        pointerMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        currentDisplayID = nil
    }

    /// Where to centre a strip of width under screen's menu bar.
    ///
    /// Uses auxiliaryTopRightArea, where the status items live, clamped so a
    /// wider strip stays on screen.
    static nonisolated func centerX(under screen: NSScreen, width: CGFloat) -> CGFloat {
        let span = screen.auxiliaryTopRightArea ?? screen.frame
        let centered = span.midX - width / 2
        return min(max(centered, screen.frame.minX), screen.frame.maxX - width)
    }

    /// Moves the bar only when the pointer has crossed to another display;
    /// every other pointer event is a cheap comparison.
    private func followPointerIfNeeded() {
        guard let screen = NSScreen.screenWithMouse, screen.displayID != currentDisplayID else {
            return
        }
        reposition(on: screen)
    }

    private func reposition(on screen: NSScreen? = nil) {
        guard let panel, let screen = screen ?? NSScreen.screenWithMouse ?? NSScreen.main else {
            return
        }
        currentDisplayID = screen.displayID
        let size = panel.fittingContentSize
        // Centred under the status items, since screen centre is the notch.
        let frame = NSRect(
            x: Self.centerX(under: screen, width: size.width),
            y: screen.visibleFrame.maxY - size.height - 8,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }
}

// MARK: - SwapBarPanel

/// Floating, non-activating but key-capable panel. Only ever ordered front
/// regardless, so it takes key on a deliberate click alone.
final class SwapBarPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
        ]
        isMovableByWindowBackground = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    /// Escape resigns key by ordering out and back; closing would change a
    /// setting. No animation, so nothing flashes.
    override func cancelOperation(_: Any?) {
        guard isKeyWindow else { return }
        orderOut(nil)
        orderFrontRegardless()
    }

    var fittingContentSize: CGSize {
        contentView?.fittingSize ?? CGSize(width: 320, height: 56)
    }

    func present(_ rootView: SwapBarView) {
        if let existing = contentView as? SwapBarHostingView {
            existing.rootView = rootView
        } else {
            contentView = SwapBarHostingView(rootView: rootView)
        }
    }
}

/// Accepts the first click, so a press acts before the panel is key.
private final class SwapBarHostingView: NSHostingView<SwapBarView> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}

// MARK: - SwapBarView

/// The bar itself: the swap control first, then the profile switcher, the two
/// concealable sections and zen mode as toggles, on panel-tier glass in a
/// capsule.
struct SwapBarView: View {
    private static let diagLog = DiagLog(category: "SwapBar")

    let appState: AppState

    /// Bumped whenever a section is revealed or hidden, since isHidden itself
    /// is not observed.
    @State private var sectionRevision = 0

    /// Every signal that can change a section's hidden state, merged: the
    /// runtime controller's revealed-section publisher on macOS 27, and the
    /// control items' hiding state on the classic backend.
    ///
    /// Stored, not computed: these re-emit on subscribe, so a fresh instance
    /// per body would re-render forever and cancel every click.
    let sectionStateChanges: AnyPublisher<Void, Never>

    init(appState: AppState) {
        self.appState = appState
        let manager = appState.menuBarManager
        var publishers: [AnyPublisher<Void, Never>] = [
            manager.revealedSectionChanges.map { _ in () }.eraseToAnyPublisher(),
        ]
        for name in [MenuBarSection.Name.hidden, .alwaysHidden] {
            if let controlItem = manager.section(withName: name)?.controlItem {
                publishers.append(controlItem.$state.map { _ in () }.eraseToAnyPublisher())
            }
        }
        self.sectionStateChanges = Publishers.MergeMany(publishers)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private var profileManager: ProfileManager {
        appState.profileManager
    }

    private var activeProfileName: String {
        guard let id = profileManager.activeProfileID,
              let profile = profileManager.profiles.first(where: { $0.id == id })
        else {
            return String(localized: "No profile")
        }
        return profile.name
    }

    var body: some View {
        HStack(spacing: ThawSpacing.tight) {
            swapControl

            Divider()
                .frame(height: 18)
                .padding(.horizontal, ThawSpacing.tight)

            sectionToggle(.hidden, symbol: "eye", label: "Hidden items")
            sectionToggle(.alwaysHidden, symbol: "eye.slash", label: "Always Hidden items")
            zenToggle

            Divider()
                .frame(height: 18)
                .padding(.horizontal, ThawSpacing.tight)

            profileMenu

            Divider()
                .frame(height: 18)
                .padding(.horizontal, ThawSpacing.tight)

            closeButton
        }
        .padding(.horizontal, ThawSpacing.row)
        .padding(.vertical, 7)
        .thawGlass(.panel, in: Capsule(style: .continuous))
        // Room for the glass's own shadow; the window itself draws none.
        .padding(ThawSpacing.gutter)
        .fixedSize()
        .onReceive(sectionStateChanges) { _ in
            sectionRevision &+= 1
        }
    }

    /// One press trades the two groups, the next trades them back. Labeled,
    /// since an icon alone would not say what it does.
    private var swapControl: some View {
        let manager = appState.menuBarManager
        let isOn = manager.isSwapped
        return Button {
            if !manager.toggleSwap() {
                Self.diagLog.debug("swap bar: swap refused")
            }
        } label: {
            HStack(spacing: ThawSpacing.compact) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(ThawType.symbol.weight(.medium))
                Text(isOn ? "Swap back" : "Swap")
                    .font(ThawType.label)
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .padding(.horizontal, ThawSpacing.inset)
            .padding(.vertical, ThawSpacing.compact)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        // A tinted fill, not a second glass layer: glass on glass refracts.
        .background {
            if isOn {
                Capsule(style: .continuous).fill(Color.accentColor.opacity(0.18))
            }
        }
        .thawSelectionCue(isSelected: isOn, in: Capsule(style: .continuous))
        .thawHoverLift()
        .help("Swap the shown and hidden menu bar items")
        .accessibilityLabel("Swap shown and hidden items")
        .accessibilityValue(Text(isOn ? "Swapped" : "Not swapped"))
    }

    /// Closing disables the bar; the Settings switch is the only way back.
    private var closeButton: some View {
        Button {
            appState.settings.advanced.enableSwapBar = false
        } label: {
            Image(systemName: "xmark")
                .font(ThawType.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .thawHoverLift()
        .help("Close the Swap Bar")
        .accessibilityLabel("Close")
    }

    private var profileMenu: some View {
        Menu {
            ForEach(profileManager.profiles) { profile in
                Button {
                    apply(profile)
                } label: {
                    if profile.id == profileManager.activeProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        } label: {
            HStack(spacing: ThawSpacing.compact) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(ThawType.symbol.weight(.medium))
                Text(activeProfileName)
                    .font(ThawType.label)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(ThawType.micro.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ThawSpacing.row)
            .padding(.vertical, ThawSpacing.compact)
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .thawHoverLift()
    }

    private func sectionToggle(_ name: MenuBarSection.Name, symbol: String, label: LocalizedStringKey) -> some View {
        let section = appState.menuBarManager.section(withName: name)
        let isShown = section.map { !$0.isHidden } ?? false
        return SwapBarButton(symbol: symbol, label: label, isOn: isShown) {
            section?.toggle()
        }
        .disabled(section?.isEnabled != true)
    }

    private var zenToggle: some View {
        SwapBarButton(symbol: "moon", label: "Zen Mode", isOn: appState.menuBarManager.isZenModeActive) {
            if !appState.menuBarManager.toggleZenMode() {
                Self.diagLog.debug("swap bar: zen toggle refused")
            }
        }
    }

    /// Switches profiles, answering a failed load through the HUD: the bar
    /// has no room for an error row and no window to put one in.
    private func apply(_ metadata: ProfileMetadata) {
        guard metadata.id != profileManager.activeProfileID else {
            return
        }
        let profile: Profile
        do {
            profile = try profileManager.loadProfile(id: metadata.id)
        } catch {
            Self.diagLog.error("swap bar: profile \(metadata.id) failed to load: \(error)")
            ThawHUD.show(symbol: "exclamationmark.triangle", text: "Profile not applied")
            return
        }
        let previousID = profileManager.activeProfileID
        profileManager.activeProfileID = metadata.id
        profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
    }
}

/// One round toggle on the bar. A tinted well when on, a plain symbol when
/// off, lifted on hover like every other control in the bar.
private struct SwapBarButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ThawType.symbol.weight(.medium))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            if isOn {
                Circle().fill(Color.accentColor.opacity(0.18))
            }
        }
        // Under Differentiate Without Color the tinted well alone is not a
        // mark; the cue rings the toggle and sets the selected trait.
        .thawSelectionCue(isSelected: isOn, in: Circle())
        .thawHoverLift()
        .help(label)
        .accessibilityLabel(label)
    }
}
