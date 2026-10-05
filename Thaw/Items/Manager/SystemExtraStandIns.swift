//
//  SystemExtraStandIns.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import PlatformRuntimeKit

// MARK: - Stand-in

/// A Thaw-owned status item that takes the place of an Apple menu extra Thaw
/// has removed natively.
///
/// Each runs from its own bundle in Contents/Library/Extras because macOS 27
/// conceals per bundle; inside Thaw it could not be hidden apart from Thaw.
enum SystemExtraStandIn: String, CaseIterable {
    case focus
    case timeMachine = "timemachine"
    case timer
    case airDrop = "airdrop"
    case nowPlaying = "nowplaying"
    case userSwitcher = "user"
    case textInput = "textinput"

    init(_ item: SystemExtraItem) {
        switch item {
        case .timeMachine: self = .timeMachine
        case .timer: self = .timer
        case .textInput: self = .textInput
        }
    }

    var bundleIdentifier: String {
        "\(ThawMenuBarIdentity.bundleIdentifier).extra.\(rawValue)"
    }

    /// Must match ExtraRole.autosaveName in ThawExtraHelper.
    private var autosaveName: String {
        switch self {
        case .focus: "Thaw.Extra.Focus"
        case .timeMachine: "Thaw.Extra.TimeMachine"
        case .timer: "Thaw.Extra.Timer"
        case .airDrop: "Thaw.Extra.AirDrop"
        case .nowPlaying: "Thaw.Extra.NowPlaying"
        case .userSwitcher: "Thaw.Extra.UserSwitcher"
        case .textInput: "Thaw.Extra.TextInput"
        }
    }

    /// The persistent identifier the stand-in's item gets in the layout.
    var itemIdentifier: String {
        "\(bundleIdentifier):\(autosaveName)"
    }

    private var bundleName: String {
        switch self {
        case .focus: "Thaw Focus"
        case .timeMachine: "Thaw Time Machine"
        case .timer: "Thaw Timer"
        case .airDrop: "Thaw AirDrop"
        case .nowPlaying: "Thaw Now Playing"
        case .userSwitcher: "Thaw User Switcher"
        case .textInput: "Thaw Text Input"
        }
    }

    var bundleURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Library/Extras/\(bundleName).app")
    }
}

// MARK: - Visibility

/// Hides Thaw's extra bundles itself: Control Center's app list may have no record of them.
/// Must match ExtraVisibilityChannel in ThawExtraHelper.
@MainActor
enum ExtraVisibilityChannel {
    private static let log = DiagLog(category: "SystemExtraStandIn")
    private static var lastHidden: Set<String>?

    static func ownsBundle(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("\(ThawMenuBarIdentity.bundleIdentifier).extra.")
    }

    static var file: URL {
        file(in: ItemStandInSlot.folder)
    }

    static func file(in folder: URL) -> URL {
        folder.appending(path: "hidden-extras.txt")
    }

    static var notification: Notification.Name {
        Notification.Name("\(ThawMenuBarIdentity.bundleIdentifier).extra.visibility")
    }

    static func hide(_ bundleIDs: Set<String>) {
        hide(bundleIDs, folder: ItemStandInSlot.folder, announce: announceChange)
    }

