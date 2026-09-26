//
//  Listener.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import Foundation
import XPC

/// A wrapper around an XPC listener object.
///
/// Explicitly nonisolated: XPC callbacks arrive on arbitrary threads, and the
/// target's default actor isolation is MainActor.
final nonisolated class Listener: @unchecked Sendable {
    private let diagLog = DiagLog(category: "Listener")
    static let shared = Listener()

    private let name = MenuBarItemService.name

    /// The underlying XPC listener object.
    private var xpcListener: XPCListener?

    private init() {
        // Intentionally empty: this type is a singleton and is configured via `activate()`.
    }

    deinit {
        cancel()
    }

    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                diagLog.debug("Listener received start request")
                return .start
            case let .configureLogging(filePath, rotationPolicy):
                if let rotationPolicy {
                    // Prune by the app's retention settings, not this target's
                    // defaults: both processes share one log directory.
                    DiagnosticLogger.shared.setRotationPolicy(rotationPolicy)
                }
                guard let filePath else {
                    // The app turned file logging off; stop writing to the
                    // shared file rather than holding it open.
                    DiagnosticLogger.shared.isEnabled = false
                    diagLog.debug("Listener disabled diagnostic logging")
                    return .configureLogging
                }
                // Only attach inside the approved log directory. Ad-hoc builds have no
                // peer requirement, so a peer could otherwise point us at any writable file.
                let requested = URL(fileURLWithPath: filePath)
                    .standardizedFileURL.resolvingSymlinksInPath()
                let approvedDir = DiagnosticLogger.shared.logDirectory
                    .standardizedFileURL.resolvingSymlinksInPath()
                guard requested.path.hasPrefix(approvedDir.path + "/") else {
                    diagLog.error(
                        "Listener rejected configureLogging path outside approved log directory: \(filePath)"
                    )
                    return nil
                }
                guard DiagnosticLogger.shared.attachToFile(at: requested) else {
                    // Replying success would leave this process writing to the old
                    // segment, which retention later deletes. Failing makes the app retry.
                    diagLog.error("Listener failed to attach diagnostic logging to \(requested.path)")
                    return nil
                }
                diagLog.debug("Listener attached diagnostic logging to \(requested.path)")
                return .configureLogging
            case let .sourcePIDs(windows):
                diagLog.debug("Listener: sourcePIDs batch request for \(windows.count) windows")
                let pids = SourcePIDCache.shared.pids(for: windows)
                diagLog.debug("Listener: sourcePIDs batch response (\(pids.compacted().count) resolved)")
                return .sourcePIDs(pids)
            }
        } catch {
            diagLog.error("Listener failed to handle message with error \(error)")
            return nil
        }
    }

    /// Accepts an incoming session request, routing its messages to
    /// ``handleMessage(_:)``.
    private func acceptSession(
        _ request: XPCListener.IncomingSessionRequest
    ) -> XPCListener.IncomingSessionRequest.Decision {
        request.accept { [self] message in
            self.handleMessage(message)
        }
    }

    /// Activates the listener.
    ///
    /// Peers must share the service's team identifier. Ad-hoc builds skip the
    /// peer requirement, since `.isFromSameTeam()` can never pass there.
    func activate() {
        guard xpcListener == nil else {
            diagLog.notice("Listener is already active")
            return
        }

        diagLog.debug("Activating listener")

        do {
            if CodeSigningInfo.processTeamIdentifier == nil {
                diagLog.notice("Listener: no team identifier (ad-hoc build), activating without peer requirement")
                xpcListener = try XPCListener(service: name) { self.acceptSession($0) }
                diagLog.warning(
                    "Listener is active WITHOUT peer validation (ad-hoc/teamless build): any local process may connect"
                )
            } else {
                xpcListener = try XPCListener(service: name, requirement: .isFromSameTeam()) { self.acceptSession($0) }
            }
        } catch {
            diagLog.error("Failed to activate listener with error \(error)")
        }
    }

    func cancel() {
        diagLog.debug("Canceling listener")
        xpcListener.take()?.cancel()
    }
}
