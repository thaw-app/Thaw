//
//  MenuBarItemSpacingManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import Subprocess
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

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

    /// An error thrown when an app fails to terminate after force-quitting.
    private struct AppNotTerminatedError: Error {}

    /// Snapshot of an app captured before the relaunch wave fires. The
    /// fallback uses the captured bundleURL to call NSWorkspace.openApplication
    /// directly, targeting the exact binary that was running; resolving the
    /// bundle ID at fallback time goes through Launch Services and can pick a
    /// different copy or fail for XPC helpers and login items.
    private struct AppHandle {
        let bundleID: String
        let bundleURL: URL?
    }

    /// Result of a single applyOffset call.
    struct ApplyOutcome {
        /// Whether the on-disk values were rewritten and a relaunch wave
        /// was actually fired. False when the on-disk values already
        /// matched the requested offset (no-op case).
        let didRelaunch: Bool

        /// Bundle IDs expected to re-attach a menu bar item after the wave, so
        /// callers can gate layout work on real reattachment rather than a
        /// fixed timer. Excludes failed apps and Thaw; empty when didRelaunch
        /// is false.
        let recoveredBundleIDs: Set<String>

        /// Localized names of apps that failed to relaunch (kill timed
        /// out, or fallback launch could not bring them back). Empty on
        /// the happy path.
        let failedAppNames: [String]
    }

    /// Delay before force terminating an app.
    private let forceTerminateDelay = 5

    /// The offset to apply to the default spacing and padding.
    /// Does not take effect until applyOffset() is called.
    var offset = 0

    /// Whether a relaunch wave may run. Synced from DisplaySettingsManager and
    /// enforced here so no caller of applyOffset can bypass it.
    var spacingApplyMode: SpacingApplyMode = .relaunchApps

    /// Serializes overlapping applyOffset calls. The screen-change sink and
    /// the profile-load layoutTask can fire in the same frame on a display
    /// switch; queued, the second runs after the settling period has started,
    /// so a later applyProfileLayout waits for items to stabilize.
    private let applyOffsetSemaphore = SimpleSemaphore(value: 1)

    /// Runs a command with the given arguments.
    private func runCommand(_ command: String, with arguments: [String]) async throws {
        let terminationStatus: TerminationStatus
        do {
            terminationStatus = try await Subprocess.run(
                .path(FilePath(Constants.menuBarItemSpacingExecutableURL.path)),
                arguments: Arguments([command] + arguments),
                output: .discarded,
                error: .discarded
            ).terminationStatus
        } catch {
            throw MenuBarItemSpacingError(
                kind: .processRun(error),
                command: command,
                arguments: arguments
            )
        }

        guard terminationStatus.isSuccess else {
            let exitStatus: Int32 = switch terminationStatus {
            case let .exited(code): code
            case let .signaled(code): code
            }
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
            with: [
                "-currentHost", "write", "-globalDomain", key.rawValue, "-int",
                String(key.defaultValue + offset),
            ]
        )
    }

    /// Sleeps for the given duration without observing the caller's
    /// cancellation.
    ///
    /// A relaunch wave that has already told apps to quit must run to
    /// completion, because aborting it leaves those apps terminated and
    /// never relaunched. An unstructured task does not inherit the
    /// caller's cancellation, so the wait runs in full even when the
    /// surrounding task is cancelled; that also keeps a poll loop from
    /// spinning on the main actor when a cancelled sleep returns
    /// immediately.
    private func sleepIgnoringCancellation(for duration: Duration) async {
        await Task {
            do {
                try await Task.sleep(for: duration)
            } catch {
                // The wave must finish, so cancellation is ignored here.
            }
        }.value
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
            await sleepIgnoringCancellation(for: pollInterval)
        }

        if !app.isTerminated {
            MenuBarItemSpacingManager.diagLog.debug(
                """
                Application "\(app.logString)" did not terminate within \
                \(forceTerminateDelay) seconds, attempting to force terminate
                """
            )
            app.forceTerminate()
            await sleepIgnoringCancellation(for: .seconds(1))

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
        // Write-only mode never fires a wave, whatever is on disk.
        guard spacingApplyMode == .relaunchApps else {
            return false
        }
        return !isOnDisk(offset: offset)
    }

    /// Whether the on-disk spacing and padding already match the offset,
    /// regardless of the apply mode.
    func isOnDisk(offset: Int) -> Bool {
        currentlyAppliedValue(forKey: .spacing) == Key.spacing.defaultValue + offset
            && currentlyAppliedValue(forKey: .padding) == Key.padding.defaultValue + offset
    }

    /// Applies the current offset.
    ///
    /// Returns an outcome whose didRelaunch is false when the on-disk values
    /// already matched the requested offset. Callers that must wait for items
    /// to re-attach can gate a settling period on the result.
    ///
    /// With relaunchApps false the value is only written: running apps keep
    /// their current spacing and pick the new one up the next time they launch.
    @discardableResult
    func applyOffset(forceRelaunch: Bool = false, relaunchApps: Bool = true) async throws -> ApplyOutcome {
        let requestedOffset = offset
        try await applyOffsetSemaphore.wait()
        do {
            // Read under the semaphore so a queued apply honors a mode changed while it waited.
            let mayRelaunch = Self.mayRelaunchApps(mode: spacingApplyMode, requested: relaunchApps)
            let outcome = try await applyOffsetLocked(
                offset: requestedOffset,
                forceRelaunch: forceRelaunch && mayRelaunch,
                relaunchApps: mayRelaunch
            )
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

    static func shouldSkipRelaunch(valuesMatch: Bool, forceRelaunch: Bool) -> Bool {
        valuesMatch && !forceRelaunch
    }

    /// Runs under the semaphore; the caller awaits its release on success and failure.
    private func applyOffsetLocked(offset: Int, forceRelaunch: Bool, relaunchApps: Bool) async throws -> ApplyOutcome {
        let targetSpacing = Key.spacing.defaultValue + offset
        let targetPadding = Key.padding.defaultValue + offset
        let onDiskSpacing = currentlyAppliedValue(forKey: .spacing)
        let onDiskPadding = currentlyAppliedValue(forKey: .padding)
        MenuBarItemSpacingManager.diagLog.debug(
            "applyOffset entered: offset=\(offset) target=\(targetSpacing)/\(targetPadding) onDisk=\(onDiskSpacing)/\(onDiskPadding) forceRelaunch=\(forceRelaunch)"
        )
        if Self.shouldSkipRelaunch(
            valuesMatch: onDiskSpacing == targetSpacing && onDiskPadding == targetPadding,
            forceRelaunch: forceRelaunch
        ) {
            MenuBarItemSpacingManager.diagLog.debug(
                "applyOffset no-op: on-disk already matches target; skipping relaunch"
            )
            return ApplyOutcome(didRelaunch: false, recoveredBundleIDs: [], failedAppNames: [])
        }

        try await writeDefaults(for: offset)

        guard relaunchApps else {
            MenuBarItemSpacingManager.diagLog.debug(
                "applyOffset wrote \(targetSpacing)/\(targetPadding) without relaunching; running apps keep their spacing"
            )
            return ApplyOutcome(didRelaunch: false, recoveredBundleIDs: [], failedAppNames: [])
        }

        await sleepIgnoringCancellation(for: .milliseconds(100))

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        let pids = Set(items.map { $0.sourcePID ?? $0.ownerPID })
        MenuBarItemSpacingManager.diagLog.debug(
            "applyOffset relaunching \(pids.count) unique PIDs from \(items.count) menu bar items"
        )

        // Snapshot pre-wave PID -> (bundleID, bundleURL) so post-wave
        // verification can tell whether each expected app came back and the
        // fallback can relaunch the exact bundleURL that was running. Stored
        // before signalling so resolution doesn't race with terminate. Thaw is
        // excluded: its unchanged PID would read as "didn't come back".
        let ownBundleID = NSRunningApplication.current.bundleIdentifier
        var preWaveAppHandles: [pid_t: AppHandle] = [:]
        for pid in pids {
            if let app = NSRunningApplication(processIdentifier: pid),
               app != .current,
               let bid = app.bundleIdentifier,
               bid != ownBundleID
            {
                preWaveAppHandles[pid] = AppHandle(bundleID: bid, bundleURL: app.bundleURL)
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for pid in pids {
                guard
                    let app = NSRunningApplication(processIdentifier: pid),
                    app != .current
                else {
                    // Skip this PID, don't break: earlier break would abort
                    // the entire wave on any unresolvable PID, leaving most
                    // apps un-relaunched depending on Set iteration order.
                    continue
                }
                group.addTask {
                    // Errors from relaunchApp are intentionally swallowed. The
                    // post-wave verification and fallback below decide whether
                    // an app came back: a timed-out kill is often still
                    // followed by a launchd respawn, and counting it as a
                    // failure would stop the settling task from waiting for
                    // its menu bar items to reattach.
                    try? await self.relaunchApp(app)
                }
            }
        }

        // Any pre-wave bundle ID without a fresh process gets a second chance
        // via NSWorkspace.openApplication(at:) with the captured bundleURL,
        // which points at the exact binary that was running (see AppHandle).
        await sleepIgnoringCancellation(for: .seconds(2))
        let stillMissingBundleIDs = await verifyAndFallbackRelaunch(
            preWaveAppHandles: preWaveAppHandles
        )

        let failedAppNames = stillMissingBundleIDs.map { bid -> String in
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

        let allBundleIDs = Set(preWaveAppHandles.values.map(\.bundleID))
        let recoveredBundleIDs = allBundleIDs.subtracting(stillMissingBundleIDs)
        return ApplyOutcome(
            didRelaunch: true,
            recoveredBundleIDs: recoveredBundleIDs,
            failedAppNames: failedAppNames
        )
    }

    /// For every pre-wave (pid, bundleID, bundleURL) snapshot, checks
    /// whether a process with that bundle ID is currently running with a
    /// PID different from the pre-wave one. Apps that have not been
    /// replaced run through a fallback launch via
    /// NSWorkspace.openApplication(at:) using the captured bundleURL.
    /// Returns the bundle IDs of apps that are still missing after the
    /// fallback.
    private func verifyAndFallbackRelaunch(
        preWaveAppHandles: [pid_t: AppHandle]
    ) async -> Set<String> {
        let missing: [AppHandle] = preWaveAppHandles.compactMap { oldPID, handle in
            let current = NSRunningApplication.runningApplications(
                withBundleIdentifier: handle.bundleID
            )
            // Came back if any current instance is a fresh PID.
            let isBack = current.contains { $0.processIdentifier != oldPID }
            return isBack ? nil : handle
        }
        guard !missing.isEmpty else {
            MenuBarItemSpacingManager.diagLog.debug(
                "applyOffset verification: all \(preWaveAppHandles.count) apps came back"
            )
            return []
        }

        let missingNames = missing.map(\.bundleID).joined(separator: ", ")
        MenuBarItemSpacingManager.diagLog.warning(
            "applyOffset verification: \(missing.count) app(s) missing post-wave: \(missingNames), running fallback"
        )

        // Fire all relaunches in parallel via TaskGroup. The
        // openApplication call returns once the launch completes; in
        // parallel the wall time is dominated by the slowest target.
        await withTaskGroup(of: Void.self) { group in
            for handle in missing {
                group.addTask {
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

        // Poll for recovery instead of a fixed sleep: exit as soon as every
        // fallback target is running, capped at ~2 s so a failed launch does
        // not strand the caller.
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
            await sleepIgnoringCancellation(for: .milliseconds(100))
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
        return stillMissing
    }
}

extension MenuBarItemSpacingManager {
    /// Whether an apply may relaunch apps. Write-only mode outranks every
    /// caller's request, a forced reapply included.
    static func mayRelaunchApps(mode: SpacingApplyMode, requested: Bool) -> Bool {
        mode == .relaunchApps && requested
    }
}

private extension NSRunningApplication {
    var logString: String {
        localizedName ?? bundleIdentifier ?? "<NIL>"
    }
}
