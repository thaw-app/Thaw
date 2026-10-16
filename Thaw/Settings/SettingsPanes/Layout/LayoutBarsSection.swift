//
//  LayoutBarsSection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The drag-to-arrange layout bars, shared by ``MenuBarLayoutSettingsPane``
/// and ``SimpleModeSettingsPane``.
struct LayoutBarsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState: AppState
    let itemManager: MenuBarItemManager

    @State private var loadDeadlineReached = false
    /// Bumped whenever the screen the editor reflects may have changed, so
    /// the display title above the bars re-evaluates.
    @State private var displayTitleRefreshToken = 0

    private let diagLog = DiagLog(category: "MenuBarLayoutPane")

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    private var areControlItemsDisabledBySystem: Bool {
        itemManager.areControlItemsMissing
    }

    var body: some View {
        IceSection {
            if let editingDisplayName {
                Text("Active display: \(editingDisplayName)")
                    // Redrawn on the same signals as LayoutBarPaddingView's
                    // notch indicator, so title and bars agree on the screen.
                    .id(displayTitleRefreshToken)
            }
        } content: {
            layoutBars
        } footer: {
            // Interpolated so the four localized strings wrap as one
            // paragraph (Text + is deprecated on macOS 26).
            Text("\(Text("Drag to arrange your menu bar items into different sections.")) \(Text("Move the New Items badge to choose where newly detected items will appear.")) \(Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")) \(Text("Click an item to open it. Hidden items are temporarily revealed."))")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            displayTitleRefreshToken &+= 1
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didActivateApplicationNotification)
        ) { _ in
            displayTitleRefreshToken &+= 1
        }
    }

    /// The name of the display whose layout the bars below are showing.
    ///
    /// The editor always reflects the screen that owns the menu bar. With an
    /// external primary display that isn't the screen users expect (the notch
    /// placeholder vanishes), so the title names it.
    private var editingDisplayName: String? {
        guard NSScreen.screens.count > 1 else {
            return nil
        }
        let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        let name = screen?.localizedName.trimmingCharacters(in: .whitespaces)
        return (name?.isEmpty ?? true) ? nil : name
    }

    private var layoutBars: some View {
        VStack(spacing: 20) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
        .opacity(hasItems ? 1 : 0.75)
        .blur(radius: hasItems ? 0 : 5)
        .allowsHitTesting(hasItems)
        .overlay {
            if !hasItems {
                VStack(spacing: 8) {
                    if loadDeadlineReached {
                        VStack(spacing: 4) {
                            if areControlItemsDisabledBySystem {
                                Text("One or more section dividers are hidden by macOS")
                                Text("Check System Settings > Menu Bar and enable \(Constants.displayName)")
                                    .font(.callout.bold())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Unable to load menu bar items")
                            }
                        }
                    } else {
                        Text("Loading menu bar items…")
                        ProgressView()
                    }
                }
            }
        }
        .task(id: hasItems) {
            loadDeadlineReached = false

            guard !hasItems else {
                return
            }

            // Only the image cache needs Screen Recording; the item cache, and
            // therefore the overlay's own resolution, does not. Bailing out on
            // the permission left the spinner up forever.
            let hasScreenRecording = ScreenCapture.cachedCheckPermissions()

            diagLog.debug("Preloading menu bar layout caches (hasItems=\(self.hasItems), screenRecording=\(hasScreenRecording))")

            async let preloadCaches: Void = preloadLayoutCaches(includingImages: hasScreenRecording)

            try? await Task.sleep(for: .seconds(3))

            if !Task.isCancelled, !hasItems {
                loadDeadlineReached = true
                diagLog.error("Menu bar layout failed to load items after 3s timeout. cacheItems: \(itemManager.itemCache.managedItems.count), images: \(appState.imageCache.images.count), displayID: \(itemManager.itemCache.displayID.map { "\($0)" } ?? "nil")")
            }

            await preloadCaches
        }
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            VStack(alignment: .leading) {
                HStack {
                    Text(name.localized)
                        .font(.headline)
                        .padding(.leading, 8)
                    Spacer(minLength: 0)
                    Button("Sort A\u{2192}Z") {
                        itemManager.sortSection(name)
                    }
                    .help(Text("Sort the items in this section alphabetically by name."))
                    .buttonStyle(.borderless)
                }

                LayoutBar(section: name)
            }
        }
    }

    private func preloadLayoutCaches(includingImages: Bool) async {
        await itemManager.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true))
        guard !Task.isCancelled else {
            return
        }

        diagLog.debug("Preload: itemCache after cacheItemsRegardless: managedItems=\(self.itemManager.itemCache.managedItems.count), visible=\(itemManager.itemCache[.visible].count), hidden=\(itemManager.itemCache[.hidden].count), alwaysHidden=\(itemManager.itemCache[.alwaysHidden].count)")

        guard includingImages else {
            // Without Screen Recording the bars draw app icons instead, so
            // there is nothing to capture.
            return
        }

        await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        guard !Task.isCancelled else {
            return
        }

        diagLog.debug("Preload: imageCache after update: \(appState.imageCache.images.count) images")
    }
}

