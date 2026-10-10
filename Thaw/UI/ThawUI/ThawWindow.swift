//
//  ThawWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - ThawWindow

/// A custom scene representing one of Thaw's windows.
struct ThawWindow<Content: View>: Scene {
    let id: ThawWindowIdentifier

    /// The app state used to track the window's live instance and visibility.
    let appState: AppState

    let content: Content

    /// Creates a window with an identifier constant.
    ///
    /// - Parameters:
    ///   - id: A custom identifier constant.
    ///   - appState: The app state used to track the window's live instance
    ///     and visibility.
    ///   - content: The content view to display in the window.
    init(id: ThawWindowIdentifier, appState: AppState, @ViewBuilder content: () -> Content) {
        self.id = id
        self.appState = appState
        self.content = content()
    }

    var body: some Scene {
        windowScene
    }

    private var windowContentView: some View {
        ThawWindowContent(id: id, appState: appState) {
            content
        }
    }

    private var windowScene: some Scene {
        Window(id.titleKey, id: id.rawValue) {
            windowContentView
        }
        .defaultLaunchBehavior(.suppressed)
        // No window state is worth restoring; restoration only re-opens
        // Settings after a crash.
        .restorationBehavior(.disabled)
    }
}

// MARK: - ThawWindowContent

/// The window's content, present only while the window is on screen.
///
/// SwiftUI keeps a closed Window scene's NSWindow, and with it the whole view
/// graph, resident. Dropping the content frees it; the window reader stays so
/// the reopen is still observed.
private struct ThawWindowContent<Content: View>: View {
    let id: ThawWindowIdentifier
    let appState: AppState
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            if appState.isWindowOpen(id) {
                content()
                    .modifier(AppUIZoomModifier())
            }
        }
        .onWindowChange { window in
            // None of Thaw's windows is a workspace; the green button zooms.
            window?.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenNone])
            appState.windowVisibilityChanged(id: id, window: window)
        }
    }
}

// MARK: - WindowActionBridge

/// Captures live SwiftUI window actions without eagerly creating any windows.
///
/// A non-inserted MenuBarExtra is instantiated with the app's scenes, so its
/// environment can open the lazy Settings and Permissions Window scenes.
struct WindowActionBridge: Scene {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    let registerWindowActions: (OpenWindowAction, DismissWindowAction) -> Void

    var body: some Scene {
        MenuBarExtra("", isInserted: .constant(false)) {
            EmptyView()
        }
        .once {
            registerWindowActions(openWindow, dismissWindow)
        }
    }
}

// MARK: - ThawWindowIdentifier

/// Custom identifier constants used to create Thaw's windows.
enum ThawWindowIdentifier: String, CustomStringConvertible {
    /// The identifier for Thaw's main settings window.
    case settings = "SettingsWindow"

    /// The identifier for Thaw's permissions window.
    case permissions = "PermissionsWindow"

    case whatsNew = "WhatsNewWindow"
    case acknowledgements = "AcknowledgementsWindow"

    /// The non-localized title of the corresponding window.
    ///
    /// - Note: Use titleKey to get the localized title.
    var titleString: String {
        switch self {
        case .settings: "\(Constants.displayName)"
        case .permissions: "Permissions"
        case .whatsNew: "What’s New"
        case .acknowledgements: "Acknowledgements"
        }
    }

    /// The localized title of the corresponding window.
    ///
    /// - Note: Use titleString to get the non-localized title.
    var titleKey: LocalizedStringKey {
        LocalizedStringKey(titleString)
    }

    /// A textual representation of the identifier.
    var description: String {
        rawValue
    }
}

// MARK: - OpenWindowAction

extension OpenWindowAction {
    /// Opens the corresponding window for the given identifier.
    ///
    /// - Parameter id: An identifier for one of Thaw's windows.
    func callAsFunction(id: ThawWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}

// MARK: - DismissWindowAction

extension DismissWindowAction {
    /// Dismisses the corresponding window for the given identifier.
    ///
    /// - Parameter id: An identifier for one of Thaw's windows.
    func callAsFunction(id: ThawWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}
