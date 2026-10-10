//
//  IceWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - IceWindow

/// A custom scene representing one of Ice's windows.
struct IceWindow<Content: View>: Scene {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    let id: IceWindowIdentifier

    let content: Content

    /// Builds the content once, when the scene is created.
    init(id: IceWindowIdentifier, @ViewBuilder content: () -> Content) {
        self.id = id
        self.content = content()
    }

    var body: some Scene {
        windowScene.once {
            // SwiftUI doesn't create the NSWindow until first presentation, and we
            // may need it earlier. Opening and dismissing in one run loop cycle creates
            // it without showing it.
            openWindow(id: id)
            dismissWindow(id: id)
        }
    }

    private var windowContentView: some View {
        content.onWindowChange { window in
            window?.collectionBehavior.insert(.moveToActiveSpace)
        }
    }

    private var windowScene: some Scene {
        Window(id.titleKey, id: id.rawValue) {
            windowContentView
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

// MARK: - IceWindowIdentifier

/// Identifiers for Ice's windows.
enum IceWindowIdentifier: String, CustomStringConvertible {
    case settings = "SettingsWindow"

    case permissions = "PermissionsWindow"

    /// The non-localized title of the corresponding window.
    ///
    /// - Note: Use ``titleKey`` to get the localized title.
    var titleString: String {
        switch self {
        case .settings: "\(Constants.displayName)"
        case .permissions: "Permissions"
        }
    }

    /// The localized title of the corresponding window.
    ///
    /// - Note: Use ``titleString`` to get the non-localized title.
    var titleKey: LocalizedStringKey {
        LocalizedStringKey(titleString)
    }

    var description: String {
        rawValue
    }
}

// MARK: - OpenWindowAction

extension OpenWindowAction {
    func callAsFunction(id: IceWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}

// MARK: - DismissWindowAction

extension DismissWindowAction {
    func callAsFunction(id: IceWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}
