//
//  MenuBarCaptureServiceClient.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import XPC

/// The app-side client of the MenuBarCaptureService XPC helper.
///
/// Session lifecycle mirrors the helper's own exit rule: the session opens
/// lazily on the first capture, stays open while any live-refresh
/// consumer is registered, and closes when the last consumer stops (or,
/// for one-shot captures with no registered consumer, as soon as the
/// capture finishes). The helper exits itself after 1,800 successful
/// captures; XPC relaunches it on demand, so the only supervision here
/// is dropping a cancelled session and reopening on the next call.
///
/// Missed-frame policy is intentionally absent: the live refresh loop
/// already drops ticks while a capture is in flight instead of queuing.
public actor MenuBarCaptureServiceClient {
    private static let diagLog = DiagLog(category: "MenuBarCaptureServiceClient")

    /// The shared client, connecting to the helper embedded in the main
    /// bundle.
    public static let shared = MenuBarCaptureServiceClient()

    /// The XPC service name to connect to.
    private let serviceName: String

    /// The one live session, while anything needs it.
    private var session: XPCSession?

    /// Identifies session. A session's cancellation handler runs after an
    /// actor hop, by which time a newer session may have replaced it; the
    /// handler only drops the session it was created for.
    private var sessionToken: UUID?

    /// Live-refresh consumers currently registered via
    /// beginLiveConsumer().
    private var liveConsumerCount = 0

    /// Captures currently awaiting a reply.
    private var inFlightCaptureCount = 0

    /// The helper's successful-capture count from the latest reply.
    /// Diagnostics only; a drop means the helper restarted.
    private var lastGeneration = 0

    /// Longest one XPC round trip may take before this client treats the
    /// session as wedged and tears it down for a retry. Longer than the
    /// helper's capture watchdog (8 s) on purpose: the normal un-wedge path is
    /// the helper exiting, which fails the parked send inside this budget.
    /// This deadline is the backstop for wedges the watchdog cannot see (a
    /// message lost before the handler ran).
    private static let replyTimeout: Duration = .seconds(12)

    /// Frames and pixel bytes received since launch; see recordTransferred(_:).
    private var framesReceived = 0
    private var bytesReceived = 0

    public init(serviceName: String? = nil) {
        self.serviceName = serviceName ?? CaptureService.serviceName(
            forAppBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    // MARK: Consumer Lifecycle

    /// Registers a live-refresh consumer. The session stays open until
    /// the matching endLiveConsumer().
    public func beginLiveConsumer() {
        liveConsumerCount += 1
    }

    /// Deregisters a live-refresh consumer, closing the session when it
    /// was the last one and no capture is in flight. The helper sees the
    /// session close and exits; the next capture relaunches it.
    public func endLiveConsumer() {
        liveConsumerCount = max(0, liveConsumerCount - 1)
        closeSessionIfIdle()
    }

    func closeForHiddenUI(generation: UInt64) {
        guard ScreenCapture.isCaptureUIClosed(at: generation) else { return }
        invalidateSession(reason: "last UI closed")
    }

    // MARK: Capture API

    /// Captures MenuBarAgent's menu bar hosting window out of process.
    /// Mirrors ScreenCapture.captureMenuBarHostingWindowAsync(displayID:).
    public func captureMenuBarHostingWindow(
        displayID: CGDirectDisplayID,
        visibilityGeneration: UInt64? = nil
    ) async -> ScreenCapture.MenuBarHostingCapture? {
        await performCapture(.menuBarHostingWindow(displayID: displayID), visibilityGeneration: visibilityGeneration)?.makeHostingCapture()
    }

    /// Captures the on-screen menu bar strip out of process. Mirrors
    /// ScreenCapture.captureMenuBarDisplayStripAsync(displayID:).
    public func captureMenuBarDisplayStrip(
        displayID: CGDirectDisplayID,
        visibilityGeneration: UInt64? = nil
    ) async -> ScreenCapture.MenuBarHostingCapture? {
        await performCapture(.menuBarDisplayStrip(displayID: displayID), visibilityGeneration: visibilityGeneration)?.makeHostingCapture()
    }

    /// Captures one app's own menu bar window out of process. Mirrors
    /// ScreenCapture.captureOwnerBarWindow(windowID:frame:).
    public func captureOwnerBarWindow(
        windowID: CGWindowID,
        visibilityGeneration: UInt64? = nil
    ) async -> ScreenCapture.MenuBarHostingCapture? {
        await performCapture(.ownerBarWindow(windowID: windowID), visibilityGeneration: visibilityGeneration)?.makeHostingCapture()
    }

    /// Captures a composite of specific windows out of process. Mirrors
    /// ScreenCapture.captureWindows(with:screenBounds:option:); the
    /// helper rejects window IDs outside its own enumeration of
    /// menu-bar-layer and wallpaper windows.
    public func captureWindows(
        with windowIDs: [CGWindowID],
        screenBounds: CGRect? = nil,
        option: CGWindowImageOption = [],
        visibilityGeneration: UInt64? = nil
    ) async -> CGImage? {
        let request = CaptureServiceRequest.windows(
            ids: windowIDs,
            screenBounds: screenBounds,
            imageOptionRawValue: option.rawValue,
            scale: 0
        )
        return await performCapture(request, visibilityGeneration: visibilityGeneration)?.makeImage()
    }

    // MARK: Session Management

    /// One capture round trip, reopening the session once when the send
    /// fails, because the helper exited between calls, or because the
    /// round trip blew replyTimeout and the session was treated as
    /// wedged.
    ///
    /// Cancellation is not one of those failures: closing a panel cancels
    /// the capture filling it, and retrying would drop a good session to
    /// fetch a frame nobody wants. A cancelled request gives up and leaves
    /// the session for the next caller.
    private func performCapture(_ request: CaptureServiceRequest, visibilityGeneration: UInt64?) async -> CaptureServiceFrame? {
        guard let ticket = visibilityGeneration ?? ScreenCapture.captureUITicket(), ScreenCapture.isCaptureUITicketCurrent(ticket) else { return nil }
        inFlightCaptureCount += 1
        defer {
            inFlightCaptureCount -= 1
            closeSessionIfIdle()
        }

        for attempt in 0 ..< 2 {
            if Task.isCancelled || !ScreenCapture.isCaptureUITicketCurrent(ticket) {
                return nil
            }
            guard let (session, token) = ensureSession() else {
                return nil
            }
            do {
                let reply = try await send(request, over: session)
                guard ScreenCapture.isCaptureUITicketCurrent(ticket) else { return nil }
                if reply.generation < lastGeneration {
                    Self.diagLog.debug(
                        "MenuBarCaptureService restarted (generation \(self.lastGeneration) -> \(reply.generation))"
                    )
                }
                lastGeneration = reply.generation
                recordTransferred(reply.frame)
                return handle(reply)
            } catch {
                if error is CancellationError || Task.isCancelled || !ScreenCapture.isCaptureUITicketCurrent(ticket) {
                    return nil
                }
                // The helper exits after its capture budget and when the
                // last session closes; a stale session fails here. Drop
                // it and retry once, XPC relaunches the service. A concurrent
                // capture may already have replaced it; leave that one alone.
                if token == sessionToken {
                    invalidateSession(reason: "send failed: \(error)")
                }
                if attempt == 0 {
                    continue
                }
                Self.diagLog.error("MenuBarCaptureService capture failed after retry: \(error)")
                return nil
            }
        }
        return nil
    }

    /// Running total of pixel bytes pulled across the XPC boundary.
    ///
    /// Frames arrive as BGRA copies, so a full menu-bar strip is over a
    /// megabyte each. The volume is logged every 64 frames, enough to compare
    /// against a footprint reading without logging per capture.
    private func recordTransferred(_ frame: CaptureServiceFrame?) {
        guard let frame else { return }
        framesReceived += 1
        bytesReceived += frame.pixelData.count
        guard framesReceived.isMultiple(of: 64) else { return }
        let mib = Double(bytesReceived) / 1_048_576
        Self.diagLog.info(
            "MenuBarCaptureService transferred \(self.framesReceived) frames, \(String(format: "%.1f", mib)) MiB total"
        )
    }

    private func handle(_ reply: CaptureServiceReply) -> CaptureServiceFrame? {
        switch reply.failure {
        case .none:
            return reply.frame
        case .permissionDenied:
            // TCC attribution of the embedded helper can only be proven
            // at runtime. If macOS attributes Screen Recording to the
            // helper instead of the responsible app, every capture lands
            // here, surface it loudly with the way out.
            Self.diagLog.error(
                """
                MenuBarCaptureService reports Screen Recording permission denied, \
                TCC is likely attributing the helper separately from the app. \
                Flip the flag off with `defaults write \
                \(Bundle.main.bundleIdentifier ?? CaptureService.baseAppBundleIdentifier) \
                CaptureViaXPCService -bool false` to restore in-process capture, \
                or grant the helper Screen Recording in System Settings.
                """
            )
            return nil
        case .rejectedWindowID:
            Self.diagLog.error("MenuBarCaptureService rejected a requested window ID")
            return nil
        case .captureFailed:
            Self.diagLog.warning("MenuBarCaptureService capture failed in the helper")
            return nil
        }
    }

    /// One XPC round trip, bounded by replyTimeout.
    ///
    /// The deadline abandons rather than awaits: if the helper wedges, its
    /// reply handler never fires, so a structured (wait-for-children) timeout
    /// would hang exactly like the call it guards. The abandoned send stays
    /// parked until the framework resumes it (a late reply, or an
    /// invalidation error once invalidateSession(reason:) cancels the
    /// session), and its result is discarded.
    ///
    /// The deadline is unstructured for the same reason, and is cancelled as
    /// soon as the round trip resolves; otherwise live refresh would keep
    /// dozens of idle 12-second timers outstanding.
    private func send(
        _ request: CaptureServiceRequest,
        over session: XPCSession
    ) async throws -> CaptureServiceReply {
        try await withAbandoningTimeout(Self.replyTimeout) {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try session.send(request) { (result: Result<CaptureServiceReply, any Error>) in
                        continuation.resume(with: result)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureSession() -> (session: XPCSession, token: UUID)? {
        if let session, let sessionToken {
            return (session, sessionToken)
        }
        let token = UUID()
        do {
            let created = try XPCSession(
                xpcService: serviceName,
                cancellationHandler: { [weak self] error in
                    // Fires when the helper exits (capture budget reached,
                    // crash, or system reclaim), and also after this client
                    // cancels the session itself. Drop the session so the
                    // next capture reopens it, but only if it is still the
                    // current one.
                    Task { await self?.sessionCancelled(token: token, reason: "cancelled: \(error)") }
                }
            )
            Self.diagLog.debug("Opened MenuBarCaptureService session (\(self.serviceName))")
            session = created
            sessionToken = token
            return (created, token)
        } catch {
            Self.diagLog.error("Failed to open MenuBarCaptureService session: \(error)")
            return nil
        }
    }

    private func sessionCancelled(token: UUID, reason: String) {
        guard token == sessionToken else {
            return
        }
        invalidateSession(reason: reason)
    }

    private func invalidateSession(reason: String) {
        guard session != nil else {
            return
        }
        Self.diagLog.debug("Dropping MenuBarCaptureService session (\(reason))")
        session?.cancel(reason: reason)
        session = nil
        sessionToken = nil
    }

    private func closeSessionIfIdle() {
        guard liveConsumerCount == 0, inFlightCaptureCount == 0 else {
            return
        }
        invalidateSession(reason: "last consumer stopped")
    }
}
