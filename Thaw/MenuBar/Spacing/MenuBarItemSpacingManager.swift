//
//  MenuBarItemSpacingManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Subprocess

// Prefer the System module when available: Subprocess's API surface uses
// System.FilePath, so both sides must resolve to the same module or the
// types won't unify.
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

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

    /// An error thrown when an app is still running after being asked to
    /// quit. The app is left alone; see signalAppToQuit(_:).
    private struct AppNotTerminatedError: Error {}

    /// Snapshot of an app captured before the relaunch wave fires. The
    /// fallback path uses the captured bundleURL to call
    /// NSWorkspace.openApplication(at:) directly, which targets the exact
    /// binary that was running. Resolving the bundle ID at fallback time
    /// (e.g. via open -gb) goes through Launch Services and can pick up a
    /// different copy when multiple builds are installed, or fail outright
    /// for XPC helpers, SMAppService login items, and LaunchAgents whose
    /// registered launch path is not a Launch Services target.
    private struct AppHandle {
        let bundleID: String
        let bundleURL: URL?

        /// How this app may be restarted, decided before the wave because
        /// it reads the running process's executable URL, which is gone by
        /// the time the fallback runs. Only apps the wave can bring back
        /// are captured, so this is never .leaveRunning. (#720, #1070)
        let strategy: SpacingRelaunchStrategy
    }

    /// Result of a single applyOffset call.
    struct ApplyOutcome {
        /// Whether the on-disk values were rewritten and a relaunch wave
        /// was actually fired. False when the on-disk values already
        /// matched the requested offset (no-op case).
        let didRelaunch: Bool

        /// Bundle IDs we expect to see re-attach a menu bar item after
        /// the wave. Excludes apps that failed to relaunch, apps the wave
        /// deliberately left running, and Thaw itself, which is never
        /// asked to quit. Empty when didRelaunch is false. Callers can
        /// pass this to a settling task to gate post-wave layout work on
        /// actual reattachment instead of a fixed timer.
        let recoveredBundleIDs: Set<String>

        /// Localized names of apps that failed to relaunch (quit timed
        /// out, or fallback launch could not bring them back). Empty on
        /// the happy path. Apps the wave deliberately left running are not
        /// failures and are not listed here.
        let failedAppNames: [String]
    }

    /// How long an app gets to quit on its own before the wave gives up on
    /// it. Nothing is force-terminated afterwards: an app that ignores the
    /// quit request is usually holding a save sheet or an in-flight
    /// operation, and killing it to reposition an icon costs the user more
    /// than the icon is worth. It keeps the old spacing instead. (#1070)
    private let quitGracePeriod = 5

    /// Small cap on captured standard error from the spacing subprocess,
    /// following the HookRunner output-limit pattern.
    private static let errorByteLimit = 16 * 1024

    /// The offset to apply to the default spacing and padding.
    /// Does not take effect until applyOffset() is called.
    var offset = 0

    /// When a spacing change becomes visible, and whether the relaunch
    /// wave is allowed to run at all. `relaunchApps` (the default) applies
    /// the change immediately by restarting the apps Thaw can bring back.
    /// `writeOnly` writes the on-disk preference and leaves every app
    /// running, so the new spacing appears the next time each status-item
    /// owner starts on its own. Synced from `DisplaySettingsManager`
    /// alongside `offset`; kept here so the spacing manager stays the one
    /// place that decides whether a wave fires. (#1075)
    var spacingApplyMode: SpacingApplyMode = .relaunchApps

    /// Serializes overlapping applyOffset calls. Without this, two
    /// concurrent callers (e.g. the screen-change sink and the
    /// profile-load layoutTask, which can both fire within the same
    /// frame on a display switch) race against each other: the second
    /// call's no-op guard sees on-disk already matches the target
    /// (because the first call wrote defaults) and returns false
    /// immediately, even though the first call is still mid-relaunch
    /// wave. With the semaphore the second caller queues behind the
    /// first; by the time it runs, the first call has completed and
    /// applyActiveDisplaySpacing has already started a settling
    /// period, so a subsequent applyProfileLayout correctly waits
    /// for items to stabilize before moving them.
    private let applyOffsetSemaphore = SimpleSemaphore(value: 1)

    /// Runs the executable at executableURL with the given arguments.
    private func runCommand(
        _ command: String,
        executable executableURL: URL,
        with arguments: [String]
    ) async throws {
        let result: ExecutionResult<Void, DiscardedOutput, StringOutput<UTF8>>
        do {
            // Executed by absolute path, with no argv[0] prepended.
            //
            // This used to run /usr/bin/env with "defaults" as its first
            // argument, so the tool that ended up writing to the global
            // domain was whatever defaults the inherited PATH resolved to.
            // command is now only used to describe the invocation in logs
            // and errors; every executable comes from Info.plist.
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
    /// kickstart -k kills the running instance and starts a fresh one
    /// with launchd as its parent, which is the whole point: it is the only
    /// way to bring a launch-constrained agent back, and it replaces the
    /// terminate-then-launch pair rather than supplementing it. (#720)
    private func kickstartLaunchAgent(label: String) async throws {
        let target = "gui/\(getuid())/\(label)"
        try await runCommand(
            "launchctl",
            executable: Constants.launchctlExecutableURL,
            with: ["kickstart", "-k", target]
        )
        MenuBarItemSpacingManager.diagLog.debug("Kickstarted launchd job \(target)")
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

    /// Asynchronously launches the app at the given URL.
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

    /// The strategy the wave should use for the given running app.
    ///
    /// Resolved once per app before the wave, so the decision is made while
    /// the process is still there to be inspected.
    private func relaunchStrategy(for app: NSRunningApplication) -> SpacingRelaunchStrategy {
        SpacingRelaunchPolicy.strategy(
            executableURL: app.executableURL,
            bundleURL: app.bundleURL,
            bundleIdentifier: app.bundleIdentifier,
            launchdLabel: launchdLabel(for: app)
        )
    }

    /// Asynchronously restarts the given app using its pre-resolved
    /// strategy.
    ///
    /// System LaunchAgents (Spotlight, TextInputMenuAgent, Dock,
    /// WindowManager, ...) can carry a launch constraint permitting launchd
    /// as their only launching parent. Terminating one and launching its
    /// bundle ourselves gets the new process SIGKILLed at exec -
    /// CODESIGNING, "Launch Constraint Violation" - and because terminate()
    /// is a successful exit, an agent with KeepAlive.SuccessfulExit=false
    /// (Spotlight's setting) is never respawned by launchd either, so the
    /// item stays gone until the machine is rebooted. Those go through
    /// launchd; a constrained binary with no label to kickstart is never
    /// touched at all. (#720, #1070)
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
            // Not reachable: applyOffsetLocked filters these out before the
            // wave. Kept exhaustive so a new strategy can't silently fall
            // into the terminate path.
            MenuBarItemSpacingManager.diagLog.debug(
                "Skipping \(bundleID) in the relaunch wave: \(reason.rawValue)"
            )
        }
    }

    /// Writes the current offset to the system defaults.
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

    /// Returns true when applying the given offset would rewrite the on-disk
    /// spacing or padding, and therefore fire a relaunch wave. Mirrors the
    /// no-op guard in applyOffsetLocked so callers can decide whether to
    /// prompt the user before a relaunch without performing the apply.
    func willRelaunch(forOffset offset: Int) -> Bool {
        guard spacingApplyMode == .relaunchApps else {
            // writeOnly never fires a wave: the preference is written and
            // the new spacing appears on the next owner start, so there is
            // nothing to prompt the user about and nothing to settle on.
            return false
        }
        let targetSpacing = Key.spacing.defaultValue + offset
        let targetPadding = Key.padding.defaultValue + offset
        let onDiskSpacing = currentlyAppliedValue(forKey: .spacing)
        let onDiskPadding = currentlyAppliedValue(forKey: .padding)
        return onDiskSpacing != targetSpacing || onDiskPadding != targetPadding
    }

    /// Applies the current offset.
    ///
    /// Returns true if a relaunch wave was actually fired, or false if
    /// the on-disk values already matched the requested offset and the
    /// call was a no-op. Callers that need to wait for items to re-attach
    /// after the wave (e.g. profile-layout application) can use the return
    /// value to gate a settling period.
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

    /// Body of applyOffset, run while holding applyOffsetSemaphore.
    /// Split out so the calling site can await the semaphore signal in
    /// both success and error paths: defer + Task wasn't reliable under
    /// MainActor load (the unstructured signal task could be deprioritized
    /// indefinitely, leaking the semaphore and stranding all subsequent
    /// callers in wait).
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

        // writeOnly: persist the preference but leave every app running. The
        // new spacing shows up the next time each status-item owner starts
        // on its own (after a restart, or when the app is reopened). No wave,
        // no settling period, nothing to recover from. (#1075)
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

        // Snapshot pre-wave PID -> (bundleID, bundleURL, strategy) so the
        // post-wave verification can tell whether each expected app actually
        // came back and the fallback can relaunch via the exact bundleURL
        // that was running. Stored before signalling so resolution doesn't
        // race with terminate. Thaw itself is excluded: it's never
        // relaunched (we skip .current during the wave), so its PID is
        // unchanged post-wave, which would otherwise be misread as "didn't
        // come back" and trigger a useless fallback launch of our own
        // bundle.
        //
        // Apps the policy declines to restart never enter the map, which is
        // what keeps them out of the wave, the verification, and the
        // fallback launch in one step. Before #1070 a launch-constrained
        // system binary that wasn't covered by an indexed LaunchAgent was
        // terminated anyway, then hit AMFI on the way back up - twice, once
        // in the wave and again in the fallback.
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
                    // Skip this PID, don't break: earlier break would abort
                    // the entire wave on any unresolvable PID, leaving most
                    // apps un-relaunched depending on Dictionary iteration
                    // order.
                    continue
                }
                group.addTask {
                    // Errors from relaunchApp are intentionally swallowed.
                    // The post-wave verification + fallback below is the
                    // authoritative source of "did this app come back":
                    // a quit that times out is often still followed by a
                    // launchd respawn, and the bundleURL fallback can also
                    // recover apps whose relaunchApp threw. Tracking
                    // wave-time exceptions as failures double-counts those
                    // cases and stops the settling task from waiting for
                    // their menu bar items to reattach.
                    try? await self.relaunchApp(
                        app,
                        bundleID: handle.bundleID,
                        strategy: handle.strategy
                    )
                }
            }
        }

        // Verification + fallback: any pre-wave bundle ID that does not
        // have a fresh process running is treated as un-relaunched and
        // gets a second chance via NSWorkspace.openApplication(at:) using
        // the bundleURL captured pre-wave. The captured URL points at the
        // exact binary that was running, which is the right primitive for
        // sandboxed apps, SMAppService login items, and LaunchAgents whose
        // bundle ID may resolve to a different copy (or to nothing) at
        // fallback time.
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
            // Don't roll back the on-disk defaults: the wave already ran,
            // the apps that DID relaunch have already started with the new
            // spacing, and rewriting the old value just causes the next
            // applyOffset to mismatch on-disk and trigger another wave.
            // Just log and surface the failures via the outcome.
            MenuBarItemSpacingManager.diagLog.warning(
                "applyOffset: \(failedAppNames.count) app(s) failed to relaunch: \(failedAppNames.joined(separator: ", "))"
            )
        }

        // Apps that never quit are subtracted too: their status items never
        // detached, so a settling period that waits for them to reattach
        // would wait for something that isn't going to happen.
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

        /// Apps that are still up on their pre-wave PID because they
        /// declined the quit request. Nothing to recover - they simply
        /// keep the previous spacing.
        let stillRunningBundleIDs: Set<String>
    }

    /// For every pre-wave (pid, bundleID, bundleURL) snapshot, checks
    /// whether a process with that bundle ID is currently running with a
    /// PID different from the pre-wave one. Apps that have not been
    /// replaced run through a fallback launch via
    /// NSWorkspace.openApplication(at:) using the captured bundleURL.
    private func verifyAndFallbackRelaunch(
        preWaveAppHandles: [pid_t: AppHandle]
    ) async -> WaveVerification {
        var missing: [AppHandle] = []
        var stillRunning = Set<String>()
        for (oldPID, handle) in preWaveAppHandles {
            let current = NSRunningApplication.runningApplications(
                withBundleIdentifier: handle.bundleID
            )
            // Came back if any current instance is a fresh PID.
            if current.contains(where: { $0.processIdentifier != oldPID }) {
                continue
            }
            // The original process is still alive, so the quit request was
            // refused (a save sheet, a modal, a busy app). Relaunching it
            // would mean forcing it down first, which is the destructive
            // behaviour this path exists to avoid; leave it be. (#1070)
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

        // Fire all relaunches in parallel via TaskGroup. The
        // openApplication call returns once the launch completes; in
        // parallel the wall time is dominated by the slowest target.
        await withTaskGroup(of: Void.self) { group in
            for handle in missing {
                group.addTask {
                    // Same launch constraint as the wave itself: retrying
                    // openApplication here is what produced the second
                    // Spotlight crash report, ~8 s after the first. (#720)
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

        // Poll for recovery instead of a fixed 2-second sleep. Exit early
        // as soon as every fallback target has produced a running process,
        // capped at ~2 s so a genuinely-failed launch doesn't strand the
        // caller. 100 ms cadence is responsive without burning CPU.
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
    /// A string to use for logging purposes.
    var logString: String {
        localizedName ?? bundleIdentifier ?? "<NIL>"
    }
}
