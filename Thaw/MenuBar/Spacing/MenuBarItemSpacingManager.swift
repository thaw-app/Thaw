//
//  MenuBarItemSpacingManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Subprocess

// Subprocess uses System.FilePath, so both sides must resolve the same module.
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Manager for menu bar item spacing.
@MainActor
final class MenuBarItemSpacingManager {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarItemSpacingManager")
    private enum Key: String {
        case spacing = "NSStatusItemSpacing"
        case padding = "NSStatusItemSelectionPadding"

        var defaultValue: Int {
            switch self {
            case .spacing: 16
            case .padding: 16
            }
        }
    }

    /// An error thrown when an app is still running after being asked to
    /// quit. The app is left alone; see signalAppToQuit(_:).
    private struct AppNotTerminatedError: Error {}

    /// Captured before the wave so the fallback opens the exact bundleURL
    /// that was running. Resolving the bundle ID later can pick a different
    /// copy, or fail for XPC helpers, login items, and LaunchAgents.
    private struct AppHandle {
        let bundleID: String
        let bundleURL: URL?

        /// Decided before the wave, while the executable URL is readable.
        /// Never `.leaveRunning`; those apps aren't captured.
        let strategy: SpacingRelaunchStrategy
    }

    /// Result of a single applyOffset call.
    struct ApplyOutcome {
        /// False when disk already matched the offset.
        let didRelaunch: Bool

        /// Bundle IDs expected to reattach an item after the wave, for
        /// gating settling. Excludes failures, apps left running, and Thaw.
        let recoveredBundleIDs: Set<String>

        /// Apps the fallback couldn't bring back. Apps left running on purpose
        /// aren't failures.
        let failedAppNames: [String]
    }

    /// Seconds an app gets to quit. Never force-terminated afterwards: it is
    /// usually holding a save sheet, so it keeps the old spacing instead.
    private let quitGracePeriod = 5

    /// Cap on captured stderr from the spacing subprocess.
    private static let errorByteLimit = 16 * 1024

    /// The offset to apply to the default spacing and padding.
    /// Does not take effect until applyOffset() is called.
    var offset = 0

    /// Whether a relaunch wave may run. Synced from `DisplaySettingsManager`,
    /// but kept here so this stays the one place that decides.
    var spacingApplyMode: SpacingApplyMode = .relaunchApps

    /// Serializes applyOffset. On a display switch, a second caller would
    /// see disk already matching and return false while the first is still
    /// mid-wave, so its layout pass wouldn't wait for items to settle.
    private let applyOffsetSemaphore = SimpleSemaphore(value: 1)

    /// Runs the executable at executableURL with the given arguments.
    private func runCommand(
        _ command: String,
        executable executableURL: URL,
        with arguments: [String]
    ) async throws {
        let result: ExecutionResult<Void, DiscardedOutput, StringOutput<UTF8>>
        do {
            // Run by absolute path from Info.plist, never via PATH. `command`
            // only describes the invocation in logs.
            result = try await Subprocess.run(
                .path(FilePath(executableURL.path)),
                arguments: Arguments(arguments),
                output: .discarded,
                error: .string(limit: Self.errorByteLimit)
            )
        } catch {
            throw MenuBarItemSpacingError(
                kind: .processRun(error),
                command: command,
                arguments: arguments
            )
        }

        guard result.terminationStatus.isSuccess else {
            let exitStatus: Int32 = switch result.terminationStatus {
            case let .exited(code): code
            case let .signaled(code): code
            }
            let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            MenuBarItemSpacingManager.diagLog.error(
                "\(command) \(arguments.joined(separator: " ")) exited with status \(exitStatus): \(stderr)"
            )
            throw MenuBarItemSpacingError(
                kind: .nonZeroExitStatus(exitStatus),
                command: command,
                arguments: arguments
            )
        }
    }

    /// Sets the value for the specified key to the key's default value plus the given offset.
    private func setOffset(_ offset: Int, forKey key: Key) async throws {
        try await runCommand(
            "defaults",
            executable: Constants.menuBarItemSpacingExecutableURL,
            with: [
                "-currentHost", "write", "-globalDomain", key.rawValue, "-int",
                String(key.defaultValue + offset),
            ]
        )
    }

    /// The launchd label that owns the given app's executable, or nil
    /// when the app is not launched by a system LaunchAgent.
    private func launchdLabel(for app: NSRunningApplication) -> String? {
        guard let executableURL = app.executableURL else {
            return nil
        }
        return SystemLaunchAgentIndex.system.label(forExecutableAt: executableURL)
    }

