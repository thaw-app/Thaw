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
    }

    /// Result of a single applyOffset call.
    struct ApplyOutcome {
        /// Whether the on-disk values were rewritten and a relaunch wave
        /// was actually fired. False when the on-disk values already
        /// matched the requested offset (no-op case).
        let didRelaunch: Bool

        /// Bundle IDs we expect to see re-attach a menu bar item after
        /// the wave. Excludes apps that failed to relaunch (and Thaw
        /// itself, which is never killed). Empty when didRelaunch is
        /// false. Callers can pass this to a settling task to gate
        /// post-wave layout work on actual reattachment instead of a
        /// fixed timer.
        let recoveredBundleIDs: Set<String>

        /// Localized names of apps that failed to relaunch (kill timed
        /// out, or fallback launch could not bring them back). Empty on
        /// the happy path.
        let failedAppNames: [String]
    }

    /// Delay before force terminating an app.
    private let forceTerminateDelay = 5

    /// The offset to apply to the default spacing and padding.
    /// Does not take effect until ``applyOffset()`` is called.
    var offset = 0

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
        let targetSpacing = Key.spacing.defaultValue + offset
        let targetPadding = Key.padding.defaultValue + offset
        let onDiskSpacing = currentlyAppliedValue(forKey: .spacing)
        let onDiskPadding = currentlyAppliedValue(forKey: .padding)
        return onDiskSpacing != targetSpacing || onDiskPadding != targetPadding
    }

    /// Applies the current ``offset``.
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

        try await writeDefaults(for: offset)

        try? await Task.sleep(for: .milliseconds(100))

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        let pids = Set(items.map { $0.sourcePID ?? $0.ownerPID })
        MenuBarItemSpacingManager.diagLog.debug(
            "applyOffset relaunching \(pids.count) unique PIDs from \(items.count) menu bar items"
        )

        // Snapshot pre-wave PID -> (bundleID, bundleURL) so the post-wave
        // verification can tell whether each expected app actually came back
        // and the fallback can relaunch via the exact bundleURL that was
        // running. Stored before signalling so resolution doesn't race with
        // terminate. Thaw itself is excluded: it's never relaunched (we skip
        // .current during the wave), so its PID is unchanged post-wave,
        // which would otherwise be misread as "didn't come back" and
        // trigger a useless fallback launch of our own bundle.
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
                    // Errors from relaunchApp are intentionally swallowed.
                    // The post-wave verification + fallback below is the
                    // authoritative source of "did this app come back":
                    // a kill that times out is often still followed by a
                    // launchd respawn, and the bundleURL fallback can also
                    // recover apps whose relaunchApp threw. Tracking
                    // wave-time exceptions as failures double-counts those
                    // cases and stops the settling task from waiting for
                    // their menu bar items to reattach.
                    try? await self.relaunchApp(app)
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
            "applyOffset verification: \(missing.count) app(s) missing post-wave: \(missingNames) — running fallback"
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
            if allBack { break }
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
        return stillMissing
    }
}

private extension NSRunningApplication {
    /// A string to use for logging purposes.
    var logString: String {
        localizedName ?? bundleIdentifier ?? "<NIL>"
    }
}
