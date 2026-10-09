//
//  main.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import MenuBarModel
import os.lock
import ThawCapture
import XPC

/// The MenuBarCaptureService XPC helper.
///
/// Hosts the ScreenCaptureKit capture core so SkyLight's per-call dictionary
/// leak accrues here instead of in the UI process. The leak is bounded by
/// lifetime: the helper exits(0) after 1,800 successful captures or when the
/// last client session closes, and a watchdog exits with status 1 when one
/// capture outlives its budget so a wedged call cannot pin the listener
/// queue. XPC relaunches the service on the next call.
///
/// The typed XPCListener handler is synchronous, so the async capture is
/// bridged with a semaphore. Requests serialize on the listener queue, which
/// matches the client's drop-not-queue policy.
private enum MenuBarCaptureServiceMain {
    static let diagLog = DiagLog(category: "MenuBarCaptureService")

    /// Successful captures before the helper retires itself. At 30 fps
    /// this is a one-minute cap; at 1 fps, half an hour.
    static let captureBudget = 1800
    static let maxWindowCount = 64

    /// Delay between returning a reply and a scheduled exit(0), giving
    /// libxpc time to flush the reply message.
    static let exitFlushDelay: TimeInterval = 0.25

    /// How long the helper stays up after its last session closes. The app
    /// reopens a session within a few hundred milliseconds when one surface
    /// closes and another opens, so exiting at once left the new request
    /// waiting out the full reply timeout on a dying process.
    ///
    /// Long enough to outlast the app's once-a-minute refresh as well. At three
    /// seconds the helper was started 23 times in half an hour, and each cold
    /// start kept a capture waiting for five to seven seconds.
    static let idleExitGrace: TimeInterval = 90

    /// How long a single capture may run before the helper treats
    /// ScreenCaptureKit as wedged and dies so XPC relaunches a healthy one.
    /// Must stay below the client's reply timeout
    /// (MenuBarCaptureServiceClient.replyTimeout, 12 s) so the exit fails the
    /// parked send inside its one-retry budget.
    static let captureWatchdogInterval: TimeInterval = 8

    static let lifecycle = LifecycleState()

    /// Keeps the listener alive for the life of the process.
    static nonisolated(unsafe) var listener: XPCListener?

    // MARK: Lifecycle

    /// Counters that decide when the helper retires. Lock-based because
    /// XPC handlers arrive on dispatch queues, not actors.
    final class LifecycleState: Sendable {
        private struct State {
            var successfulCaptures = 0
            var activeSessions = 0
            var inFlightRequests = 0
            var exitWhenIdle = false
            var exitScheduled = false
            /// IDs of the running captures. Each session has its own queue, so
            /// a session the client dropped can still be capturing when the
            /// next one starts; a watchdog checks for its own ID rather than
            /// for "the" capture.
            var inFlightCaptureIDs: Set<Int> = []
            var captureCounter = 0
            /// Bumped whenever a session opens, so a delayed idle exit can
            /// tell that it has been superseded.
            var idleGeneration = 0
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        var captureCount: Int {
            state.withLock(\.successfulCaptures)
        }

        func sessionOpened() {
            let count = state.withLock { state in
                state.activeSessions += 1
                state.idleGeneration += 1
                state.exitWhenIdle = false
                return state.activeSessions
            }
            diagLog.debug("Session opened (\(count) active)")
        }

        /// The current idle generation; an exit armed under an older one is stale.
        var idleGeneration: Int {
            state.withLock(\.idleGeneration)
        }

        /// Whether the idle exit armed under generation may still fire.
        func isIdle(since generation: Int) -> Bool {
            state.withLock {
                $0.idleGeneration == generation && $0.activeSessions == 0 && $0.inFlightRequests == 0
            }
        }

        /// Returns whether the helper should exit now that this session
        /// is gone. When a request is still in flight the exit is
        /// deferred to requestFinished() instead.
        func sessionClosed() -> Bool {
            state.withLock { state in
                state.activeSessions = max(0, state.activeSessions - 1)
                guard state.activeSessions == 0 else {
                    return false
                }
                guard state.inFlightRequests == 0 else {
                    state.exitWhenIdle = true
                    return false
                }
                return true
            }
        }

