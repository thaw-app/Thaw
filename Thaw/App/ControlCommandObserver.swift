//
//  ControlCommandObserver.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import MenuBarModel

// For LocalizedStringKey in the HUD confirmations below; no view code here.
import SwiftUI

/// Receiving end of the ThawControls Control Center bridge.
///
/// The ThawControls appex is sandboxed and Thaw is not. The controls post
/// Darwin notifications, which cross that boundary without any shared
/// entitlement and, unlike a shared defaults write, wake a running process.
/// Commands are one-way and unacknowledged; state travels the other way
/// through ControlStatePublisher. If Thaw is not running, a command has
/// nothing to act on anyway.
///
/// Set up once from AppState and never torn down, so registration
/// deliberately has no matching stop: the observer's lifetime is the app's.
@MainActor
final class ControlCommandObserver {
    /// The commands the controls can send, and what each one runs.
    ///
    /// These strings are duplicated in
    /// ThawControls/ControlCommandNames.swift and the two lists have to stay
    /// in sync. A typo on either side is a silent no-op: Darwin notifications
    /// have no delivery receipt and no subscriber count, so a mismatched name
    /// just vanishes. That file also records why the duplication is deliberate
    /// rather than a constant shared through Shared/.
    enum Command: String, CaseIterable {
        case toggleHidden = "com.stonerl.Thaw.control.toggle-hidden"
        case toggleZen = "com.stonerl.Thaw.control.toggle-zen"

        /// The existing action this command forwards to. Same thinness as the
        /// App Intents in ThawActionIntents.swift: a command that needs more
        /// than one line of dispatch belongs in HotkeyAction first.
        var action: HotkeyAction {
            switch self {
            case .toggleHidden: .toggleHiddenSection
            case .toggleZen: .toggleZenMode
            }
        }

        /// The on-screen confirmation this command owes the user, or nil
        /// when its action already confirms itself.
        ///
        /// A press from Control Center often shows no visible change, since
        /// the panel covers the menu bar, so without a HUD the only check is
        /// pressing again, which undoes it.
        ///
        /// Read before HotkeyAction.perform(appState:) runs: the hiding path
        /// is not synchronous, so the label is derived from the state the
        /// press moves from.
        ///
        /// .toggleZen returns nil because HotkeyAction shows its own zen HUD,
        /// so every entry path gets one capsule, not two.
        @MainActor
        func confirmation(appState: AppState) -> (symbol: String, text: LocalizedStringKey)? {
            switch self {
            case .toggleHidden:
                guard let section = appState.menuBarManager.section(withName: .hidden) else {
                    return nil
                }
                return section.isHidden
                    ? (symbol: "eye", text: "Items shown")
                    : (symbol: "eye.slash", text: "Items hidden")
            case .toggleZen:
                return nil
            }
        }
    }

    private let diagLog = DiagLog(category: "ControlCommandObserver")

    private var isObserving = false

    func performSetup(with _: AppState) {
        guard !isObserving else { return }
        isObserving = true

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for command in Command.allCases {
            // The callback is a bare C function pointer, so it can capture
            // nothing, not even self. It re-derives the live AppState
            // from the delegate on the main actor instead, exactly as the App
            // Intents do. The observer pointer is only an identity for
            // deregistration in deinit.
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                { _, _, name, _, _ in
                    guard let rawName = name?.rawValue as String? else { return }
                    Task { @MainActor in
                        ControlCommandObserver.dispatch(rawName)
                    }
                },
                command.rawValue as CFString,
                nil,
                // The Darwin notify center honours no other suspension
                // behaviour; anything else is ignored.
                .deliverImmediately
            )
        }

        diagLog.debug("registered \(Command.allCases.count) Darwin control commands")
    }

    /// Runs the action a posted notification name stands for.
    ///
    /// Static because the C callback above has no way to hand self back;
    /// unknown names are dropped rather than logged loudly, since the Darwin
    /// center is a global namespace and this process is not the only thing
    /// posting into it.
    @MainActor
    private static func dispatch(_ rawName: String) {
        guard
            let command = Command(rawValue: rawName),
            let appState = (NSApp?.delegate as? AppDelegate)?.appState
        else {
            return
        }
        let confirmation = command.confirmation(appState: appState)
        command.action.perform(appState: appState)
        if let confirmation {
            ThawHUD.show(symbol: confirmation.symbol, text: confirmation.text)
        }
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
}
