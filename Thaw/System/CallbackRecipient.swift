//
//  CallbackRecipient.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The app a thaw:// response may be opened with. Any app can register a URL scheme and
/// claim a bundle ID, so the scheme's handler must carry the sender's own signature.
nonisolated enum CallbackRecipient {
    /// The handler of url when its signature names sender, by the rule stored grants use:
    /// the same bundle ID, and the same team or, for code without one, the same code hash.
    static func application(
        for url: URL,
        sender: SettingsURISender,
        handler: (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) },
        identify: (URL) -> SettingsURISender? = { SettingsURISender.identify(appAt: $0) }
    ) -> URL? {
        guard let app = handler(url), let identity = identify(app), identity.bundleIdentifier.caseInsensitiveCompare(sender.bundleIdentifier) == .orderedSame, identity.matchesGrant(storedTeamIdentifier: sender.teamIdentifier, storedCodeHash: sender.codeHash)
        else {
            return nil
        }
        return app
    }

    /// Opens url with the sender's own app, or with whatever handles it when there is no sender
    /// to answer to. Returns false when the sender's app can't be confirmed.
    /// Tests pass the lookups and launch, which gets the app to open with or nil for the default handler.
    static func open(
        _ url: URL,
        answering sender: SettingsURISender?,
        handler: (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) },
        identify: (URL) -> SettingsURISender? = { SettingsURISender.identify(appAt: $0) },
        launch: (URL, URL?) -> Bool = CallbackRecipient.launch(_:with:)
    ) -> Bool {
        guard let sender else { return launch(url, nil) }
        guard let app = application(for: url, sender: sender, handler: handler, identify: identify) else { return false }
        return launch(url, app)
    }

    /// Opens url with app, or with its default handler when app is nil.
    static func launch(_ url: URL, with app: URL?) -> Bool {
        guard let app else { return NSWorkspace.shared.open(url) }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}
