//
//  MenuBarLayoutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager

    @State private var loadDeadlineReached = false
    @State private var isResettingLayout = false
    @State private var resetStatus: ResetStatus?
    @State private var isConfirmingReset = false
    @State private var isConfirmingIconReset = false
    @State private var hasOverrides = !AssetCatalogReader.overrides.isEmpty

    private let diagLog = DiagLog(category: "MenuBarLayoutPane")

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    private var areControlItemsDisabledBySystem: Bool {
        itemManager.areControlItemsMissing
    }

    var body: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            IceForm(spacing: 20) {
                header
                layoutBars
                iconOverrideControls
                resetControls
            }
        }
    }

    private var header: some View {
        IceSection {
            VStack(spacing: 3) {
                Text("Drag to arrange your menu bar items into different sections.")
                    .font(.title3.bold())
                Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Right-click any icon to choose an alternative.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(15)
        }
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
                                    .font(.calloutBox)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Unable to load menu bar items")
                            }
                        }
                    } else {
                        Text("Loading menu bar items…")
                    }
                    if loadDeadlineReached {
                        EmptyView()
                    } else {
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

            diagLog.debug("Preloading menu bar layout caches (hasItems=\(self.hasItems))")

            // Run cache updates in the background to avoid blocking the UI
            Task {
                await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                diagLog.debug("Preload: itemCache after cacheItemsRegardless: managedItems=\(self.itemManager.itemCache.managedItems.count), visible=\(self.itemManager.itemCache[.visible].count), hidden=\(self.itemManager.itemCache[.hidden].count), alwaysHidden=\(self.itemManager.itemCache[.alwaysHidden].count)")
                await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
                diagLog.debug("Preload: imageCache after update: \(self.appState.imageCache.images.count) images")
            }

            try? await Task.sleep(for: .seconds(3))

            if !hasItems {
                loadDeadlineReached = true
                diagLog.error("Menu bar layout failed to load items after 3s timeout. cacheItems: \(itemManager.itemCache.managedItems.count), images: \(appState.imageCache.images.count), displayID: \(self.itemManager.itemCache.displayID.map { "\($0)" } ?? "nil")")
            }
        }
    }

    private var iconOverrideControls: some View {
        IceSection {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Icon overrides")
                        .font(.headline)
                    Text("Export your overrides to share or reset back to application defaults.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button("Export to Clipboard") {
                        exportOverridesToClipboard()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasOverrides)

                    Button("Reset All") {
                        isConfirmingIconReset = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasOverrides)
                }
            }
        }
        .onAppear {
            hasOverrides = !AssetCatalogReader.overrides.isEmpty
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            hasOverrides = !AssetCatalogReader.overrides.isEmpty
        }
        .alert("Reset all icon overrides?", isPresented: $isConfirmingIconReset) {
            Button("Reset", role: .destructive) {
                resetAllIconOverrides()
            }
            Button("Cancel", role: .cancel) {
                isConfirmingIconReset = false
            }
        } message: {
            Text("This will remove all custom icon selections and revert every icon to its default.")
        }
    }

    private var resetControls: some View {
        IceSection {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reset menu bar layout")
                        .font(.headline)
                    Text("Resets dividers and moves every movable item except the \(Constants.displayName) icon to hidden — just like a fresh install.")
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
                        Text("Reset Layout")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isResettingLayout || areControlItemsDisabledBySystem)
            }

            if let resetStatus {
                Text(resetStatus.message)
                    .font(.footnote)
                    .foregroundStyle(resetStatus.isError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("Reset menu bar layout?", isPresented: $isConfirmingReset) {
            Button("Reset", role: .destructive) {
                resetMenuBarLayout()
            }
            Button("Cancel", role: .cancel) {
                isConfirmingReset = false
            }
        } message: {
            Text("Restores divider defaults and moves every movable item except the \(Constants.displayName) icon to Hidden. Use this if the layout looks broken or items won’t load.")
        }
    }

    private var cannotArrange: some View {
        Text("\(Constants.displayName) cannot arrange menu bar items in automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var loadingMenuBarItems: some View {
        VStack {
            Text("Loading menu bar items…")
            ProgressView()
        }
        .font(.title)
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            VStack(alignment: .leading) {
                Text(name.localized)
                    .font(.headline)
                    .padding(.leading, 8)

                LayoutBar(imageCache: appState.imageCache, section: name)
            }
        }
    }

    private func exportOverridesToClipboard() {
        let overrides = AssetCatalogReader.overrides
        guard !overrides.isEmpty else { return }
        if let data = try? JSONSerialization.data(withJSONObject: overrides, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8)
        {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        }
    }

    private func resetAllIconOverrides() {
        AssetCatalogReader.overrides = [:]
        hasOverrides = false
        Task {
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        }
    }

    private func resetMenuBarLayout() {
        isResettingLayout = true
        resetStatus = nil

        let manager = itemManager

        Task { @MainActor in
            do {
                let failedMoves = try await manager.resetLayoutToFreshState()
                if failedMoves == 0 {
                    resetStatus = .success
                } else {
                    resetStatus = .partialFailure(failedMoves)
                }
                isResettingLayout = false

                await manager.cacheItemsRegardless(skipRecentMoveCheck: true)
                await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            } catch {
                resetStatus = .failure(error.localizedDescription)
                isResettingLayout = false
            }
        }
    }

    private enum ResetStatus {
        case success
        case partialFailure(Int)
        case failure(String)

        var message: String {
            switch self {
            case .success:
                String(localized: "Layout reset. Items were moved to the Hidden section.")
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
