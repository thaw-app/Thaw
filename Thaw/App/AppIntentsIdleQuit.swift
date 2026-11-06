//
//  AppIntentsIdleQuit.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Security

/// Recognizes the quit App Intents sends once an intent it ran in Thaw has finished.
///
/// linkd, the App Intents daemon, quits an app 30 seconds after its last intent there when it
/// believes it launched the app for that intent. It turns down the registration of a Thaw signed
/// without a team, as a local build is. When the Focus filter runs at login, linkd then treats
/// the Thaw that login started as one it launched, and quits it about a minute later. Thaw keeps
/// the menu bar arranged, so an intent finishing is no reason for it to end. A logout, restart
/// or shutdown comes from loginwindow with a reason and still quits Thaw.
nonisolated enum AppIntentsIdleQuit {
    /// Apple's linkd, matched by its signature so no other process can pass for it.
    static let linkdRequirement = #"identifier "com.apple.linkd" and anchor apple"#

    private static let diagLog = DiagLog(category: "AppIntentsIdleQuit")

    /// Whether Thaw should turn down the quit event it is handling now. A refusal is logged.
    /// Thaw passes neither argument; tests pass the event and the sender check.
    @MainActor
    static func refusesCurrentRequest(
        _ event: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent,
        isSentByLinkd: (NSAppleEventDescriptor) -> Bool = isSentByLinkd
    ) -> Bool {
        guard let event, refuses(event, isSentByLinkd: isSentByLinkd) else {
            return false
        }
        diagLog.info("Refusing to quit \(QuitRequestSource.current()): App Intents ends apps it launched for an intent, and Thaw keeps running")
        return true
    }

    /// Whether event is a quit from linkd that gives no reason.
    static func refuses(
        _ event: NSAppleEventDescriptor,
        isSentByLinkd: (NSAppleEventDescriptor) -> Bool = isSentByLinkd
    ) -> Bool {
        event.eventClass == AEEventClass(kCoreEventClass)
            && event.eventID == AEEventID(kAEQuitApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)) == nil
            && isSentByLinkd(event)
    }

    /// Whether the app that sent event is linkd. False when the event names no sender.
    static func isSentByLinkd(_ event: NSAppleEventDescriptor) -> Bool {
        SettingsURISender.guestAttributes(of: event).map(isLinkd(guestAttributes:)) ?? false
    }

    /// Whether the running code these attributes find has linkd's signature.
    static func isLinkd(guestAttributes: [CFString: Any]) -> Bool {
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, guestAttributes as CFDictionary, [], &code) == errSecSuccess,
              let code,
              SecRequirementCreateWithString(linkdRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
