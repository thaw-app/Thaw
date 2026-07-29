//
//  HotkeyRegistry.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Carbon.HIToolbox
import Cocoa
import Combine
import os.lock

/// An object that manages the registration, storage, and unregistration of hotkeys.
nonisolated final class HotkeyRegistry {
    private let diagLog = DiagLog(category: "HotkeyRegistry")
    /// The event kinds that a hotkey can be registered for.
    enum EventKind {
        case keyUp
        case keyDown

        fileprivate init?(event: EventRef) {
            switch Int(GetEventKind(event)) {
            case kEventHotKeyPressed:
                self = .keyDown
            case kEventHotKeyReleased:
                self = .keyUp
            default:
                return nil
            }
        }
    }

    /// An object that stores the information needed to cancel a registration.
    private final class Registration {
        let eventKind: EventKind
        let key: KeyCode
        let modifiers: Modifiers
        let hotKeyID: EventHotKeyID
        var hotKeyRef: EventHotKeyRef?
        let handler: () -> Void

        init(
            eventKind: EventKind,
            key: KeyCode,
            modifiers: Modifiers,
            hotKeyID: EventHotKeyID,
            hotKeyRef: EventHotKeyRef,
            handler: @escaping () -> Void
        ) {
            self.eventKind = eventKind
            self.key = key
            self.modifiers = modifiers
            self.hotKeyID = hotKeyID
            self.hotKeyRef = hotKeyRef
            self.handler = handler
        }
    }

    private let signature = OSType(1_231_250_720) // OSType for Ice

    private var eventHandlerRef: EventHandlerRef?

    /// Mutable registry storage (`registrations` and `cancellables`),
    /// protected by an unfair lock so lookups and mutations are safe from
    /// any isolation context. `Registration` is not `Sendable`, so access
    /// goes through the unchecked lock variants; every touch of the stored
    /// state happens while the lock is held.
    private struct MutableState {
        var registrations = [UInt32: Registration]()
        var cancellables = Set<AnyCancellable>()
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: MutableState())

    /// Installs the global event handler reference, if it isn't already installed.
    private func installIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }

        let didBeginTrackingObserver = NotificationCenter.default
            .publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                self?.unregisterAndRetainAll()
            }

        let didEndTrackingObserver = NotificationCenter.default
            .publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                self?.registerAllRetained()
            }

        state.withLockUnchecked { state in
            didBeginTrackingObserver.store(in: &state.cancellables)
            didEndTrackingObserver.store(in: &state.cancellables)
        }

        let handler: EventHandlerUPP = { _, event, userData in
            guard
                let event,
                let userData
            else {
                return OSStatus(eventNotHandledErr)
            }
            let registry = Unmanaged<HotkeyRegistry>.fromOpaque(userData).takeUnretainedValue()
            return registry.performEventHandler(for: event)
        }

        let eventTypes: [EventTypeSpec] = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        return InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            eventTypes.count,
            eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    /// Registers the given hotkey for the given event kind and returns the
    /// identifier of the registration on success.
    ///
    /// The returned identifier can be used to unregister the hotkey using
    /// the ``unregister(_:)`` function.
    ///
    /// - Parameters:
    ///   - hotkey: The hotkey to register the handler with.
    ///   - eventKind: The event kind to register the handler with.
    ///   - handler: The handler to perform when `hotkey` is triggered with
    ///     the event kind specified by `eventKind`.
    ///
    /// - Returns: The registration's identifier on success, `nil` on failure.
    @MainActor
    func register(hotkey: Hotkey, eventKind: EventKind, handler: @escaping () -> Void) -> UInt32? {
        enum Context {
            static nonisolated(unsafe) var currentID: UInt32 = 0
        }

        defer {
            Context.currentID += 1
        }

        guard let keyCombination = hotkey.keyCombination else {
            diagLog.error("Hotkey does not have a valid key combination")
            return nil
        }

        var status = installIfNeeded()

        guard status == noErr else {
            diagLog.error("Hotkey event handler installation failed with status \(status)")
            return nil
        }

        let id = Context.currentID

        guard state.withLockUnchecked({ $0.registrations[id] == nil }) else {
            diagLog.error("Hotkey already registered for id \(id)")
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        status = RegisterEventHotKey(
            UInt32(keyCombination.key.rawValue),
            UInt32(keyCombination.modifiers.carbonFlags),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            diagLog.error("Hotkey registration failed with status \(status)")
            return nil
        }

        guard let hotKeyRef else {
            diagLog.error("Hotkey registration failed due to invalid EventHotKeyRef")
            return nil
        }

        let registration = Registration(
            eventKind: eventKind,
            key: keyCombination.key,
            modifiers: keyCombination.modifiers,
            hotKeyID: hotKeyID,
            hotKeyRef: hotKeyRef,
            handler: handler
        )
        state.withLockUnchecked { state in
            state.registrations[id] = registration
        }

        return id
    }

    /// Unregisters the key combination with the given identifier, retaining
    /// its registration in an inactive state.
    ///
    /// Must be called while holding `state`'s lock, with the locked
    /// dictionary passed inout.
    private func retainedUnregister(_ id: UInt32, registrations: inout [UInt32: Registration]) {
        guard let registration = registrations[id] else {
            diagLog.error("No registered key combination for id \(id)")
            return
        }
        let status = UnregisterEventHotKey(registration.hotKeyRef)
        guard status == noErr else {
            diagLog.error("Hotkey unregistration failed with status \(status)")
            return
        }
        registration.hotKeyRef = nil
    }

    /// Unregisters the key combination with the given identifier.
    ///
    /// - Parameter id: An identifier returned from a call to the
    ///   ``register(hotkey:eventKind:handler:)`` function.
    func unregister(_ id: UInt32) {
        state.withLockUnchecked { state in
            retainedUnregister(id, registrations: &state.registrations)
            state.registrations.removeValue(forKey: id)
        }
    }

    /// Unregisters all key combinations, retaining their registrations
    /// in an inactive state.
    private func unregisterAndRetainAll() {
        state.withLockUnchecked { state in
            for (id, _) in state.registrations {
                retainedUnregister(id, registrations: &state.registrations)
            }
        }
    }

    /// Registers all registrations that were retained during a call to
    /// ``retainedUnregister(_:)``
    private func registerAllRetained() {
        state.withLockUnchecked { state in
            for registration in state.registrations.values {
                guard registration.hotKeyRef == nil else {
                    continue
                }

                var hotKeyRef: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    UInt32(registration.key.rawValue),
                    UInt32(registration.modifiers.carbonFlags),
                    registration.hotKeyID,
                    GetEventDispatcherTarget(),
                    0,
                    &hotKeyRef
                )

                guard
                    status == noErr,
                    let hotKeyRef
                else {
                    state.registrations.removeValue(forKey: registration.hotKeyID.id)
                    diagLog.error("Hotkey registration failed with status \(status)")
                    continue
                }

                registration.hotKeyRef = hotKeyRef
            }
        }
    }

    /// Retrieves and performs the event handler stored under the
    /// identifier for the specified event.
    private func performEventHandler(for event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        // create a hot key id from the event
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        // make sure creation was successful
        guard status == noErr else {
            return status
        }

        // make sure the event signature matches our signature and
        // that an event handler is registered for the event
        guard
            hotKeyID.signature == signature,
            let registration = state.withLockUnchecked({ $0.registrations[hotKeyID.id] }),
            registration.eventKind == EventKind(event: event)
        else {
            return OSStatus(eventNotHandledErr)
        }

        // all checks passed; perform the event handler
        registration.handler()

        return noErr
    }
}
