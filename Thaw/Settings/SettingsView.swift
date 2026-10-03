//
//  SettingsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppUIZoom.defaultsKey) private var zoomPercent = 100

    let appState: AppState
    let navigationState: AppNavigationState
    let generalSettings: GeneralSettings
    @State private var settingsWindow: NSWindow?

    /// Shared settings search state, driving the detail header's search field
    /// the single search entry point. The sidebar is navigation only, so
    /// results take over the detail column rather than the pane list.
    @State private var searchModel = SearchModel()
    @State private var isCustomizeSidebarPresented = false
    @State private var paneHistory = SettingsPaneHistory()

    private var isSearching: Bool {
        !searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if generalSettings.simpleMode {
                // No sidebar at all: one screen is the whole point of Simple
                // Mode, and a sidebar listing a single item is just a sidebar.
                simpleModeScreen
            } else {
                fullSettingsScreen
            }
        }
        // Applied here rather than on the Scene so it can follow the mode: with
        // .windowResizability(.contentSize) this minimum is the window's, and
        // the full layout's would otherwise hold Simple Mode open at a sidebar's
        // width forever.
        .frame(
            minWidth: SettingsWindowMetrics.minimum(simpleMode: generalSettings.simpleMode).width / zoomScale,
            minHeight: SettingsWindowMetrics.minimum(simpleMode: generalSettings.simpleMode).height / zoomScale
        )
        .environment(\.settingsDescriptionsVisible, generalSettings.showSettingDescriptions)
        .environment(searchModel)
        // Both layouts title the toolbar themselves: the full one with the
        // pane, Simple Mode with the app and the mode. Cleared here so the
        // window never falls back to the scene's title.
        .navigationTitle("")
        .onWindowChange { window in
            settingsWindow = window
        }
        .onChange(of: generalSettings.simpleMode) { _, isSimpleMode in
            resizeSettingsWindow(forSimpleMode: isSimpleMode)
            // Simple Mode's folded bar draws captured glyphs where the full
            // window's General pane draws none, so the mode switch decides
            // whether capture is on.
            navigationState.isSimpleModeSettings = isSimpleMode
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var zoomScale: CGFloat {
        CGFloat(AppUIZoom.normalized(zoomPercent)) / 100
    }

    private var simpleModeScreen: some View {
        // No sidebar and no navigation: one scrolling page is the whole point
        // of Simple Mode. The title bar names the mode, so the page has no
        // heading of its own and opens straight on the folded bar; arranging
        // comes first, app plumbing last.
        SimpleModeSettingsPane(
            itemManager: appState.itemManager,
            updatesManager: appState.updatesManager,
            settings: generalSettings
        )
        .environment(\.settingsPaneTitle, nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("\(Constants.displayName): Simple Mode")
        // The same overflow menu as the full window, so the mode switch sits
        // in the same place whichever way the window is showing.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsOverflowMenu(appState: appState, generalSettings: generalSettings, isCustomizeSidebarPresented: $isCustomizeSidebarPresented)
            }
        }
    }

    private var fullSettingsScreen: some View {
        @Bindable var searchModel = searchModel
        return NavigationSplitView {
            sidebar
        } detail: {
            detailContent
                // The system toolbar is the pane header: it names the pane,
                // stays put while the form scrolls under it and blurs what
                // passes beneath, and carries the search field and the
                // overflow menu on its trailing edge.
                .navigationTitle(toolbarTitle)
                .navigationSubtitle(toolbarSubtitle)
                .toolbar {
                    // History on the leading edge, the active profile as the
                    // one chip in the middle, and the overflow menu beside
                    // search. Swap and Zen Mode live in the overflow menu.
                    ToolbarItemGroup(placement: .navigation) {
                        SettingsHistoryButtons(history: paneHistory, navigationState: navigationState)
                    }
                    ToolbarItem(placement: .principal) {
                        SettingsProfileChip(appState: appState, navigationState: navigationState)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        SettingsOverflowMenu(appState: appState, generalSettings: generalSettings, isCustomizeSidebarPresented: $isCustomizeSidebarPresented)
                    }
                }
                .onChange(of: navigationState.settingsNavigationIdentifier) { previous, _ in
                    paneHistory.record(leaving: previous)
                }
                .background {
                    // ⌘F from anywhere in the window lands in the field.
                    Button("Find") {
                        isSearchPresented = true
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden()
                    // History's shortcuts live in the content, not on the
                    // toolbar buttons: a toolbar item that carries a
                    // keyboardShortcut is vended with focused values every
                    // layout pass, and AppKit refuses the 406th constraints pass.
                    Button("Back") {
                        paneHistory.goBack(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
                    }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(paneHistory.back.isEmpty)
                    .hidden()
                    Button("Forward") {
                        paneHistory.goForward(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
                    }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(paneHistory.forward.isEmpty)
                    .hidden()
                }
                // Fill the detail column so the Form's scrollbar sits on the
                // window/detail trailing edge, not on a 680pt content column.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Content fades under the glass toolbar instead of stopping at
                // a hard band.
                .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .searchable(
            text: $searchModel.searchText,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "Search"
        )
        .sheet(isPresented: $isCustomizeSidebarPresented) {
            CustomizeSidebarSheet(appState: appState)
        }
    }

    /// Whether the toolbar search field has focus. Driven by ⌘F; the
    /// system clears it on Escape or when the field loses focus.
    @State private var isSearchPresented = false

    private var toolbarTitle: LocalizedStringKey {
        isSearching ? "Search" : navigationState.settingsNavigationIdentifier.localized
    }

    private var toolbarSubtitle: Text {
        isSearching ? Text(verbatim: "") : Text(navigationState.settingsNavigationIdentifier.subtitle)
    }

    @ViewBuilder
    private var detailContent: some View {
        if isSearching {
            SettingsSearchResults(navigationState: navigationState)
                .id("search")
                .transition(paneTransition)
        } else {
            settingsPane
                .id(navigationState.settingsNavigationIdentifier)
                .transition(paneTransition)
                // The toolbar names the pane; the pane's own title slot stays
                // empty so nothing prints it twice.
                .environment(\.settingsPaneTitle, nil)
        }
    }

    private var paneTransition: AnyTransition {
        // Insertion-only: cross-fading two full panes doubles the glass and
        // material layers WindowServer composites for the whole fade, which
        // reads as pane-switch lag. Removing the old pane instantly keeps at
        // most one pane's worth of glass on screen.
        reduceMotion
            ? .identity
            : .asymmetric(
                insertion: .opacity.animation(ThawMotion.pane),
                removal: .identity
            )
    }

    /// Brings the window to the size the incoming layout wants.
    ///
    /// The minimum alone cannot do this: it lets Simple Mode be shrunk, it does
    /// not shrink anything, so switching modes would leave the old layout's
    /// frame with the new layout rattling around inside it. Only shrinks on the
    /// way in and grows on the way out, so a window someone has already sized to
    /// taste within a mode is left alone. Anchored at the top-left because
    /// AppKit sizes from the bottom.
    private func resizeSettingsWindow(forSimpleMode isSimpleMode: Bool) {
        guard let window = settingsWindow else {
            return
        }
        let preferred = SettingsWindowMetrics.preferred(simpleMode: isSimpleMode)
        let current = window.frame.size
        let target = CGSize(
            width: isSimpleMode ? min(current.width, preferred.width) : max(current.width, preferred.width),
            height: isSimpleMode ? min(current.height, preferred.height) : max(current.height, preferred.height)
        )
        guard target != current else {
            return
        }
        let origin = window.frame.origin
        window.setFrame(
            NSRect(
                x: origin.x,
                y: origin.y + (current.height - target.height),
                width: target.width,
                height: target.height
            ),
            display: true,
            // Never the blocking animate: true loop: it re-displays every
            // frame on the main thread while SwiftUI is simultaneously
            // swapping the entire mode tree, which is the Simple Mode
            // transition lag. One instant resize under the mode swap reads
            // faster than a stuttering animation.
            animate: false
        )
    }

    // No window-chrome or surface overrides here on purpose: the sidebar keeps
    // AppKit's own source-list material and the detail column its window
    // background, which is what a stock settings window looks like.

    private var sidebar: some View {
        SettingsSidebar(
            appState: appState,
            navigationState: navigationState,
            generalSettings: appState.settings.general
        )
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .menuBarLayout:
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        case .visibility:
            MenuBarAccessPane(
                settings: appState.settings.general,
                advancedSettings: appState.settings.advanced
            )
        case .spaces:
            // Session-only Space controls: a peer destination, not a tab inside
            // Menu Bar. See SpacesSettingsPane for why these are commands, not
            // preferences.
            SpacesSettingsPane()
        case .thawBar:
            ThawBarSettingsPane(displaySettings: appState.settings.displaySettings)
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager)
        case .widgets:
            WidgetsSettingsPane()
        case .profiles:
            ProfileSettingsPane(profileManager: appState.profileManager)
        case .hotkeys:
            HotkeysSettingsPane(settings: appState.settings.hotkeys)
        case .automation:
            AutomationSettingsPane(
                settings: appState.settings.automation,
                hookSettings: appState.settings.automationHook,
                advancedSettings: appState.settings.advanced
            )
        case .triggers:
            TriggersSettingsPane(manager: appState.appRunningTriggers)
        case .displays:
            DisplaySettingsPane(displaySettings: appState.settings.displaySettings)
        case .general:
            GeneralSettingsPane(
                settings: appState.settings.general,
                advancedSettings: appState.settings.advanced
            )
        case .privacy:
            PrivacySettingsPane(
                updatesManager: appState.updatesManager,
                advancedSettings: appState.settings.advanced
            )
        case .theLab:
            TheLabSettingsPane(settings: appState.settings.advanced)
        case .tools:
            ToolsSettingsPane(settings: appState.settings.advanced)
        case .about:
            AboutSettingsPane(updatesManager: appState.updatesManager)
        case .scripts:
            ScriptsSettingsPane()
        case .advanced:
            // Advanced was dissolved; its controls live on General, Layout, and
            // Automation. A stale identifier (saved last pane) lands on Layout.
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        }
    }
}

// MARK: - SettingsDetailLayout

enum SettingsDetailLayout {
    /// Comfortable reading width for settings groups. Title and form share this
    /// column so they stay aligned when the window grows.
    static let columnMaxWidth: CGFloat = 748
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
/// system-owned NavigationSplitView backdrop beneath the SwiftUI layer.
/// The behind-window material every Thaw window surface is built on. Shared
/// with the What's New reader so it sits on the same glass as the panes.
struct BehindWindowMaterialBackground: NSViewRepresentable {
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

/// The system glass button, unmodified: its own padding and shape, so a
/// Settings button looks like one in System Settings and follows macOS as the
/// style changes. Kept as a name so call sites say what they mean.
extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    static var settingsGlass: GlassButtonStyle {
        .glass
    }
}

// MARK: - SettingsDetailHeader

/// The toolbar's overflow menu: the window-level switches that have no pane
/// of their own, plus About and the update actions people look for in a
/// title bar. Replaying onboarding lives in Troubleshooting. The
/// system draws the button; in the full window it is the one beside the
/// search field, and Simple Mode shows the same menu alone.
private struct SettingsOverflowMenu: View {
    let appState: AppState
    let generalSettings: GeneralSettings
    @Binding var isCustomizeSidebarPresented: Bool

    var body: some View {
        @Bindable var generalSettings = generalSettings
        let menuBarManager = appState.menuBarManager
        Menu {
            Button(menuBarManager.isSwapped ? "Swap Back" : "Swap Shown and Hidden Items") {
                menuBarManager.toggleSwap()
            }
            Button(menuBarManager.isZenModeActive ? "Leave Zen Mode" : "Zen Mode") {
                menuBarManager.toggleZenMode()
            }
            Divider()
            Menu {
                AppUIZoomControls(showsShortcuts: false)
            } label: {
                Text("Zoom")
            }
            Divider()
            Toggle("Simple Mode", isOn: $generalSettings.simpleMode)
            Toggle("Show Descriptions", isOn: $generalSettings.showSettingDescriptions)
            Divider()
            Button("Customize Sidebar…") {
                isCustomizeSidebarPresented = true
            }
            Divider()
            Button("About \(Constants.displayName)") {
                appState.navigationState.settingsNavigationIdentifier = .about
            }
            Button("What’s New…") {
                appState.openWindow(.whatsNew)
            }
            Button("Check for Updates…") {
                appState.updatesManager.checkForUpdates()
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
    }
}

// MARK: - SettingsSearchResults

/// Search results in the detail column, on the same reading width as the
/// panes they stand in for.
private struct SettingsSearchResults: View {
    @Environment(SearchModel.self) private var searchModel
    let navigationState: AppNavigationState

    private var resultCount: Int {
        searchModel.displayedGroups.reduce(0) { $0 + $1.entries.count }
    }

    var body: some View {
        @Bindable var searchModel = searchModel
        if searchModel.displayedGroups.isEmpty {
            SearchEmptyView(query: searchModel.searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // A count makes a long list read as bounded, and tells the
                // reader whether narrowing the query is worth it.
                Text("^[\(resultCount) result](inflect: true)")
                    .font(ThawType.detail.weight(.medium))
                    .foregroundStyle(ThawInk.supporting)
                    .padding(.horizontal, SettingsDetailLayout.titleHorizontalInset + 6)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.updatesFrequently)

                SearchResultsList(groups: searchModel.displayedGroups) { entry in
                    SettingsSearchNavigation.selectSearchResult(
                        entry,
                        navigationState: navigationState,
                        query: &searchModel.searchText
                    )
                }
                .frame(maxWidth: SettingsDetailLayout.columnMaxWidth)
                .padding(.horizontal, SettingsDetailLayout.titleHorizontalInset - 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - SettingsSidebar

/// The sidebar: a plain source list of panes over a pinned profile control.
///
/// The pane header names the pane; the sidebar only ever lists where to go
/// and which profile is live.
private struct SettingsSidebar: View {
    @Environment(SearchModel.self) private var searchModel
    let appState: AppState
    let navigationState: AppNavigationState
    let generalSettings: GeneralSettings

    private static let listWidth: CGFloat = 210

    var body: some View {
        // The profile switcher lives in the toolbar, so the list runs to the
        // foot of the sidebar.
        SettingsSidebarPaneList(navigationState: navigationState)
            .navigationSplitViewColumnWidth(min: Self.listWidth, ideal: Self.listWidth, max: 250)
            .onChange(of: generalSettings.simpleMode) { _, _ in
                searchModel.updateDisplayedItems()
            }
    }
}

// MARK: - SettingsSidebarPanes

/// The sidebar's direct destinations, one flat list with no headings.
///
/// The basics (General, Layout, Visibility, Appearance, Thaw Bar) sit at the
/// top, with About last. Custom Status Icon is not a destination: it is an
/// Experiments toggle. Scripts is an unbuilt
/// placeholder, reachable through search only.
enum SettingsSidebarPanes {
    /// One sidebar group: its direct destinations. Groups are separated by a
    /// small gap, with no text heading, the way macOS Settings separates its
    /// top group from the rest.
    struct Group: Identifiable {
        let panes: [SettingsNavigationIdentifier]

        /// A group is never empty: visibleGroups(hidden:) drops empty ones.
        var id: SettingsNavigationIdentifier {
            panes[0]
        }
    }

    static let groups: [Group] = [
        // The basics sit at the top: the everyday surfaces (General, Menu Bar,
        // Appearance, Thaw Bar) need no heading.
        Group(panes: [
            .general, .menuBarLayout, .visibility, .menuBarAppearance, .thawBar,
            .profiles, .hotkeys, .automation, .triggers, .displays, .spaces,
            .privacy, .theLab, .tools, .about,
        ]),
    ]

    /// Every direct destination, flattened.
    static let all: [SettingsNavigationIdentifier] = groups.flatMap(\.panes)

    /// Groups with hidden panes filtered out. A group that empties entirely is
    /// dropped so no empty section sits in the sidebar.
    static func visibleGroups(hidden: Set<String>) -> [Group] {
        groups.compactMap { group in
            let panes = group.panes.filter { !hidden.contains($0.rawValue) }
            return panes.isEmpty ? nil : Group(panes: panes)
        }
    }
}

// MARK: - SettingsProfileChip

/// The toolbar's chip for the live profile, with a menu to switch, in the
/// spot Xcode gives its scheme: the one setting people change most often
/// without wanting the Profiles pane.
private struct SettingsProfileChip: View {
    @Environment(SearchModel.self) private var searchModel
    let appState: AppState
    let navigationState: AppNavigationState
    @State private var errorMessage: String?

    private var profileManager: ProfileManager {
        appState.profileManager
    }

    private var activeProfile: ProfileMetadata? {
        guard let id = profileManager.activeProfileID else {
            return nil
        }
        return profileManager.profiles.first { $0.id == id }
    }

    private var activeProfileName: String {
        activeProfile?.name ?? String(localized: "No active profile")
    }

    /// Loads and applies a profile the way the status item menu does.
    ///
    /// Throws rather than swallowing a failed load: a profile that cannot be
    /// read closes the menu and changes nothing, which reads as the app
    /// ignoring the choice. Callers surface it the way the Profiles pane
    /// does, so the same failure says the same thing wherever it happens.
    static func apply(_ metadata: ProfileMetadata, appState: AppState) throws {
        let profileManager = appState.profileManager
        guard metadata.id != profileManager.activeProfileID else {
            return
        }
        let profile = try profileManager.loadProfile(id: metadata.id)
        let previousID = profileManager.activeProfileID
        profileManager.activeProfileID = metadata.id
        profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
    }

    var body: some View {
        Menu {
            if profileManager.profiles.isEmpty {
                Text("No profiles saved")
            } else {
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
            }
            Divider()
            Button("Manage Profiles…") {
                // A sidebar jump ends the search, or the detail column keeps stale results.
                searchModel.searchText = ""
                SettingsSearchNavigation.selectSidebarPane(.profiles, navigationState: navigationState)
            }
        } label: {
            Label(activeProfileName, systemImage: "person.crop.rectangle.stack")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .menuIndicator(.visible)
        .fixedSize()
        .help("Active profile")
        .accessibilityLabel("Active profile")
        .accessibilityValue(activeProfileName)
        .errorAlert("Couldn’t switch profile", message: $errorMessage)
    }

    private func apply(_ metadata: ProfileMetadata) {
        do {
            try Self.apply(metadata, appState: appState)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - SettingsSidebarPaneList

/// The settings sidebar navigation list: a standard macOS source list, one
/// SF Symbol and one label per row, and nothing drawn by hand.
///
/// The selection binding is what makes it a source list rather than a stack
/// of buttons: AppKit draws the selected row, walks it with the arrow keys,
/// emphasises it while the list holds key focus and greys it when focus is
/// elsewhere, and reports the selected row to VoiceOver. Selection, hover
/// and keyboard focus are all the system's marks here; a row that paints
/// its own only ends up fighting the fill underneath it.
private struct SettingsSidebarPaneList: View {
    @Environment(SearchModel.self) private var searchModel
    let navigationState: AppNavigationState

    /// Width of the icon column, so labels line up whatever each symbol's
    /// own width is.
    private static let iconColumn: CGFloat = 22

    @Environment(\.colorScheme) private var colorScheme

    /// The accent, deepened in dark mode so a light one such as yellow keeps
    /// its contrast against the selected label.
    private var accent: Color {
        colorScheme == .dark ? Color.accentColor.mix(with: .black, by: 0.4) : Color.accentColor
    }

    private var selection: Binding<SettingsNavigationIdentifier?> {
        Binding {
            // Routes outside the sidebar, such as Scripts, select no row.
            SettingsSidebarPanes.all.contains(navigationState.settingsNavigationIdentifier)
                ? navigationState.settingsNavigationIdentifier
                : nil
        } set: { pane in
            guard let pane else {
                return
            }
            // Clear the search first: the clicked pane may already be selected,
            // and a leftover search would keep the detail column on results.
            searchModel.searchText = ""
            SettingsSearchNavigation.selectSidebarPane(pane, navigationState: navigationState)
        }
    }

    var body: some View {
        let visible = SettingsSidebarPanes.visibleGroups(hidden: navigationState.hiddenSidebarPanes)
            .flatMap(\.panes)
        // One list and no Sections: a Section makes SwiftUI back the list with
        // an outline view, and switching into that mode crashes AppKit on a
        // freed row view (sizeLastColumnToFit) on macOS 27.0 and 27.2.
        List(selection: selection) {
            ForEach(visible, id: \.self) { identifier in
                let isSelected = identifier == navigationState.settingsNavigationIdentifier
                Label {
                    Text(identifier.localized)
                        .font(ThawType.detail.weight(.medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                } icon: {
                    identifier.iconResource.view
                        .font(ThawType.symbol.weight(.medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: Self.iconColumn)
                }
                // Only the selection fill carries the accent. Applied per row,
                // where the sidebar reads it.
                .listItemTint(isSelected ? .preferred(accent) : .monochrome)
            }
        }
        .listStyle(.sidebar)
        // The selection fill uses the same deepened accent.
        .tint(accent)
        // Medium rows whatever the system's sidebar size: at Large the labels
        // and symbols crowd a settings window this narrow.
        .environment(\.sidebarRowSize, .medium)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, ThawSpacing.base, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

// MARK: - Toolbar pieces

/// Back and forward through the panes visited in this window, like a
/// browser, so a detour to check one setting is one click back.
@MainActor
@Observable
final class SettingsPaneHistory {
    private(set) var back: [SettingsNavigationIdentifier] = []
    private(set) var forward: [SettingsNavigationIdentifier] = []
    /// Set while a history move is changing the pane, so the change is not
    /// recorded as a new visit.
    private var isTravelling = false

    func record(leaving pane: SettingsNavigationIdentifier) {
        guard !isTravelling else { return }
        back.append(pane)
        if back.count > 50 {
            back.removeFirst()
        }
        forward.removeAll()
    }

    func goBack(from current: SettingsNavigationIdentifier, navigationState: AppNavigationState) {
        guard let target = back.popLast() else { return }
        forward.append(current)
        travel(to: target, navigationState: navigationState)
    }

    func goForward(from current: SettingsNavigationIdentifier, navigationState: AppNavigationState) {
        guard let target = forward.popLast() else { return }
        back.append(current)
        travel(to: target, navigationState: navigationState)
    }

    private func travel(to pane: SettingsNavigationIdentifier, navigationState: AppNavigationState) {
        isTravelling = true
        SettingsSearchNavigation.selectSidebarPane(pane, navigationState: navigationState)
        isTravelling = false
    }
}

private struct SettingsHistoryButtons: View {
    let history: SettingsPaneHistory
    let navigationState: AppNavigationState

    var body: some View {
        Button {
            history.goBack(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
        } label: {
            Label("Back", systemImage: "chevron.backward")
        }
        .disabled(history.back.isEmpty)
        .help("Back")

        Button {
            history.goForward(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
        } label: {
            Label("Forward", systemImage: "chevron.forward")
        }
        .disabled(history.forward.isEmpty)
        .help("Forward")
    }
}
