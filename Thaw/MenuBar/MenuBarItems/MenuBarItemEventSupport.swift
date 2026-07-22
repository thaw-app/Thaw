//
//  MenuBarItemEventSupport.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - CGEventField Helpers

nonisolated extension CGEventField {
    /// Key to access a field that contains the event's window identifier.
    static let windowID = CGEventField(rawValue: 0x33)! // swiftlint:disable:this force_unwrapping

    /// Fields that can be used to compare menu bar item events.
    static let menuBarItemEventFields: [CGEventField] = [
        .eventSourceUserData,
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        .windowID,
    ]
}

// MARK: - MoveInputSuppression

nonisolated enum MoveInputSuppression {
    private static let syntheticMoveUserData: Int64 = 0x5468_6177_4D6F_7665

    static let suppressedMouseEventTypes: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]

    static func markSyntheticMoveEvent(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMoveUserData)
    }

    static func shouldSuppress(_ event: CGEvent) -> Bool {
        guard suppressedMouseEventTypes.contains(event.type) else { return false }
        return event.getIntegerValueField(.eventSourceUserData) == 0
    }

    @MainActor
    static func withUserMouseInputSuppressed<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        let tap = EventTap(
            label: "Move input suppression",
            types: suppressedMouseEventTypes,
            location: .hidEventTap,
            placement: .headInsertEventTap,
            option: .defaultTap
        ) { _, event in
            shouldSuppress(event) ? nil : event
        }

        if tap.isValid {
            tap.enable()
        } else {
            MenuBarItemManager.diagLog.warning("Move input suppression tap could not be created")
        }
        defer { tap.invalidate() }
        return try await operation()
    }
}

// MARK: - CGEventFilterMask Helpers

nonisolated extension CGEventFilterMask {
    /// Specifies that all events should be permitted during event suppression states.
    static let permitAllEvents: CGEventFilterMask = [
        .permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents,
    ]
}

// MARK: - CGEventType Helpers

private nonisolated extension CGEventType {
    var logString: String {
        switch self {
        case .null: "null event"
        case .leftMouseDown: "leftMouseDown event"
        case .leftMouseUp: "leftMouseUp event"
        case .rightMouseDown: "rightMouseDown event"
        case .rightMouseUp: "rightMouseUp event"
        case .mouseMoved: "mouseMoved event"
        case .leftMouseDragged: "leftMouseDragged event"
        case .rightMouseDragged: "rightMouseDragged event"
        case .keyDown: "keyDown event"
        case .keyUp: "keyUp event"
        case .flagsChanged: "flagsChanged event"
        case .scrollWheel: "scrollWheel event"
        case .tabletPointer: "tabletPointer event"
        case .tabletProximity: "tabletProximity event"
        case .otherMouseDown: "otherMouseDown event"
        case .otherMouseUp: "otherMouseUp event"
        case .otherMouseDragged: "otherMouseDragged event"
        case .tapDisabledByTimeout: "tapDisabledByTimeout event"
        case .tapDisabledByUserInput: "tapDisabledByUserInput event"
        @unknown default: "unknown event"
        }
    }
}

// MARK: - CGMouseButton Helpers

nonisolated extension CGMouseButton {
    var logString: String {
        switch self {
        case .left: "left mouse button"
        case .right: "right mouse button"
        case .center: "center mouse button"
        @unknown default: "unknown mouse button"
        }
    }
}

// MARK: - Duration Helpers

nonisolated extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }
}

// MARK: - CGEvent Helpers

nonisolated extension CGEvent {
    static func menuBarItemEvent(
        item: MenuBarItem,
        source: CGEventSource,
        type: MenuBarItemEventType,
        location: CGPoint
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type.cgEventType,
            mouseCursorPosition: location,
            mouseButton: type.cgMouseButton
        ) else { return nil }
        event.setFlags(for: type)
        event.setUserData(ObjectIdentifier(event))
        event.setWindowID(item.windowID, for: type)
        event.setClickState(for: type)
        return event
    }

    static func uniqueNullEvent() -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.setUserData(ObjectIdentifier(event))
        return event
    }

    func post(to location: EventTap.Location) {
        let type = type
        MenuBarItemManager.diagLog.debug("Posting \(type.logString) to \(location.logString)")
        switch location {
        case .hidEventTap: post(tap: .cghidEventTap)
        case .sessionEventTap: post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap: post(tap: .cgAnnotatedSessionEventTap)
        case let .pid(pid): postToPid(pid)
        }
    }

    func matches(_ other: CGEvent, byIntegerFields fields: [CGEventField]) -> Bool {
        fields.allSatisfy { getIntegerValueField($0) == other.getIntegerValueField($0) }
    }

    func setTargetPID(_ pid: pid_t) {
        setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
    }

    private func setFlags(for type: MenuBarItemEventType) {
        flags = type.cgEventFlags
    }

    private func setUserData(_ bitPattern: ObjectIdentifier) {
        setIntegerValueField(.eventSourceUserData, value: Int64(Int(bitPattern: bitPattern)))
    }

    private func setWindowID(_ windowID: CGWindowID, for type: MenuBarItemEventType) {
        let windowID = Int64(windowID)
        setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
        setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
        if case .move = type {
            setIntegerValueField(.windowID, value: windowID)
        }
    }

    private func setClickState(for type: MenuBarItemEventType) {
        if case let .click(subtype) = type {
            setIntegerValueField(.mouseEventClickState, value: subtype.clickState)
        }
    }
}