        /// Marks a capture in flight and returns its watchdog ID.
        func requestStarted() -> Int {
            state.withLock { state in
                state.inFlightRequests += 1
                state.captureCounter += 1
                state.inFlightCaptureIDs.insert(state.captureCounter)
                return state.captureCounter
            }
        }

        /// Returns whether a deferred last-session exit should run now.
        func requestFinished(_ captureID: Int) -> Bool {
            state.withLock { state in
                state.inFlightCaptureIDs.remove(captureID)
                state.inFlightRequests = max(0, state.inFlightRequests - 1)
                return state.exitWhenIdle && state.inFlightRequests == 0
            }
        }

        /// Whether the capture armed under id is still running.
        func isCaptureInFlight(_ id: Int) -> Bool {
            state.withLock { $0.inFlightCaptureIDs.contains(id) }
        }

        /// Counts one successful capture, returning the new generation.
        func recordSuccess() -> Int {
            state.withLock { state in
                state.successfulCaptures += 1
                return state.successfulCaptures
            }
        }

        /// One-shot gate so the exit path runs exactly once.
        func claimExit() -> Bool {
            state.withLock { state in
                guard !state.exitScheduled else {
                    return false
                }
                state.exitScheduled = true
                return true
            }
        }
    }

    /// Retires the process once it has been idle for idleExitGrace; a
    /// session that opens in the meantime cancels it.
    static func scheduleIdleExit(reason: String) {
        let generation = lifecycle.idleGeneration
        DispatchQueue.global().asyncAfter(deadline: .now() + idleExitGrace) {
            guard lifecycle.isIdle(since: generation) else { return }
            scheduleExit(reason: reason)
        }
    }

    /// Retires the process after letting any just-returned reply flush.
    static func scheduleExit(reason: String) {
        guard lifecycle.claimExit() else {
            return
        }
        diagLog.notice("MenuBarCaptureService exiting: \(reason)")
        DispatchQueue.global().asyncAfter(deadline: .now() + exitFlushDelay) {
            exit(0)
        }
    }

    /// Arms a one-shot check: if the capture assigned captureID is still in
    /// flight after captureWatchdogInterval, exit(1). Runs off the listener
    /// queue because the semaphore bridge blocks that queue for the whole
    /// capture. Dying is safe recovery: the helper holds no state, XPC
    /// relaunches it, and the client's parked send fails and retries there.
    static func armCaptureWatchdog(for captureID: Int) {
        let interval = captureWatchdogInterval
        DispatchQueue.global().asyncAfter(deadline: .now() + interval) {
            guard lifecycle.isCaptureInFlight(captureID) else {
                return
            }
            diagLog.error(
                "Capture \(captureID) still in flight after \(Int(interval))s — wedged; exiting so XPC relaunches a healthy helper"
            )
            exit(1)
        }
    }

    // MARK: Window ID Validation

    /// The window set a caller may name in a windows request: the
    /// menu-bar-layer windows plus the wallpaper windows and
    /// MenuBarAgent's hosting surfaces, re-derived here so a
    /// compromised caller cannot turn the helper into a general screen
    /// scraper.
    static func allowedWindowIDs() -> Set<CGWindowID> {
        var allowed = Set(Bridging.getMenuBarWindowList())
        // Window descriptions come back nil inside this service, so the host
        // is found through its owner's connection and the wallpaper by level.
        if let hostPID = NSRunningApplication.runningApplications(
            withBundleIdentifier: SharedConstants.menuBarHostingBundleID
        ).first?.processIdentifier {
            allowed.formUnion(Bridging.getMenuBarWindowIDs(forProcess: hostPID, skipWidthFilter: true))
        }
        let desktopLevel = CGWindowLevelForKey(.desktopWindow)
        // The level scan reads the full list: the on-screen one misses the
        // system windows that sit below the desktop level and are sampled.
        for windowID in Bridging.getWindowList(option: []) {
            if let level = Bridging.getWindowLevel(for: windowID), level <= desktopLevel {
                allowed.insert(windowID)
            }
        }
        // The hosting window is off-screen, so read the full list.
        for window in WindowInfo.createWindows(option: []) {
            if window.owningApplication?.bundleIdentifier == SharedConstants.menuBarHostingBundleID {
                allowed.insert(window.windowID)
            }
        }
        // The wallpaper is a desktop element that only an on-screen list holds.
        for window in WindowInfo.createWindows(option: .onScreen) where window.isWallpaperWindow {
            allowed.insert(window.windowID)
        }
        return allowed
    }

