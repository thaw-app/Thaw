//
//  Listener.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XPC

/// A wrapper around an XPC listener object.
final class Listener {
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
            case let .sourcePID(window):
                diagLog.debug("Listener: sourcePID request for windowID=\(window.windowID) title=\(window.title ?? "nil")")
                let pid = SourcePIDCache.shared.pid(for: window)
                diagLog.debug("Listener: sourcePID response for windowID=\(window.windowID) -> pid=\(pid.map { "\($0)" } ?? "nil")")
                return .sourcePID(pid)
            }
        } catch {
            diagLog.error("Listener failed to handle message with error \(error)")
            return nil
        }
    }

    /// Activates the listener without checking if it is already active,
    /// with the requirement that session peers must be signed with the
    /// same team identifier as the service process.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithSameTeamRequirement() throws {
        xpcListener = try XPCListener(service: name, requirement: .isFromSameTeam()) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        xpcListener = try XPCListener(service: name) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener.
    func activate() {
        guard xpcListener == nil else {
            diagLog.notice("Listener is already active")
            return
        }

        diagLog.debug("Activating listener")

        do {
            if #available(macOS 26.0, *) {
                try uncheckedActivateWithSameTeamRequirement()
            } else {
                try uncheckedActivate()
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
