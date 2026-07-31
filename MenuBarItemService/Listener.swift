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
    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying XPC listener object.
    private var xpcListener: XPCListener?

    /// Creates the shared listener.
    private init() {
        // Intentionally empty: this type is a singleton and is configured via `activate()`.
    }

    deinit {
        cancel()
    }

    /// Handles a received message.
    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                diagLog.debug("Listener received start request")
                return .start
            case let .configureLogging(filePath):
                // Only attach to files inside the app's approved log
                // directory. The path arrives from the XPC peer, and in
                // teamless (ad-hoc) builds the listener has no peer
                // requirement, so an arbitrary path could otherwise make
                // this service open and append to any user-writable file.
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
                DiagnosticLogger.shared.attachToFile(at: requested)
                diagLog.debug("Listener attached diagnostic logging to \(requested.path)")
                return .configureLogging
            case let .sourcePID(window):
                diagLog.debug("Listener: sourcePID request for windowID=\(window.windowID) title=\(window.title ?? "nil")")
                let pid = SourcePIDCache.shared.pid(for: window)
                diagLog.debug("Listener: sourcePID response for windowID=\(window.windowID) -> pid=\(pid.map { "\($0)" } ?? "nil")")
                return .sourcePID(pid)
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

    /// Activates the listener without checking if it is already active,
    /// with the requirement that session peers must be signed with the
    /// same team identifier as the service process.
    private func uncheckedActivateWithSameTeamRequirement() throws {
        xpcListener = try XPCListener(service: name, requirement: .isFromSameTeam()) { request in
            request.accept { [self] message in
                self.handleMessage(message)
            }
        }
    }

    /// Activates the listener without a peer requirement. Used for builds
    /// signed without a team identifier (ad-hoc/personal builds), where
    /// `.isFromSameTeam()` can never be satisfied and every session is
    /// cancelled before the first message.
    private func uncheckedActivateWithoutPeerRequirement() throws {
        xpcListener = try XPCListener(service: name) { request in
            request.accept { [self] message in
                self.handleMessage(message)
            }
        }
        diagLog.warning(
            "Listener is active WITHOUT peer validation (ad-hoc/teamless build): any local process may connect"
        )
    }

    /// Activates the listener.
    func activate() {
        guard xpcListener == nil else {
            diagLog.notice("Listener is already active")
            return
        }

        diagLog.debug("Activating listener")

        do {
            if CodeSigningInfo.processTeamIdentifier == nil {
                diagLog.notice("Listener: no team identifier (ad-hoc build), activating without peer requirement")
                try uncheckedActivateWithoutPeerRequirement()
            } else {
                try uncheckedActivateWithSameTeamRequirement()
            }
        } catch {
            diagLog.error("Failed to activate listener with error \(error)")
        }
    }

    /// Cancels the listener.
    func cancel() {
        diagLog.debug("Canceling listener")
        xpcListener.take()?.cancel()
    }
}
