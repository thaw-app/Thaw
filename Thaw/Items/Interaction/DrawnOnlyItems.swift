//
//  DrawnOnlyItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import Synchronization
import ThawAXCore

/// Status items that MenuBarAgent's window lists but whose app's own tree does not.
///
/// Some apps answer the walk at once with no extras-bar items while MenuBarAgent draws their icon.
/// For an app with exactly one drawn entry, the walk records the item an untitled extras-bar child of
/// that app would give, so it gets the same tag, the same synthetic window ID and the same position
/// store key. An app with more than one entry is left out, since nothing says which entry is which.
nonisolated enum DrawnOnlyItems {
    typealias Entry = MenuBarAgentWindow.Entry
    typealias RawItem = MenuBarItemAXProvider.RawItem

    /// What the selection needs to know about a running app.
    struct App: Equatable, Sendable {
        let bundleID: String?
        let localizedName: String?
    }

    /// The vertical band this pass's items sit in.
    struct Band: Equatable, Sendable {
        let minY: CGFloat
        let height: CGFloat
    }

    /// The owners a pass found drawn and silent.
    struct Selection: Equatable, Sendable {
        /// Owners with one drawn entry, by pid.
        let owners: [pid_t: Entry]
        /// Owners left out because they have more than one drawn entry.
        let multiEntryOwners: Set<pid_t>
    }

    /// How a pass records an owner whose empty answer waited on the drawn read.
    enum Answer: Equatable, Sendable {
        case record([RawItem])
        /// The drawn read was taken mid-change, so the owner's last answer stands and the pass is incomplete.
        case keepPrior
    }

    /// What one pass knows besides the drawn read.
    struct Pass: Sendable {
        let apps: [pid_t: App]
        /// This app's pid, MenuBarAgent's and the control pids.
        let excluded: Set<pid_t>
        /// The items the AX walk read this pass.
        let axItems: [RawItem]
        /// The tallest frame that still counts as a status item.
        let ceiling: CGFloat
    }

    /// The result of settling a pass's waiting owners.
    struct Resolution: Equatable, Sendable {
        let answers: [pid_t: Answer]
        let newlyConfirmed: Set<pid_t>
        let newlySkipped: Set<pid_t>
    }

    /// More than this share of an entry's width covered by an AX item means the item is already read.
    static let overlapThreshold: CGFloat = 0.5

    /// The drawn entries whose owner answered this pass with no items and could own a status item.
    ///
    /// An owner qualifies when it answered empty this pass (not skipped, timed out or cooling down),
    /// is not excluded, is a running app with a bundle id outside this app's and MenuBarAgent's
    /// namespaces, and its entry is not mostly covered by an AX item read this pass.
    static func silentDrawnOwners(
        entries: [Entry],
        answeredEmpty: Set<pid_t>,
        excluded: Set<pid_t>,
        apps: [pid_t: App],
        axItems: [RawItem]
    ) -> Selection {
        let grouped = Dictionary(grouping: entries.filter { entry in
            answeredEmpty.contains(entry.ownerPID) && !excluded.contains(entry.ownerPID)
                && apps[entry.ownerPID].map(ownsStatusItems) == true
        }, by: \.ownerPID)
        var owners: [pid_t: Entry] = [:]
        var multiEntryOwners = Set<pid_t>()
        for (owner, ownerEntries) in grouped {
            guard ownerEntries.count == 1, let entry = ownerEntries.first else {
                multiEntryOwners.insert(owner)
                continue
            }
            if !axItems.contains(where: { covers($0.bounds, entry.frame) }) {
                owners[owner] = entry
            }
        }
        return Selection(owners: owners, multiEntryOwners: multiEntryOwners)
    }

    private static func ownsStatusItems(_ app: App) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        let namespace = MenuBarItemAXProvider.namespace(forBundleIdentifier: bundleID, localizedName: app.localizedName)
        return namespace != .thaw && namespace != .menuBarAgent
    }

    /// Whether an item covers more than the threshold of an entry's width on the same row.
    static func covers(_ item: CGRect, _ entry: CGRect) -> Bool {
        guard entry.width > 0, item.minY < entry.maxY, entry.minY < item.maxY else { return false }
        let shared = min(item.maxX, entry.maxX) - max(item.minX, entry.minX)
        return shared > entry.width * overlapThreshold
    }

    /// The item an untitled extras-bar child of the app would give, titled with the app's name.
    static func rawItem(ownerPID: pid_t, app: App, frame: CGRect) -> RawItem? {
        let namespace = MenuBarItemAXProvider.namespace(forBundleIdentifier: app.bundleID, localizedName: app.localizedName)
        guard let item = MenuBarItemAXProvider.rawItem(
            namespace: namespace,
            identifier: nil,
            childIdentifier: nil,
            accessibilityDescription: nil,
            childDescription: nil,
            axTitle: nil,
            fallbackIndex: 0,
            bounds: frame,
            ownerPID: ownerPID
        ).item else { return nil }
        return RawItem(
            namespace: item.namespace,
            identityTitle: item.identityTitle,
            displayTitle: app.localizedName ?? item.displayTitle,
            bounds: frame,
            ownerPID: ownerPID
        )
    }

    /// The median band of this pass's items. MenuBarAgent's own items are left out: its wrappers
    /// span the full bar height.
    static func band(of axItems: [RawItem]) -> Band? {
        let frames = axItems.filter { $0.namespace != .menuBarAgent }.map(\.bounds)
        guard !frames.isEmpty else { return nil }
        return Band(minY: median(frames.map(\.minY)), height: median(frames.map(\.height)))
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The entry's frame as an AX item would report it.
    ///
    /// The drawn entry spans the full bar height, so the band of this pass's items gives the
    /// vertical extent. With no band, an entry taller than the ceiling is inset to it, centred.
    static func normalizedFrame(entry: CGRect, band: Band?, ceiling: CGFloat) -> CGRect {
        if let band {
            return CGRect(x: entry.minX, y: band.minY, width: entry.width, height: band.height)
        }
        guard entry.height > ceiling else { return entry }
        return entry.insetBy(dx: 0, dy: (entry.height - ceiling) / 2)
    }

    /// Settles the owners whose empty answer waited on the drawn read.
    ///
    /// A settled read records the synthesized item for each confirmed owner and nothing for the rest.
    /// A nil read, taken mid-change, keeps every waiting owner's last answer and guesses nothing.
    static func resolve(
        pending: Set<pid_t>,
        read: [Entry]?,
        pass: Pass,
        ledger: DrawnOnlyOwnerLedger,
        now: ContinuousClock.Instant = .now
    ) -> Resolution {
        guard let read else {
            return Resolution(answers: pending.reduce(into: [:]) { $0[$1] = .keepPrior }, newlyConfirmed: [], newlySkipped: [])
        }
        let selection = silentDrawnOwners(
            entries: read, answeredEmpty: pending, excluded: pass.excluded, apps: pass.apps, axItems: pass.axItems
        )
        let confirmation = ledger.confirm(
            silent: Set(selection.owners.keys),
            answered: pending.union(pass.axItems.map(\.ownerPID)),
            running: Set(pass.apps.keys),
            now: now
        )
        let band = band(of: pass.axItems)
        var answers: [pid_t: Answer] = [:]
        for owner in pending {
            guard confirmation.confirmed.contains(owner), let entry = selection.owners[owner],
                  let item = item(for: owner, entry: entry, pass: pass, band: band)
            else {
                answers[owner] = .record([])
                continue
            }
            answers[owner] = .record([item])
        }
        return Resolution(
            answers: answers,
            newlyConfirmed: confirmation.newlyConfirmed,
            newlySkipped: ledger.firstSkips(of: selection.multiEntryOwners)
        )
    }

    /// The items a walk that doesn't report empty answers adds, such as the helper process's walk.
    ///
    /// Each owner the in-process walk confirmed adds its item when this walk found no items for it.
    /// The selection is the same, so an owner with several entries, or whose entry an item covers, adds nothing.
    static func confirmedItems(confirmed: Set<pid_t>, read: [Entry], pass: Pass) -> [RawItem] {
        let silent = confirmed.subtracting(pass.axItems.map(\.ownerPID))
        guard !silent.isEmpty else { return [] }
        let selection = silentDrawnOwners(
            entries: read, answeredEmpty: silent, excluded: pass.excluded, apps: pass.apps, axItems: pass.axItems
        )
        let band = band(of: pass.axItems)
        return selection.owners.sorted { $0.key < $1.key }.compactMap { owner, entry in
            item(for: owner, entry: entry, pass: pass, band: band)
        }
    }

    /// The item an owner's drawn entry stands for, sized to the band this pass's items sit in.
    private static func item(for owner: pid_t, entry: Entry, pass: Pass, band: Band?) -> RawItem? {
        guard let app = pass.apps[owner] else { return nil }
        return rawItem(ownerPID: owner, app: app, frame: normalizedFrame(entry: entry.frame, band: band, ceiling: pass.ceiling))
    }
}

