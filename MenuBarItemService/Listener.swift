//
//  Listener.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Security
import XPC

/// A wrapper around an XPC listener object.
final class Listener: @unchecked Sendable {
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
                DiagnosticLogger.shared.attachToFile(at: URL(fileURLWithPath: filePath))
                diagLog.debug("Listener attached diagnostic logging to \(filePath)")
                return .configureLogging
            case let .sourcePID(window):
                diagLog.debug("Listener: sourcePID request for windowID=\(window.windowID) title=\(window.title ?? "nil")")
                let pid = SourcePIDCache.shared.pid(for: window)
                diagLog.debug("Listener: sourcePID response for windowID=\(window.windowID) -> pid=\(pid.map { "\($0)" } ?? "nil")")
                return .sourcePID(pid)
            case let .sourcePIDs(windows):
                diagLog.debug("Listener: sourcePIDs batch request for \(windows.count) windows")
                let pids = SourcePIDCache.shared.pids(for: windows)
                diagLog.debug("Listener: sourcePIDs batch response (\(pids.compactMap(\.self).count) resolved)")
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
    }

    /// The team identifier of the current process, or `nil` when signed
    /// without one (ad-hoc).
    private static let processTeamIdentifier: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else {
            return nil
        }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    /// Activates the listener.
    func activate() {
        guard xpcListener == nil else {
            diagLog.notice("Listener is already active")
            return
        }

        diagLog.debug("Activating listener")

        do {
            if Self.processTeamIdentifier == nil {
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