/// The layout reset flow, shared by ``MenuBarLayoutSettingsPane`` and
/// ``SimpleModeSettingsPane``.
struct LayoutResetControls: View {
    @Environment(AppState.self) private var appState: AppState
    let itemManager: MenuBarItemManager
    let controlItemsDisabled: Bool
    let alwaysHiddenEnabled: Bool

    @State private var isResettingLayout = false
    @State private var resetStatus: ResetStatus?
    @State private var isConfirmingReset = false

    var body: some View {
        IceSection {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reset menu bar layout")
                        .font(.headline)
                    Text("Resets dividers and moves every movable item except the \(Constants.displayName) icon to the selected section.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    isConfirmingReset = true
                } label: {
                    if isResettingLayout {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Reset Layout…")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isResettingLayout || controlItemsDisabled)
            }

            if isConfirmingReset {
                resetTargetControls
            }

            if let resetStatus {
                Text(resetStatus.message)
                    .font(.footnote)
                    .foregroundStyle(resetStatus.isError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var resetTargetControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose where to move the menu bar items:")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Visible") { resetMenuBarLayout(to: .visible) }
                Button("Hidden") { resetMenuBarLayout(to: .hidden) }
                if alwaysHiddenEnabled {
                    Button("Always Hidden") { resetMenuBarLayout(to: .alwaysHidden) }
                }
                Button("Cancel", role: .cancel) {
                    isConfirmingReset = false
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func resetMenuBarLayout(to target: MenuBarItemManager.LayoutResetTarget) {
        isConfirmingReset = false
        isResettingLayout = true
        resetStatus = nil

        let manager = itemManager

        Task { @MainActor in
            do {
                let failedMoves = switch target {
                case .visible:
                    try await manager.resetLayoutToVisible()
                case .hidden:
                    try await manager.resetLayoutToFreshState()
                case .alwaysHidden:
                    try await manager.resetLayoutToAlwaysHidden()
                }
                if failedMoves == 0 {
                    resetStatus = .success(target)
                } else {
                    resetStatus = .partialFailure(failedMoves)
                }
                isResettingLayout = false

                // The manager rebuilds both caches before returning.
            } catch {
                resetStatus = .failure(error.localizedDescription)
                isResettingLayout = false
            }
        }
    }

    private enum ResetStatus {
        case success(MenuBarItemManager.LayoutResetTarget)
        case partialFailure(Int)
        case failure(String)

        var message: String {
            switch self {
            case .success(.visible):
                String(localized: "Items were moved to the Visible section.")
            case .success(.hidden):
                String(localized: "Layout reset. Items were moved to the Hidden section.")
            case .success(.alwaysHidden):
                String(localized: "Layout reset. Items were moved to the Always Hidden section.")
            case let .partialFailure(count):
                String(localized: "Reset completed with \(count) item(s) that could not be moved. Check the menu bar and try again if needed.")
            case let .failure(message):
                String(localized: "Reset failed: \(message)")
            }
        }

        var isError: Bool {
            switch self {
            case .failure, .partialFailure:
                true
            case .success:
                false
            }
        }
    }
}