/// Owners found drawn and silent, and since when.
///
/// An owner must stay drawn and silent for the confirmation delay before its item is synthesized, so
/// an app that publishes its items a moment after drawing them is read the normal way. An owner that
/// answers with items, or is no longer drawn, leaves; one that quits is dropped.
nonisolated final class DrawnOnlyOwnerLedger: Sendable {
    static let confirmationDelay = Duration.seconds(2)

    /// Whether an owner first seen silent at start has stayed silent for the confirmation delay.
    static func hasStayedSilent(since start: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Bool {
        guard let start else { return false }
        return now - start >= confirmationDelay
    }

    struct Confirmation: Equatable, Sendable {
        let confirmed: Set<pid_t>
        let newlyConfirmed: Set<pid_t>
    }

    private struct State {
        var silentSince: [pid_t: ContinuousClock.Instant] = [:]
        var confirmed: Set<pid_t> = []
        var skipped: Set<pid_t> = []
    }

    private let state = Mutex(State())

    /// The owners being watched, confirmed or not.
    var owners: Set<pid_t> {
        state.withLock { Set($0.silentSince.keys) }
    }

    /// The owners silent for at least the confirmation delay as of now.
    func confirmedOwners(now: ContinuousClock.Instant = .now) -> Set<pid_t> {
        state.withLock { state in
            Set(state.silentSince.filter { now - $0.value >= Self.confirmationDelay }.keys)
        }
    }

    /// Records one pass and returns the owners silent for at least the confirmation delay.
    ///
    /// - Parameters:
    ///   - silent: Owners drawn and silent this pass.
    ///   - answered: Owners that answered this pass. Those not silent leave.
    ///   - running: The running pids. Every other owner is dropped.
    func confirm(
        silent: Set<pid_t>,
        answered: Set<pid_t>,
        running: Set<pid_t>,
        now: ContinuousClock.Instant = .now
    ) -> Confirmation {
        state.withLock { state in
            let leaving = answered.subtracting(silent)
            state.silentSince = state.silentSince.filter { running.contains($0.key) && !leaving.contains($0.key) }
            state.skipped.formIntersection(running)
            for owner in silent where state.silentSince[owner] == nil {
                state.silentSince[owner] = now
            }
            let confirmed = Set(silent.filter { Self.hasStayedSilent(since: state.silentSince[$0], now: now) })
            let newlyConfirmed = confirmed.subtracting(state.confirmed)
            state.confirmed = state.confirmed.intersection(state.silentSince.keys).union(confirmed)
            return Confirmation(confirmed: confirmed, newlyConfirmed: newlyConfirmed)
        }
    }

    /// The owners among skipped not reported before, so each skip is logged once per process.
    func firstSkips(of skipped: Set<pid_t>) -> Set<pid_t> {
        state.withLock { state in
            let fresh = skipped.subtracting(state.skipped)
            state.skipped.formUnion(fresh)
            return fresh
        }
    }
}

/// The walk's drawn-only fallback: which owners wait for the drawn read, and what each is recorded as.
/// Holds the ledger and the diagnostics, so the walk only reads the bar and records the answers.
nonisolated final class DrawnOnlyInventory: Sendable {
    private let diagLog = DiagLog(category: "MenuBarItemAXProvider")
    private let ledger = DrawnOnlyOwnerLedger()
    private let diagnostics = DrawnSilentOwnerDiagnostics()

    /// Owners whose empty answer waits for the drawn read: those drawn, and those the ledger watches.
    func candidates(drawn: [DrawnOnlyItems.Entry]?) -> Set<pid_t> {
        ledger.owners.union(drawn?.map(\.ownerPID) ?? [])
    }

    /// Settles the waiting owners against the drawn read, and hands the read to the diagnostics.
    ///
    /// - Parameters:
    ///   - pending: Owners that answered empty and waited for the read.
    ///   - answeredEmpty: Every owner that answered empty this pass, for the diagnostics.
    ///   - read: A settled read of MenuBarAgent's window, or nil when there was none or it was mid-change.
    ///   - apps: The running apps by pid.
    ///   - excluded: MenuBarAgent's pid and the control pids.
    ///   - axItems: The items the AX walk read this pass.
    func answers(
        pending: Set<pid_t>,
        answeredEmpty: Set<pid_t>,
        read: [DrawnOnlyItems.Entry]?,
        apps: [pid_t: NSRunningApplication],
        excluded: Set<pid_t>,
        axItems: [DrawnOnlyItems.RawItem]
    ) -> [pid_t: DrawnOnlyItems.Answer] {
        if let read {
            diagnostics.note(drawn: read, answeredEmpty: answeredEmpty, apps: apps)
        }
        guard !pending.isEmpty else { return [:] }
        let pass = pass(apps: apps, excluded: excluded, axItems: axItems)
        let resolution = DrawnOnlyItems.resolve(pending: pending, read: read, pass: pass, ledger: ledger)
        let name = { (pid: pid_t) in pass.apps[pid]?.bundleID ?? "(pid \(pid))" }
        for owner in resolution.newlyConfirmed.sorted() {
            diagLog.info("menuBarItems: \(name(owner)) is drawn but lists no items of its own; showing its icon from MenuBarAgent's window")
        }
        for owner in resolution.newlySkipped.sorted() {
            diagLog.info("menuBarItems: \(name(owner)) has more than one drawn entry but lists no items of its own; not showing it")
        }
        return resolution.answers
    }

    /// Whether any owner is confirmed drawn-only, so a walk can skip reading the bar when none is.
    var hasConfirmedOwners: Bool {
        !ledger.confirmedOwners().isEmpty
    }

    /// The items for confirmed owners that a walk without empty answers found nothing for. See DrawnOnlyItems.confirmedItems.
    func confirmedItems(
        read: [DrawnOnlyItems.Entry]?,
        apps: [pid_t: NSRunningApplication],
        excluded: Set<pid_t>,
        axItems: [DrawnOnlyItems.RawItem]
    ) -> [DrawnOnlyItems.RawItem] {
        let confirmed = ledger.confirmedOwners()
        guard !confirmed.isEmpty, let read else { return [] }
        return DrawnOnlyItems.confirmedItems(confirmed: confirmed, read: read, pass: pass(apps: apps, excluded: excluded, axItems: axItems))
    }

    private func pass(
        apps: [pid_t: NSRunningApplication],
        excluded: Set<pid_t>,
        axItems: [DrawnOnlyItems.RawItem]
    ) -> DrawnOnlyItems.Pass {
        DrawnOnlyItems.Pass(
            apps: apps.mapValues { DrawnOnlyItems.App(bundleID: $0.bundleIdentifier, localizedName: $0.localizedName) },
            excluded: excluded.union([getpid()]),
            axItems: axItems,
            ceiling: MenuBarItemAXProvider.maxItemHeight(menuBarHeight: NSScreen.tallestCachedMenuBarHeight)
        )
    }
}