    /// The folder and the announcement are parameters so tests write to a scratch folder and post nothing.
    static func hide(_ bundleIDs: Set<String>, folder: URL, announce: () -> Void) {
        guard bundleIDs != lastHidden else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bundleIDs.sorted().joined(separator: "\n").write(to: file(in: folder), atomically: true, encoding: .utf8)
        } catch {
            log.error("could not write hidden extras: \(error.localizedDescription)")
            return
        }
        lastHidden = bundleIDs
        announce()
        log.info("hidden extras: \(bundleIDs.sorted())")
    }

    private static func announceChange() {
        DistributedNotificationCenter.default().postNotificationName(
            notification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

// MARK: - Launcher

/// Starts and stops stand-in bundles, and gives each the original's place in
/// the layout before it first appears.
///
/// Assigned before launch, or it flashes into the visible bar and is filed as
/// a new arrival.
@MainActor
final class SystemExtraStandInLauncher: SystemExtraReplacementProviding {
    weak var controller: RuntimeSectionController?
    /// Records an identifier as seen, so the stand-in is not routed to the
    /// new-items section instead of the original's slot.
    var markKnown: ((String) -> Void)?
    /// Stand-ins given a section of their own. Only these have a section worth
    /// mirroring back onto their original.
    private(set) var placed: Set<SystemExtraStandIn> = []
    private let log = DiagLog(category: "SystemExtraStandIn")
    /// Stand-ins that should be running, each watched so one that exits on its
    /// own is started again. The app is held for as long as it is observed:
    /// KVO on a released NSRunningApplication crashes.
    private var watched: [SystemExtraStandIn: (app: NSRunningApplication, observation: NSKeyValueObservation)] = [:]
    /// Recent restarts per stand-in, so one that cannot stay up is not
    /// relaunched forever.
    private var restarts: [SystemExtraStandIn: [Date]] = [:]
    private static let restartLimit = 3
    private static let restartWindow: TimeInterval = 30

    func publish(item: SystemExtraItem, canonicalIdentifier: String, section: MenuBarSectionName) async throws {
        try await launch(SystemExtraStandIn(item), replacing: canonicalIdentifier, in: section)
    }

    func remove(item: SystemExtraItem) {
        stop(SystemExtraStandIn(item))
    }

    func launch(
        _ standIn: SystemExtraStandIn,
        replacing original: String,
        in section: MenuBarSectionName
    ) async throws {
        guard FileManager.default.fileExists(atPath: standIn.bundleURL.path) else {
            throw SystemExtraTakeoverError.replacementUnavailable
        }
        markKnown?(MenuBarItemTag.canonicalPersistentIdentifier(standIn.itemIdentifier))
        place(standIn, after: original, in: section)
        try await open(standIn)
        log.info("launched \(standIn.rawValue) stand-in in \(section.rawValue)")
    }

    func stop(_ standIn: SystemExtraStandIn) {
        placed.remove(standIn)
        watched[standIn]?.observation.invalidate()
        watched[standIn] = nil
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: standIn.bundleIdentifier) {
            app.terminate()
        }
    }

    /// Starts the stand-in, or adopts the instance already running, and
    /// watches it.
    ///
    /// After a Thaw relaunch macOS may hand back the dying previous instance;
    /// the watch restarts it when it exits.
    private func open(_ standIn: SystemExtraStandIn) async throws {
        let app: NSRunningApplication
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: standIn.bundleIdentifier)
            .first(where: { !$0.isTerminated })
        {
            app = running
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            configuration.promptsUserIfNeeded = false
            // The stand-in exits when this process does. Naming the process rather
            // than the bundle keeps it from latching onto an instance mid-quit.
            configuration.arguments = ["--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
            app = try await NSWorkspace.shared.openApplication(at: standIn.bundleURL, configuration: configuration)
        }
        let observation = app.observe(\.isTerminated, options: [.new]) { [weak self] app, _ in
            guard app.isTerminated else { return }
            let pid = app.processIdentifier
            Task { @MainActor in self?.standInExited(standIn, pid: pid) }
        }
        watched[standIn] = (app, observation)
        if app.isTerminated {
            standInExited(standIn, pid: app.processIdentifier)
        }
    }

    private func standInExited(_ standIn: SystemExtraStandIn, pid: pid_t) {
        guard let entry = watched[standIn], entry.app.processIdentifier == pid else { return }
        entry.observation.invalidate()
        watched[standIn] = nil
        let now = Date()
        let recent = (restarts[standIn] ?? []).filter { now.timeIntervalSince($0) < Self.restartWindow }
        guard recent.count < Self.restartLimit else {
            log.error("\(standIn.rawValue) stand-in keeps exiting; not starting it again")
            return
        }
        restarts[standIn] = recent + [now]
        log.info("\(standIn.rawValue) stand-in (pid \(pid)) exited; starting it again")
        Task { [weak self] in
            do {
                try await self?.open(standIn)
            } catch {
                self?.log.error("\(standIn.rawValue) stand-in restart failed: \(error.localizedDescription)")
            }
        }
    }

    /// Puts the stand-in in section, right after the original when the
    /// original is in that section's order, so it takes the original's slot.
    /// A stand-in the user has already placed elsewhere stays there.
    private func place(_ standIn: SystemExtraStandIn, after original: String, in section: MenuBarSectionName) {
        guard let controller else { return }
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(standIn.itemIdentifier)
        if controller.authoredSection(for: identifier) != section {
            controller.setSection(section, identifier: identifier)
        }
        placed.insert(standIn)
        var order = controller.sectionItemOrder[section] ?? []
        let canonicalOriginal = MenuBarItemTag.canonicalPersistentIdentifier(original)
        guard let originalIndex = order.firstIndex(of: canonicalOriginal),
              order.firstIndex(of: identifier) != originalIndex + 1
        else {
            return
        }
        order.removeAll { $0 == identifier }
        let insertAt = order.firstIndex(of: canonicalOriginal).map { $0 + 1 } ?? order.endIndex
        order.insert(identifier, at: insertAt)
        controller.setSectionOrder(order, for: section)
    }
}
