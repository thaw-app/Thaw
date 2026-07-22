//
//  SettingsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let appState: AppState
    @ObservedObject var navigationState: AppNavigationState
    @State private var settingsWindow: NSWindow?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            settingsPane
                .id(navigationState.settingsNavigationIdentifier)
                .transition(paneTransition)
                .buttonStyle(.settingsGlass)
                .environment(\.settingsPaneTitle, paneTitle)
                // Fill the detail column so the Form's scrollbar sits on the
                // window/detail trailing edge — not on a 680pt content column.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Draw under the transparent toolbar so the page title isn't pushed
                // down by the ~60pt title-bar safe area.
                .ignoresSafeArea(.container, edges: .top)
                // Dark panes use a solid Music-like surface. Light bumps vibrancy
                // with under-window materials instead of the denser `.sidebar` fill.
                .background {
                    detailSurface
                        .ignoresSafeArea(.container, edges: .top)
                }
        }
        // Keep the window titled for Mission Control; omit the toolbar label so
        // it does not fight the in-pane header while scrolling.
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onWindowChange { window in
            settingsWindow = window
            configureSettingsWindowChrome(window)
        }
        .onChange(of: colorScheme) { _, _ in
            configureSettingsWindowChrome(settingsWindow)
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var paneTitle: LocalizedStringKey? {
        // About is a centered identity layout; a page title would be redundant.
        // Title sits above IceForm (outside grouped cards) and stays put while
        // the form scrolls in the remaining space.
        navigationState.settingsNavigationIdentifier == .about
            ? nil
            : navigationState.settingsNavigationIdentifier.localized
    }

    private var paneTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.animation(.easeOut(duration: 0.14))
    }

    private var prefersExtremeVibrancy: Bool {
        colorScheme == .dark
    }

    /// Dense behind-window vibrancy for the sidebar (and About) in both appearances.
    private var sidebarMaterial: NSVisualEffectView.Material {
        .hudWindow
    }

    private var sharedSidebarSurface: some View {
        BehindWindowMaterialBackground(material: sidebarMaterial)
    }

    private func configureSettingsWindowChrome(_ window: NSWindow?) {
        guard let window else {
            return
        }
        // Let pane/sidebar materials own the title-bar band and suppress the
        // system separator drawn over the detail pane.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // Clear chrome in both appearances so `.hudWindow` / under-window
        // materials can sample the desktop the same way. Light detail keeps
        // its own under-window + glass stack for readability; dark detail
        // stays a solid Music-like fill.
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    @ViewBuilder
    private var detailSurface: some View {
        let isAbout = navigationState.settingsNavigationIdentifier == .about
        if isAbout {
            sharedSidebarSurface
        } else if prefersExtremeVibrancy {
            // Apple Music–style solid page: no Liquid Glass veil over content.
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
        } else {
            // Light panes: under-window vibrancy + glass for a touch more life
            // than glass alone, without the muddy dark-mode double stack.
            ZStack {
                BehindWindowMaterialBackground(material: .underWindowBackground)
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Rectangle())
            }
        }
    }

    private var sidebar: some View {
        Group {
            if #available(macOS 27, *) {
                SettingsSearchSidebar(navigationState: navigationState)
            } else {
                SettingsSidebarPaneList(navigationState: navigationState)
                    .navigationSplitViewColumnWidth(ideal: 200, max: 240)
            }
        }
        .background {
            sharedSidebarSurface
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .general:
            GeneralSettingsPane(
                settings: appState.settings.general,
                advancedSettings: appState.settings.advanced
            )
        case .menuBarLayout:
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        case .displays:
            DisplaySettingsPane(displaySettings: appState.settings.displaySettings)
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager)
        case .hotkeys:
            HotkeysSettingsPane(settings: appState.settings.hotkeys)
        case .profiles:
            ProfileSettingsPane(profileManager: appState.profileManager)
        case .advanced:
            AdvancedSettingsPane(settings: appState.settings.advanced)
        case .automation:
            AutomationSettingsPane(
                settings: appState.settings.automation,
                hookSettings: appState.settings.automationHook
            )
        case .tools:
            ToolsSettingsPane(settings: appState.settings.advanced)
        case .about:
            AboutSettingsPane(updatesManager: appState.updatesManager)
        }
    }
}

// MARK: - SettingsDetailLayout

enum SettingsDetailLayout {
    /// Comfortable reading width for settings groups. Title and form share this
    /// column so they stay aligned when the window grows.
    static let columnMaxWidth: CGFloat = 680
    /// Offset from the window top under the transparent unified toolbar.
    /// Intentionally well below the ~60pt safe-area push.
    static let titleTopInset: CGFloat = 28
    /// Leading inset aligned with grouped form section cards / headers.
    static let titleHorizontalInset: CGFloat = 28
}

extension EnvironmentValues {
    @Entry var settingsPaneTitle: LocalizedStringKey?
}

// MARK: - BehindWindowMaterialBackground

/// Behind-window vibrancy so surfaces sample the desktop rather than the
/// system-owned `NavigationSplitView` backdrop beneath the SwiftUI layer.
private struct BehindWindowMaterialBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }
}

struct SettingsGlassButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            configuration.trigger()
        } label: {
            configuration.label
                .padding(.horizontal, 16)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}

extension PrimitiveButtonStyle where Self == SettingsGlassButtonStyle {
    static var settingsGlass: SettingsGlassButtonStyle {
        .init()
    }
}

// MARK: - SettingsSearchSidebar

@available(macOS 27, *)
private struct SettingsSearchSidebar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var navigationState: AppNavigationState

    @StateObject private var searchModel = SearchModel()

    private var isSearching: Bool {
        !searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var contentMode: ContentMode {
        if !isSearching {
            return .navigation
        }
        return searchModel.displayedGroups.isEmpty ? .empty : .results
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchModel.searchText)

            Group {
                switch contentMode {
                case .navigation:
                    SettingsSidebarPaneList(
                        navigationState: navigationState
                    )
                case .results:
                    SearchResultsList(groups: searchModel.displayedGroups) { entry in
                        SettingsSearchNavigation.selectSearchResult(
                            entry,
                            navigationState: navigationState,
                            query: &searchModel.searchText
                        )
                    }
                case .empty:
                    SearchEmptyView()
                }
            }
            .id(contentMode)
            .transition(contentTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewColumnWidth(ideal: 200, max: 240)
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.animation(.easeOut(duration: 0.1))
    }

    private enum ContentMode: Hashable {
        case navigation
        case results
        case empty
    }
}

// MARK: - SettingsSidebarPaneList

/// The default settings sidebar navigation list.
private struct SettingsSidebarPaneList: View {
    @ObservedObject var navigationState: AppNavigationState

    var body: some View {
        let selection = Binding<SettingsNavigationIdentifier>(
            get: { navigationState.settingsNavigationIdentifier },
            set: { newValue in
                SettingsSearchNavigation.selectSidebarPane(
                    newValue,
                    navigationState: navigationState
                )
            }
        )

        List(selection: selection) {
            Section {
                ForEach(SettingsNavigationIdentifier.allCases) { identifier in
                    Label {
                        Text(identifier.localized)
                    } icon: {
                        identifier.iconResource.view
                    }
                    .tag(identifier)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}
