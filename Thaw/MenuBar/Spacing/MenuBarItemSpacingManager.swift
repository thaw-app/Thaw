//
//  MenuBarItemSpacingManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Manager for menu bar item spacing.
@MainActor
final class MenuBarItemSpacingManager {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarItemSpacingManager")
    /// UserDefaults keys.
    private enum Key: String {
        case spacing = "NSStatusItemSpacing"
        case padding = "NSStatusItemSelectionPadding"

        /// The default value for the key.
        var defaultValue: Int {
            switch self {
            case .spacing: 16
            case .padding: 16
            }
        }
    }

    /// An error thrown when an app fails to terminate after force-quitting.
    private struct AppNotTerminatedError: Error {}

    /// An error that groups multiple failed app relaunches.
    private struct GroupedRelaunchError: LocalizedError {
        let failedApps: [String]

        var errorDescription: String? {
            "The following applications failed to quit and were not restarted:\n"
                + failedApps.joined(separator: "\n")
        }

        var recoverySuggestion: String? {
            "You may need to log out for the changes to take effect."
        }
    }

    /// Delay before force terminating an app.
    private let forceTerminateDelay = 5

    /// The offset to apply to the default spacing and padding.
    /// Does not take effect until ``applyOffset()`` is called.
    var offset = 0

    /// Runs a command with the given arguments.
    private func runCommand(_ command: String, with arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = Constants.menuBarItemSpacingExecutableURL
            process.arguments = CollectionOfOne(command) + arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: MenuBarItemSpacingError(
                        kind: .nonZeroExitStatus(process.terminationStatus),
                        command: command,
                        arguments: arguments
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: MenuBarItemSpacingError(
                    kind: .processRun(error),
                    command: command,
                    arguments: arguments
                ))
            }
        }
    }

    /// Sets the value for the specified key to the key's default value plus the given offset.
    private func setOffset(_ offset: Int, forKey key: Key) async throws {
        try await runCommand(
            "defaults",
            with: [
                "-currentHost", "write", "-globalDomain", key.rawValue, "-int",
                String(key.defaultValue + offset),
            ]
        )
    }

    /// Asynchronously signals the given app to quit.
    private func signalAppToQuit(_ app: NSRunningApplication) async throws {
        if app.isTerminated {
            MenuBarItemSpacingManager.diagLog.debug(
                "Application \"\(app.logString)\" is already terminated"
            )
            return
        }

        MenuBarItemSpacingManager.diagLog.debug(
            "Signaling application \"\(app.logString)\" to quit"
        )

        app.terminate()

        let pollInterval: Duration = .milliseconds(50)
        let deadline = ContinuousClock.now.advanced(by: .seconds(forceTerminateDelay))

        while !app.isTerminated, ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }

        if !app.isTerminated {
            MenuBarItemSpacingManager.diagLog.debug(
                """
                Application "\(app.logString)" did not terminate within \
                \(forceTerminateDelay) seconds, attempting to force terminate
                """
            )
            app.forceTerminate()
            try? await Task.sleep(for: .seconds(1))

            if !app.isTerminated {
                throw AppNotTerminatedError()
            }
        }

        MenuBarItemSpacingManager.diagLog.debug(
            "Application \"\(app.logString)\" terminated successfully"
        )
    }

    /// Asynchronously launches the app at the given URL.
    private func launchApp(
        at applicationURL: URL,
        bundleIdentifier: String
    ) async throws {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            MenuBarItemSpacingManager.diagLog.debug(
                "Application \"\(app.logString)\" is already open, so skipping launch"
            )
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.promptsUserIfNeeded = false
        try await NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }

    /// Asynchronously relaunches the given app.
    private func relaunchApp(_ app: NSRunningApplication) async throws {
        struct RelaunchError: Error {}
        guard
            let url = app.bundleURL,
            let bundleIdentifier = app.bundleIdentifier
        else {
            throw RelaunchError()
        }
        try await signalAppToQuit(app)
        if app.isTerminated {
            try await launchApp(at: url, bundleIdentifier: bundleIdentifier)
        } else {
            throw RelaunchError()
        }
    }

    /// Writes the current offset to the system defaults.
    private func writeDefaults(for offset: Int) async throws {
        try await setOffset(offset, forKey: .spacing)
        try await setOffset(offset, forKey: .padding)
    }

    /// Applies the current ``offset``.
    ///
    /// - Note: Calling this restarts all apps with a menu bar item.
    func applyOffset() async throws {
        let previousOffset = offset

        try await writeDefaults(for: offset)

        try? await Task.sleep(for: .milliseconds(100))

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        let pids = Set(items.map { $0.sourcePID ?? $0.ownerPID })

        var failedApps = [String]()

        await withTaskGroup(of: String?.self) { group in
            for pid in pids {
                guard
                    let app = NSRunningApplication(processIdentifier: pid),
                    app != .current
                else {
                    continue
                }
                group.addTask {
                    do {
                        try await self.relaunchApp(app)
                    } catch {
                        guard let name = app.localizedName else { return nil }
                        if app.bundleIdentifier == "com.apple.Spotlight" {
                            if let latestSpotlightInstance =
                                NSRunningApplication.runningApplications(
                                    withBundleIdentifier: "com.apple.Spotlight"
                                ).first,
                                latestSpotlightInstance.processIdentifier == app.processIdentifier
                            {
                                return name
                            }
                        } else {
                            return name
                        }
                    }
                    return nil
                }
            }
            for await failure in group {
                if let name = failure {
                    failedApps.append(name)
                }
            }
        }

        if !failedApps.isEmpty {
            offset = previousOffset
            try? await writeDefaults(for: previousOffset)
            throw GroupedRelaunchError(failedApps: failedApps)
        }
    }
}

private extension NSRunningApplication {
    /// A string to use for logging purposes.
    var logString: String {
        localizedName ?? bundleIdentifier ?? "<NIL>"
    }
}