    /// Restarts the launchd job with the given label in the calling user's
    /// GUI domain.
    ///
    /// `kickstart -k` keeps launchd as the parent, the only way to bring a
    /// launch-constrained agent back. Replaces terminate-then-launch.
    private func kickstartLaunchAgent(label: String) async throws {
        let target = "gui/\(getuid())/\(label)"
        try await runCommand(
            "launchctl",
            executable: Constants.launchctlExecutableURL,
            with: ["kickstart", "-k", target]
        )
        MenuBarItemSpacingManager.diagLog.debug("Kickstarted launchd job \(target)")
    }

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
        let deadline = ContinuousClock.now.advanced(by: .seconds(quitGracePeriod))

        while !app.isTerminated, ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }

        if !app.isTerminated {
            MenuBarItemSpacingManager.diagLog.notice(
                """
                Application "\(app.logString)" did not quit within \
                \(quitGracePeriod) seconds; leaving it running with the \
                previous spacing
                """
            )
            throw AppNotTerminatedError()
        }

        MenuBarItemSpacingManager.diagLog.debug(
            "Application \"\(app.logString)\" terminated successfully"
        )
    }

    private func launchApp(
        at applicationURL: URL,
        bundleIdentifier: String
    ) async throws {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            MenuBarItemSpacingManager.diagLog.debug(
                "Application \"\(app.logString)\" (\(bundleIdentifier)) is already open, so skipping launch"
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
        MenuBarItemSpacingManager.diagLog.debug(
            "Launched \(bundleIdentifier) via NSWorkspace.openApplication(at: \(applicationURL.path))"
        )
    }

    /// Resolved before the wave, while the process can still be inspected.
    private func relaunchStrategy(for app: NSRunningApplication) -> SpacingRelaunchStrategy {
        SpacingRelaunchPolicy.strategy(
            executableURL: app.executableURL,
            bundleURL: app.bundleURL,
            bundleIdentifier: app.bundleIdentifier,
            launchdLabel: launchdLabel(for: app)
        )
    }

    /// Restarts the app using its pre-resolved strategy. Launch-constrained
    /// agents go through launchd, since relaunching them ourselves is
    /// SIGKILLed and launchd won't respawn a successful exit.
    private func relaunchApp(
        _ app: NSRunningApplication,
        bundleID: String,
        strategy: SpacingRelaunchStrategy
    ) async throws {
        struct RelaunchError: Error {}

        switch strategy {
        case let .launchdKickstart(label):
            try await kickstartLaunchAgent(label: label)
        case let .terminateAndLaunch(bundleURL):
            try await signalAppToQuit(app)
            if app.isTerminated {
                try await launchApp(at: bundleURL, bundleIdentifier: bundleID)
            } else {
                throw RelaunchError()
            }
        case let .leaveRunning(reason):
            // Unreachable: filtered out before the wave.
            MenuBarItemSpacingManager.diagLog.debug(
                "Skipping \(bundleID) in the relaunch wave: \(reason.rawValue)"
            )
        }
    }

    private func writeDefaults(for offset: Int) async throws {
        try await setOffset(offset, forKey: .spacing)
        try await setOffset(offset, forKey: .padding)
    }

    /// Reads the value for the given key from the byHost global domain.
    /// Returns the key's default when no value is set.
    private func currentlyAppliedValue(forKey key: Key) -> Int {
        let value = CFPreferencesCopyValue(
            key.rawValue as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? Int
        return value ?? key.defaultValue
    }

    /// Whether applying `offset` would fire a relaunch wave. Mirrors the no-op
    /// guard in applyOffsetLocked so callers can prompt first.
    func willRelaunch(forOffset offset: Int) -> Bool {
        guard spacingApplyMode == .relaunchApps else {
            // writeOnly never fires a wave.
            return false
        }
        return !isOnDisk(offset: offset)
    }

    /// Whether the on-disk spacing and padding already match `offset`,
    /// regardless of the apply mode.
    func isOnDisk(offset: Int) -> Bool {
        currentlyAppliedValue(forKey: .spacing) == Key.spacing.defaultValue + offset
            && currentlyAppliedValue(forKey: .padding) == Key.padding.defaultValue + offset
    }

    /// Applies the current offset. `didRelaunch` in the outcome gates any
    /// settling period.
    @discardableResult
    func applyOffset() async throws -> ApplyOutcome {
        try await applyOffsetSemaphore.wait()
        do {
            let outcome = try await applyOffsetLocked()
            await applyOffsetSemaphore.signal()
            MenuBarItemSpacingManager.diagLog.debug(
                "applyOffset finished: didRelaunch=\(outcome.didRelaunch), recovered=\(outcome.recoveredBundleIDs.count), failed=\(outcome.failedAppNames.count)"
            )
            return outcome
        } catch {
            await applyOffsetSemaphore.signal()
            MenuBarItemSpacingManager.diagLog.debug("applyOffset failed: \(error)")
            throw error
        }
    }

    /// Runs under applyOffsetSemaphore. Split out so the caller awaits the
    /// signal on both paths; a defer + Task signal could starve under
    /// MainActor load and leak the semaphore.
    private func applyOffsetLocked() async throws -> ApplyOutcome {
        let targetSpacing = Key.spacing.defaultValue + offset
        let targetPadding = Key.padding.defaultValue + offset
        let onDiskSpacing = currentlyAppliedValue(forKey: .spacing)
        let onDiskPadding = currentlyAppliedValue(forKey: .padding)
        MenuBarItemSpacingManager.diagLog.debug(
            "applyOffset entered: offset=\(offset) target=\(targetSpacing)/\(targetPadding) onDisk=\(onDiskSpacing)/\(onDiskPadding)"
        )
        if onDiskSpacing == targetSpacing, onDiskPadding == targetPadding {
            MenuBarItemSpacingManager.diagLog.debug(
                "applyOffset no-op: on-disk already matches target; skipping relaunch"
            )
            return ApplyOutcome(didRelaunch: false, recoveredBundleIDs: [], failedAppNames: [])
        }

        // writeOnly: persist the preference and leave every app running.
        if spacingApplyMode == .writeOnly {
            try await writeDefaults(for: offset)
            MenuBarItemSpacingManager.diagLog.info(
                "applyOffset writeOnly: wrote spacing=\(targetSpacing)/padding=\(targetPadding); skipping relaunch wave"
            )
            return ApplyOutcome(didRelaunch: false, recoveredBundleIDs: [], failedAppNames: [])
        }

        try await writeDefaults(for: offset)

        try? await Task.sleep(for: .milliseconds(100))

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        let pids = Set(items.map { $0.sourcePID ?? $0.ownerPID })
        MenuBarItemSpacingManager.diagLog.debug(
            "applyOffset relaunching \(pids.count) unique PIDs from \(items.count) menu bar items"
        )

        // Snapshot before signalling so resolution doesn't race terminate.
        // Thaw is excluded, or its unchanged PID would read as "didn't come
        // back". Apps the policy won't restart never enter the map, which
        // keeps them out of the wave, verification, and fallback at once.
        let ownBundleID = NSRunningApplication.current.bundleIdentifier
        var preWaveAppHandles: [pid_t: AppHandle] = [:]
        var skippedByReason: [SpacingRelaunchSkipReason: [String]] = [:]
        for pid in pids {
            guard
                let app = NSRunningApplication(processIdentifier: pid),
                app != .current,
                let bid = app.bundleIdentifier,
                bid != ownBundleID
            else {
                continue
            }
            let strategy = relaunchStrategy(for: app)
            if case let .leaveRunning(reason) = strategy {
                skippedByReason[reason, default: []].append(bid)
                continue
            }
            preWaveAppHandles[pid] = AppHandle(
                bundleID: bid,
                bundleURL: app.bundleURL,
                strategy: strategy
            )
        }

        for (reason, bundleIDs) in skippedByReason {
            MenuBarItemSpacingManager.diagLog.notice(
                """
                applyOffset leaving \(bundleIDs.count) app(s) running \
                (\(reason.rawValue)): \(bundleIDs.sorted().joined(separator: ", "))
                """
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for (pid, handle) in preWaveAppHandles {
                guard
                    let app = NSRunningApplication(processIdentifier: pid),
                    app != .current
                else {
                    // Skip, don't break: one unresolvable PID mustn't abort
                    // the wave.
                    continue
                }
                group.addTask {
                    // Errors are ignored: the verification below decides
                    // whether an app came back, and it often still does.
                    try? await self.relaunchApp(
                        app,
                        bundleID: handle.bundleID,
                        strategy: handle.strategy
                    )
                }
            }
        }

        // Apps without a fresh process get a fallback launch from the
        // captured bundleURL.
        try? await Task.sleep(for: .seconds(2))
        let verification = await verifyAndFallbackRelaunch(
            preWaveAppHandles: preWaveAppHandles
        )

        let failedAppNames = verification.stillMissingBundleIDs.map { bid -> String in
            NSRunningApplication.runningApplications(
                withBundleIdentifier: bid
            ).first?.localizedName ?? bid
        }

        if !failedAppNames.isEmpty {
            // Don't roll back: relaunched apps already use the new spacing,
            // and a rollback would trigger another wave.
            MenuBarItemSpacingManager.diagLog.warning(
                "applyOffset: \(failedAppNames.count) app(s) failed to relaunch: \(failedAppNames.joined(separator: ", "))"
            )
        }

        // Apps that never quit never detach, so don't wait for them.
        let allBundleIDs = Set(preWaveAppHandles.values.map(\.bundleID))
        let recoveredBundleIDs = allBundleIDs
            .subtracting(verification.stillMissingBundleIDs)
            .subtracting(verification.stillRunningBundleIDs)
        return ApplyOutcome(
            didRelaunch: true,
            recoveredBundleIDs: recoveredBundleIDs,
            failedAppNames: failedAppNames
        )
    }

    /// Outcome of the post-wave check.
    private struct WaveVerification {
        /// Apps that are gone: nothing with their bundle ID is running,
        /// even after the fallback launch.
        let stillMissingBundleIDs: Set<String>

        /// Apps that declined to quit and keep the previous spacing.
        let stillRunningBundleIDs: Set<String>
    }

    /// Fallback-launches every snapshotted app that has no process with a
    /// new PID.
    private func verifyAndFallbackRelaunch(
        preWaveAppHandles: [pid_t: AppHandle]
    ) async -> WaveVerification {
        var missing: [AppHandle] = []
        var stillRunning = Set<String>()
        for (oldPID, handle) in preWaveAppHandles {
            let current = NSRunningApplication.runningApplications(
                withBundleIdentifier: handle.bundleID
            )
            if current.contains(where: { $0.processIdentifier != oldPID }) {
                continue
            }
            // The quit was refused (save sheet, modal). Leave it be.
            if current.contains(where: { $0.processIdentifier == oldPID }) {
                stillRunning.insert(handle.bundleID)
                continue
            }
            missing.append(handle)
        }

        if !stillRunning.isEmpty {
            MenuBarItemSpacingManager.diagLog.notice(
                """
                applyOffset verification: \(stillRunning.count) app(s) declined to quit \
                and keep the previous spacing: \(stillRunning.sorted().joined(separator: ", "))
                """
            )
        }

        guard !missing.isEmpty else {
            MenuBarItemSpacingManager.diagLog.debug(
                "applyOffset verification: all \(preWaveAppHandles.count - stillRunning.count) relaunched apps came back"
            )
            return WaveVerification(
                stillMissingBundleIDs: [],
                stillRunningBundleIDs: stillRunning
            )
        }

        let missingNames = missing.map(\.bundleID).joined(separator: ", ")
        MenuBarItemSpacingManager.diagLog.warning(
            "applyOffset verification: \(missing.count) app(s) missing post-wave: \(missingNames) — running fallback"
        )

        await withTaskGroup(of: Void.self) { group in
            for handle in missing {
                group.addTask {
                    // Same launch constraint as the wave: openApplication
                    // here would be SIGKILLed again.
                    if case let .launchdKickstart(label) = handle.strategy {
                        do {
                            try await self.kickstartLaunchAgent(label: label)
                        } catch {
                            MenuBarItemSpacingManager.diagLog.error(
                                "applyOffset fallback kickstart for \(handle.bundleID) (\(label)) failed: \(error)"
                            )
                        }
                        return
                    }
                    guard let url = handle.bundleURL else {
                        MenuBarItemSpacingManager.diagLog.warning(
                            "applyOffset fallback skipped for \(handle.bundleID): no bundleURL captured pre-wave"
                        )
                        return
                    }
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    configuration.addsToRecentItems = false
                    configuration.createsNewApplicationInstance = false
                    configuration.promptsUserIfNeeded = false
                    do {
                        try await NSWorkspace.shared.openApplication(
                            at: url,
                            configuration: configuration
                        )
                        MenuBarItemSpacingManager.diagLog.debug(
                            "applyOffset fallback launched \(handle.bundleID) via NSWorkspace.openApplication(at: \(url.path))"
                        )
                    } catch {
                        MenuBarItemSpacingManager.diagLog.error(
                            "applyOffset fallback NSWorkspace.openApplication(at: \(url.path)) for \(handle.bundleID) failed: \(error)"
                        )
                    }
                }
            }
        }

        // Poll every 100 ms until all targets run, capped at ~2 s.
        let missingBundleIDs = missing.map(\.bundleID)
        let pollDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < pollDeadline {
            let allBack = missingBundleIDs.allSatisfy { bundleID in
                !NSRunningApplication.runningApplications(
                    withBundleIdentifier: bundleID
                ).isEmpty
            }
            if allBack {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        var stillMissing = Set<String>()
        for bundleID in missingBundleIDs {
            let current = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleID
            )
            if current.isEmpty {
                stillMissing.insert(bundleID)
                MenuBarItemSpacingManager.diagLog.warning(
                    "applyOffset fallback verification: \(bundleID) still missing"
                )
            } else {
                MenuBarItemSpacingManager.diagLog.debug(
                    "applyOffset fallback verification: \(bundleID) recovered"
                )
            }
        }
        return WaveVerification(
            stillMissingBundleIDs: stillMissing,
            stillRunningBundleIDs: stillRunning
        )
    }
}

private extension NSRunningApplication {
    var logString: String {
        localizedName ?? bundleIdentifier ?? "<NIL>"
    }
}