    // MARK: Capture

    static func failureReply(_ failure: CaptureServiceReply.Failure) -> CaptureServiceReply {
        CaptureServiceReply(frame: nil, generation: lifecycle.captureCount, failure: failure)
    }

    /// A capture that produced no image: permission denial when TCC says
    /// so (the runtime answer to the helper-attribution question), plain
    /// failure otherwise.
    static func captureFailureReply() -> CaptureServiceReply {
        guard CGPreflightScreenCaptureAccess() else {
            diagLog.error("Capture failed and CGPreflightScreenCaptureAccess() is false — TCC attributes the helper separately")
            return failureReply(.permissionDenied)
        }
        return failureReply(.captureFailed)
    }

    static func successReply(image: CGImage, windowFrame: CGRect, scale: Double) -> CaptureServiceReply {
        guard let frame = CaptureServiceFrame(image: image, windowFrame: windowFrame, scale: scale) else {
            diagLog.error("Failed to serialize a captured frame (\(image.width)×\(image.height)px)")
            return failureReply(.captureFailed)
        }
        return CaptureServiceReply(frame: frame, generation: lifecycle.recordSuccess(), failure: nil)
    }

    static func makeReply(for request: CaptureServiceRequest) async -> CaptureServiceReply {
        switch request {
        case let .windows(ids, screenBounds, imageOptionRawValue, _):
            // The scale field is advisory in v1; the SCK path derives the
            // capture scale from the filter (or 1x for .nominalResolution).
            //
            // One foreign ID must not void the capture for the rest: drop
            // what is not allowed and refuse only an empty result.
            let allowed = allowedWindowIDs()
            // Drop zeros and duplicates and cap the request, as the macOS 26
            // service does, then filter by the allowlist.
            var seenIDs = Set<CGWindowID>()
            seenIDs.reserveCapacity(ids.count)
            let accepted = ids.filter { id in
                guard id != 0, !seenIDs.contains(id), allowed.contains(id),
                      seenIDs.count < Self.maxWindowCount
                else { return false }
                seenIDs.insert(id)
                return true
            }
            guard !accepted.isEmpty else {
                diagLog.warning("Rejecting windows request; no requested ID is in the menu-bar/wallpaper set: \(ids)")
                return failureReply(.rejectedWindowID)
            }
            if accepted.count < ids.count {
                let dropped = ids.filter { !allowed.contains($0) }
                diagLog.info("Dropping \(dropped.count) window ID(s) outside the menu-bar/wallpaper set and capturing the rest: \(dropped)")
            }
            // Union of the requested windows' frames, for the reply's crop
            // geometry, read from the window server before the capture since
            // descriptions are unavailable here.
            let unionBounds = accepted
                .compactMap { Bridging.getWindowBounds(for: $0) }
                .reduce(CGRect.null) { $0.union($1) }
            guard let image = await ScreenCapture.captureWindows(
                with: accepted,
                screenBounds: screenBounds,
                option: CGWindowImageOption(rawValue: imageOptionRawValue)
            ) else {
                return captureFailureReply()
            }
            let effectiveBounds: CGRect = if let screenBounds, !screenBounds.isNull {
                screenBounds
            } else {
                unionBounds
            }
            guard effectiveBounds.width > 0 else {
                return failureReply(.captureFailed)
            }
            return successReply(
                image: image,
                windowFrame: effectiveBounds,
                scale: Double(image.width) / effectiveBounds.width
            )
        case let .menuBarHostingWindow(displayID):
            guard let capture = await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID) else {
                return captureFailureReply()
            }
            return successReply(image: capture.image, windowFrame: capture.windowFrame, scale: capture.scale)
        case let .menuBarDisplayStrip(displayID):
            guard let capture = await ScreenCapture.captureMenuBarDisplayStripAsync(displayID: displayID) else {
                return captureFailureReply()
            }
            return successReply(image: capture.image, windowFrame: capture.windowFrame, scale: capture.scale)
        case let .ownerBarWindow(windowID):
            // The window is re-read from the window server and has to be a
            // menu bar strip, so a caller cannot name an arbitrary window.
            guard let capture = ScreenCapture.captureOwnerBarWindowForService(windowID: windowID) else {
                return failureReply(.rejectedWindowID)
            }
            return successReply(image: capture.image, windowFrame: capture.windowFrame, scale: capture.scale)
        }
    }

