//
//  Bridging+SpaceEvents.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Synchronization

/// A Space change the window server reports to every connection that asks.
public enum WindowServerSpaceEvent: Sendable, Equatable {
    /// The active Space changed. Sent as the transition starts.
    case activeSpaceChanged
    /// A Space was created or deleted.
    case spacesChanged

    /// The event ids, found by testing, that Thaw listens for.
    public static let activeSpaceEventIDs: [UInt32] = [1329, 1401]
    public static let spacesChangedEventIDs: [UInt32] = [818, 828, 1322]

    public static var registeredEventIDs: [UInt32] {
        activeSpaceEventIDs + spacesChangedEventIDs
    }

    /// The event a window server notification id stands for, or nil for one Thaw doesn't use.
    public init?(eventID: UInt32) {
        if Self.activeSpaceEventIDs.contains(eventID) {
            self = .activeSpaceChanged
        } else if Self.spacesChangedEventIDs.contains(eventID) {
            self = .spacesChanged
        } else {
            return nil
        }
    }
}

public extension Bridging {
    /// Sends window server Space events to handler, which replaces any earlier one.
    ///
    /// The callback is registered once per process and cannot be removed.
    /// - Returns: False when the symbol is missing or a registration failed, so callers rely on NSWorkspace alone.
    @discardableResult
    static func setSpaceEventHandler(_ handler: @escaping @Sendable (WindowServerSpaceEvent) -> Void) -> Bool {
        spaceEventHandler.withLock { $0 = handler }
        return spaceEventRegistration.withLock { registered in
            if let registered {
                return registered
            }
            let result = registerSpaceEvents()
            registered = result
            return result
        }
    }
}

private extension Bridging {
    static let spaceEventHandler = Mutex<(@Sendable (WindowServerSpaceEvent) -> Void)?>(nil)
    static let spaceEventRegistration = Mutex<Bool?>(nil)
    static let spaceEventLog = DiagLog(category: "SpaceEvents")

    /// A C callback can't capture, so it reads the handler from static storage.
    static let spaceEventProc: SLSConnectionNotifications.Proc = { eventID, _, _, _, _ in
        guard let event = WindowServerSpaceEvent(eventID: eventID) else { return }
        let handler = Bridging.spaceEventHandler.withLock { $0 }
        handler?(event)
    }

    static func registerSpaceEvents() -> Bool {
        guard let register = SLSConnectionNotifications.register else {
            spaceEventLog.warning("SLSRegisterConnectionNotifyProc is missing; Space changes come from NSWorkspace only")
            return false
        }
        let connection = cgsMainConnectionID()
        var succeeded = true
        for eventID in WindowServerSpaceEvent.registeredEventIDs {
            let status = register(connection, spaceEventProc, eventID, nil)
            if status != .success {
                spaceEventLog.warning("Registering for window server event \(eventID) failed with error \(status.logString)")
                succeeded = false
            }
        }
        return succeeded
    }
}
