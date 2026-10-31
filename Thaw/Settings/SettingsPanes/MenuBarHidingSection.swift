//
//  MenuBarHidingSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// Where the system menu bar is hidden, as one choice. macOS keeps two
/// separate overrides, one for the current Space and one for every Space;
/// the choice sets both.
nonisolated enum MenuBarHidingScope: CaseIterable, Hashable, Sendable {
    case never
    case thisSpace
    case everySpace

    /// Every Space wins when both overrides are on, since it covers this one.
    init(hiddenInSpace: Bool, hiddenEverywhere: Bool) {
        self = hiddenEverywhere ? .everySpace : hiddenInSpace ? .thisSpace : .never
    }

    var hidesInSpace: Bool {
        self == .thisSpace
    }

    var hidesEverywhere: Bool {
        self == .everySpace
    }

    /// One override to send to macOS.
    enum Request: Equatable, Sendable {
        case everySpace(hidden: Bool)
        case thisSpace(hidden: Bool)
    }

    /// The overrides that change when moving from the current state to this
    /// choice. A request that hides goes before one that shows, so the menu
    /// bar never comes back for a moment between the two.
    func requests(fromHiddenInSpace inSpace: Bool, hiddenEverywhere everywhere: Bool) -> [Request] {
        var requests: [Request] = []
        if everywhere != hidesEverywhere {
            requests.append(.everySpace(hidden: hidesEverywhere))
        }
        if inSpace != hidesInSpace {
            requests.append(.thisSpace(hidden: hidesInSpace))
        }
        return requests.filter(\.hides) + requests.filter { !$0.hides }
    }
}

nonisolated extension MenuBarHidingScope.Request {
    var hides: Bool {
        switch self {
        case let .everySpace(hidden), let .thisSpace(hidden): hidden
        }
    }
}

/// The picker for MenuBarHidingScope on Displays. The overrides are commands
/// that last for this session and can't be read back, so the picker mirrors
/// what was asked for and goes back when macOS declines.
struct MenuBarHidingSection: View {
    let spaceID: UInt64
    @Binding var isHiddenInSpace: Bool
    @Binding var isHiddenEverywhere: Bool
    @State private var failure: LocalizedStringResource?

    private var presentation: any MenuBarPresentationControlling {
        MenuBarPresentationProvider.current
    }

    var body: some View {
        ThawSection {
            ThawPicker("Hide the menu bar", selection: scopeBinding) {
                Text("Never").tag(MenuBarHidingScope.never)
                Text("In this Space").tag(MenuBarHidingScope.thisSpace)
                    .selectionDisabled(spaceID == 0)
                Text("In every Space").tag(MenuBarHidingScope.everySpace)
            }
            .annotation(
                "Hides the system menu bar while this Space is showing, or everywhere, full screen included.",
                more: "In this Space leaves other Spaces as they are. It is unavailable while \(Constants.displayName) can't tell which Space is showing."
            )
        } footer: {
            if let failure {
                SettingsWarningPill(
                    title: "macOS didn't apply that change. Try again.",
                    message: failure,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
    }

    private var scopeBinding: Binding<MenuBarHidingScope> {
        Binding {
            MenuBarHidingScope(hiddenInSpace: isHiddenInSpace, hiddenEverywhere: isHiddenEverywhere)
        } set: { scope in
            apply(scope)
        }
    }

    /// Moves the picker at once and sends the overrides that change. A
    /// request macOS declines puts back only the override it was for, since
    /// the ones before it took effect.
    private func apply(_ scope: MenuBarHidingScope) {
        let requests = scope.requests(fromHiddenInSpace: isHiddenInSpace, hiddenEverywhere: isHiddenEverywhere)
        isHiddenInSpace = scope.hidesInSpace
        isHiddenEverywhere = scope.hidesEverywhere
        failure = nil
        let spaceID = spaceID
        Task {
            for request in requests {
                let succeeded = switch request {
                case let .everySpace(hidden):
                    await presentation.setSystemMenuBarHidden(hidden)
                case let .thisSpace(hidden):
                    spaceID != 0 ? await presentation.setSystemMenuBarHidden(hidden, spaceID: spaceID) : false
                }
                guard succeeded else {
                    switch request {
                    case let .everySpace(hidden): isHiddenEverywhere = !hidden
                    case let .thisSpace(hidden): isHiddenInSpace = !hidden
                    }
                    failure = "The menu bar could not be hidden there right now."
                    return
                }
            }
        }
    }
}
