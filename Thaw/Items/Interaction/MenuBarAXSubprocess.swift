//
//  MenuBarAXSubprocess.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import MenuBarModel
import os
import ThawAXClient
import ThawAXCore

/// Routes the ambient menu bar walk through the bundled AX helper.
///
/// The helper process does the AX reads so a wedged status-item app blocks it
/// instead of the app's main thread. It returns raw observations; identity and
/// assembly stay here, on the same code the in-process walk uses.
///
/// On by default; off when Defaults.axEnumerationViaSubprocess is set to
/// false or the helper is not embedded. The move/settle hot path deliberately
/// keeps the in-process walk.
nonisolated enum MenuBarAXSubprocess {
    static let isEnabled: Bool = {
        let enabled = Defaults.bool(forKey: .axEnumerationViaSubprocess)
        guard enabled else { return false }
        return AXSubprocessClient.embeddedHelperURL() != nil
    }()

    /// The one helper process. The walk and the pointer reads share it; the
    /// helper serves them on separate lanes, so neither waits on the other.
    static let client: AXSubprocessClient? = {
        guard isEnabled, let url = AXSubprocessClient.embeddedHelperURL() else { return nil }
        return AXSubprocessClient(configuration: AXSubprocessClient.Configuration(helperURL: url))
    }()

    private static let diagLog = DiagLog(category: "MenuBarAXSubprocess")

    /// What to do about a helper that answers but is not trusted.
    private static let untrustedPolicy = OSAllocatedUnfairLock(initialState: UntrustedHelperPolicy())

    /// Returns assembled items, or nil when the helper is off or unusable so
    /// the caller falls back to the in-process walk.
    static func items(displayID _: CGDirectDisplayID?) async -> [MenuBarItem]? {
        guard let client else { return nil }
        guard untrustedPolicy.withLock({ $0.shouldAsk(now: .now) }) else { return nil }
        // The helper walk must match the in-process walk, which does not filter
        // by display: macOS 27 mirrors one status-item set on every bar, and a
        // filter drops items the app still manages. displayID is kept in the
        // signature for call-site compatibility but deliberately not sent.
        // The height ceiling is the one the in-process walk computes, so tall
        // notched bars admit their full-height system items here too.
        let maximumItemHeight = MenuBarItemAXProvider.maxItemHeight(
            menuBarHeight: NSScreen.tallestCachedMenuBarHeight
        )
        do {
            let reply = try await client.enumerate(AXEnumerateRequest(
                displayID: nil,
                maximumItemHeight: Double(maximumItemHeight)
            ))
            guard reply.accessibilityTrusted, reply.errorDescription == nil else {
                handleUnusableReply(reply, client: client)
                return nil
            }
            if untrustedPolicy.withLock({ $0.noteTrusted() }) {
                diagLog.info("subprocess walk trusted again")
            }
            return MenuBarItemAXProvider.items(fromSubprocess: reply.items)
        } catch is CancellationError {
            // A newer walk superseded this one; nothing failed.
            return nil
        } catch {
            let reason = client.lastExitDescription.map { " (\($0))" } ?? ""
            let abandoned = client.hasAbandonedHelper ? "; helper disabled for this session" : ""
            diagLog.error("subprocess walk failed: \(error)\(reason)\(abandoned)")
            return nil
        }
    }

    /// Replaces a helper that reports it is not trusted.
    ///
    /// macOS settles a process's Accessibility trust when it starts, so a
    /// helper launched at login before trust was in place stays untrusted for
    /// its whole life. Asking it again cannot help; a new process is checked
    /// afresh. Until the replacement is due
    /// the walk reads in-process without asking.
    private static func handleUnusableReply(_ reply: AXEnumerateReply, client: AXSubprocessClient) {
        guard !reply.accessibilityTrusted else {
            diagLog.warning("subprocess walk unusable: \(reply.errorDescription ?? "unknown error")")
            return
        }
        let backoff = untrustedPolicy.withLock { $0.noteUntrusted(now: .now) }
        client.stop()
        diagLog.warning(
            "subprocess walk unusable: helper not trusted; replacing it, next try in \(backoff.retryAfter)" +
                (backoff.isGivingUp ? ", retrying rarely from now on" : "")
        )
    }
}

/// When to ask a helper that keeps reporting it is not trusted.
///
/// Each untrusted answer replaces the helper and waits longer before asking
/// the next one: 5 s, then 15 s, then 45 s. Past that the grant is
/// probably missing rather than late, so the helper is asked every ten
/// minutes, which still notices a grant made later in System Settings. A
/// trusted answer resets everything.
nonisolated struct UntrustedHelperPolicy {
    static let backoffs: [Duration] = [.seconds(5), .seconds(15), .seconds(45)]
    static let rareRetry: Duration = .seconds(600)

    private(set) var untrustedCount = 0
    private var nextAsk: ContinuousClock.Instant?

    func shouldAsk(now: ContinuousClock.Instant) -> Bool {
        nextAsk.map { now >= $0 } ?? true
    }

    mutating func noteUntrusted(now: ContinuousClock.Instant) -> (retryAfter: Duration, isGivingUp: Bool) {
        untrustedCount += 1
        let index = untrustedCount - 1
        let isGivingUp = index >= Self.backoffs.count
        let delay = isGivingUp ? Self.rareRetry : Self.backoffs[index]
        nextAsk = now + delay
        return (delay, isGivingUp)
    }

    /// Resets after a trusted answer. Returns whether the helper had been
    /// untrusted, so the recovery is logged once.
    mutating func noteTrusted() -> Bool {
        defer {
            untrustedCount = 0
            nextAsk = nil
        }
        return untrustedCount > 0
    }
}

extension MenuBarItemAXProvider {
    /// Builds [MenuBarItem] from a subprocess observation list.
    ///
    /// Mirrors the in-process per-app loop through MenuBarItemAXProvider.rawItem(namespace:identifier:childIdentifier:accessibilityDescription:childDescription:axTitle:fallbackIndex:bounds:ownerPID:):
    /// per-app fallback titles, the stable AX identifier rule including the
    /// nested-child fallback, identity derivation, and the overflow-control
    /// skip. The helper already dropped oversized children.
    static nonisolated func items(fromSubprocess observations: [AXItemObservation]) -> [MenuBarItem] {
        var raw: [RawItem] = []
        var fallbackIndexByBundle: [String: Int] = [:]

        for observation in observations where !observation.isOverflowControl {
            let namespace = namespace(
                forBundleIdentifier: observation.bundleID,
                localizedName: observation.processName
            )
            let bundleKey = observation.bundleID ?? ""
            let fallbackIndex = fallbackIndexByBundle[bundleKey, default: 0]
            let derived = rawItem(
                namespace: namespace,
                identifier: nilIfBlank(observation.identifier),
                childIdentifier: nilIfBlank(observation.childIdentifier),
                accessibilityDescription: nilIfBlank(observation.accessibilityDescription),
                childDescription: nilIfBlank(observation.childDescription),
                axTitle: nilIfBlank(observation.title),
                fallbackIndex: fallbackIndex,
                bounds: observation.frame,
                ownerPID: observation.ownerPID
            )
            fallbackIndexByBundle[bundleKey] = derived.fallbackIndex
            guard let item = derived.item else { continue }
            raw.append(item)
        }
        return assemble(raw)
    }

    private static nonisolated func nilIfBlank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
