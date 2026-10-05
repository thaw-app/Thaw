//
//  ExtraHelperDelegate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import OSLog

/// Publishes one status item standing in for an Apple menu extra that Thaw has
/// removed, and exits when the Thaw that launched it quits.
@MainActor
final class ExtraHelperDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThawExtraHelper", category: "extra")
    private var role: ExtraRole?
    private var statusItem: NSStatusItem?
    private var focus: FocusExtra?
    private var textInput: TextInputExtra?
    private var slotStandIn: SlotStandIn?
    /// Held for as long as it is observed: KVO on a released
    /// NSRunningApplication crashes the helper.
    private var parent: NSRunningApplication?
    private var parentObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_: Notification) {
        // An item published without a bundle identity has no identity on
        // macOS 27 either, and would leave a nameless row in the agent's table.
        guard let bundleID = Bundle.main.bundleIdentifier,
              let role = ExtraRole(bundleIdentifier: bundleID)
        else {
            logger.error("Refusing to publish outside a Thaw extra bundle")
            NSApp.terminate(nil)
            return
        }
        self.role = role
        exitWithParent(ExtraRole.parentBundleIdentifier(of: bundleID))

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Named before the first visibility change, so the agent never records
        // an unnamed placeholder for it.
        item.autosaveName = role.autosaveName
        item.behavior = []
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.setAccessibilityIdentifier(role.autosaveName)
            button.setAccessibilityLabel(role.displayName)
        }
        statusItem = item
        // Read before the first show, so a hidden stand-in never flashes in.
        observeVisibility(bundleID: bundleID)

        if let slot = role.slot, let parentID = ExtraRole.parentBundleIdentifier(of: bundleID), let button = item.button {
            // Thaw opens the real item; the stand-in has no menu of its own.
            slotStandIn = SlotStandIn(slot: slot, parentBundleIdentifier: parentID, button: button)
            return
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        if role == .focus {
            let focus = FocusExtra { [weak self] symbol, label in self?.setImage(symbol, label: label) }
            focus.start()
            self.focus = focus
        } else if role == .textInput, let button = item.button {
            let textInput = TextInputExtra(button: button)
            textInput.start()
            self.textInput = textInput
        } else if role == .airDrop {
            statusItem?.button?.image = AirDropGlyph.image(accessibilityDescription: role.displayName)
            statusItem?.button?.toolTip = role.displayName
        } else {
            setImage(role.symbolName, label: role.displayName)
        }
    }

    func applicationWillTerminate(_: Notification) {
        focus?.stop()
        textInput?.stop()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch role {
        case .focus:
            focus?.populate(menu)
        case .timeMachine:
            menu.addItem(actionItem(String(localized: "Back Up Now"), #selector(backUpNow)))
            menu.addItem(actionItem(String(localized: "Browse Time Machine Backups"), #selector(browseBackups)))
            menu.addItem(.separator())
            menu.addItem(actionItem(String(localized: "Open Time Machine Settings…"), #selector(openTimeMachineSettings)))
        case .timer:
            menu.addItem(actionItem(String(localized: "Open Timers in Clock"), #selector(openClock)))
        case .airDrop:
            menu.addItem(actionItem(String(localized: "Open AirDrop"), #selector(openAirDrop)))
            menu.addItem(.separator())
            menu.addItem(actionItem(String(localized: "AirDrop Settings…"), #selector(openAirDropSettings)))
        case .nowPlaying:
            NowPlayingCommands.populate(menu)
        case .userSwitcher:
            UserSessionCommands.populate(menu)
        case .textInput:
            textInput?.populate(menu)
        case .slot1, .slot2, .slot3, .slot4, .slot5, .slot6, nil:
            break
        }
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func backUpNow() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tmutil")
        process.arguments = ["startbackup", "--auto"]
        do {
            try process.run()
        } catch {
            logger.error("tmutil startbackup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func browseBackups() {
        NSWorkspace.shared.open(URL(filePath: "/System/Applications/Time Machine.app"))
    }

    @objc private func openTimeMachineSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openClock() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func openAirDrop() {
        let url = URL(filePath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func openAirDropSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Visibility

    /// Thaw hides its own bundles: Control Center may have no record of a stand-in.
    private func observeVisibility(bundleID: String) {
        guard let parentID = ExtraRole.parentBundleIdentifier(of: bundleID) else {
            statusItem?.isVisible = true
            return
        }
        applyVisibility(bundleID: bundleID, parentID: parentID)
        DistributedNotificationCenter.default().addObserver(
            forName: ExtraVisibilityChannel.notification(parent: parentID),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyVisibility(bundleID: bundleID, parentID: parentID)
            }
        }
    }

    private func applyVisibility(bundleID: String, parentID: String) {
        let isVisible = !ExtraVisibilityChannel.hiddenBundles(parent: parentID).contains(bundleID)
        guard statusItem?.isVisible != isVisible else { return }
        statusItem?.isVisible = isVisible
    }

    // MARK: Helpers

    private func setImage(_ symbolName: String, label: String) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: label)
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = label
    }

    /// A stand-in must never outlive the Thaw that put it there: with Thaw gone
    /// nothing restores the original, and the stand-in would be all that is left.
    ///
    /// Thaw passes its process identifier as --parent-pid. Matching by bundle
    /// identifier alone can pick the instance that quit a moment before a
    /// relaunch, which reads as terminated and takes the new stand-in with it.
    /// The bundle lookup remains for a helper started by hand.
    ///
    /// Watches the parent's own isTerminated because the workspace's
    /// termination notification does not reach this accessory process when
    /// Thaw quits.
    private func exitWithParent(_ parentBundleID: String?) {
        guard let parentBundleID else { return }
        let arguments = CommandLine.arguments
        let pidArgument = arguments.firstIndex(of: "--parent-pid").flatMap { index in
            arguments.indices.contains(index + 1) ? pid_t(arguments[index + 1]) : nil
        }
        let candidate = pidArgument.flatMap(NSRunningApplication.init(processIdentifier:))
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: parentBundleID)
            .first { !$0.isTerminated }
        guard let parent = candidate, parent.bundleIdentifier == parentBundleID else {
            logger.notice("\(parentBundleID, privacy: .public) is not running; exiting")
            NSApp.terminate(nil)
            return
        }
        self.parent = parent
        parentObservation = parent.observe(\.isTerminated, options: [.initial, .new]) { [logger] app, _ in
            guard app.isTerminated else { return }
            Task { @MainActor in
                logger.notice("\(parentBundleID, privacy: .public) quit; exiting")
                NSApp.terminate(nil)
            }
        }
    }
}

extension ExtraRole {
    /// The symbol scripts/assemble-extra-helper.sh wrote into this bundle,
    /// the one table Thaw also reads to draw the stand-in.
    var symbolName: String {
        Bundle.main.object(forInfoDictionaryKey: "ThawExtraSymbol") as? String ?? "questionmark.circle"
    }
}