    /// Bridges the async capture into the synchronous typed message
    /// handler. Blocking the listener queue serializes captures, which
    /// matches the client's drop-not-queue policy.
    static func handle(_ request: CaptureServiceRequest) -> CaptureServiceReply {
        let captureID = lifecycle.requestStarted()
        armCaptureWatchdog(for: captureID)
        let box = OSAllocatedUnfairLock<CaptureServiceReply?>(initialState: nil)
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            let reply = await makeReply(for: request)
            box.withLock { $0 = reply }
            semaphore.signal()
        }
        semaphore.wait()
        let reply = box.withLock { $0 } ?? failureReply(.captureFailed)

        if lifecycle.requestFinished(captureID) {
            scheduleIdleExit(reason: "last session closed")
        }
        if reply.failure == nil, reply.generation >= captureBudget {
            scheduleExit(reason: "capture budget (\(captureBudget)) reached")
        }
        return reply
    }

    // MARK: Entry Point

    /// Mirrors the app's diagnostic flag into this process. Without it,
    /// helper-side failures (a wedged capture, a refused window, a slow
    /// start) reach the log only as the client's cancelled request. The
    /// helper's bundle identifier is the app's plus a service component,
    /// which is how the app's defaults domain is found.
    static func enableDiagnosticLoggingIfRequested() {
        guard
            let helperIdentifier = Bundle.main.bundleIdentifier,
            let serviceComponent = helperIdentifier.range(
                of: ".MenuBarCaptureService",
                options: .backwards
            )
        else { return }
        let appIdentifier = String(helperIdentifier[helperIdentifier.startIndex ..< serviceComponent.lowerBound])
        guard UserDefaults(suiteName: appIdentifier)?.bool(forKey: "EnableDiagnosticLogging") == true else {
            return
        }

        // XPC relaunches this helper every few seconds, so it appends to the app's
        // session log instead of minting its own, but never reopens a stale one.
        if let sessionLog = DiagnosticLogger.shared.latestLogFile,
           let modified = try? sessionLog.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) < Self.sessionLogAttachWindow
        {
            DiagnosticLogger.shared.attachToFile(at: sessionLog)
        } else {
            DiagnosticLogger.shared.isEnabled = true
        }
    }

    /// How recently the app must have written a log for this process to append to it instead of starting its own.
    static let sessionLogAttachWindow: TimeInterval = 600

    static func run() -> Never {
        enableDiagnosticLoggingIfRequested()
        ScreenCapture.desktopIndependentWindowCaptureEnabled = false
        let serviceName = Bundle.main.bundleIdentifier ?? CaptureService.baseServiceBundleIdentifier
        do {
            listener = try XPCListener(service: serviceName) { request in
                lifecycle.sessionOpened()
                return request.accept { (message: CaptureServiceRequest) -> (any Encodable)? in
                    handle(message)
                } cancellationHandler: { _ in
                    if lifecycle.sessionClosed() {
                        scheduleIdleExit(reason: "last session closed")
                    }
                }
            }
        } catch {
            diagLog.error("Failed to create XPCListener for \(serviceName): \(error)")
            exit(1)
        }
        diagLog.notice("MenuBarCaptureService listening as \(serviceName)")
        dispatchMain()
    }
}

MenuBarCaptureServiceMain.run()
