//
//  HotkeyRegistry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Carbon.HIToolbox
import Cocoa
import Combine
import MenuBarModel

/// Registers global hotkeys with Carbon and routes IDs to closures through one shared dispatcher handler.
final class HotkeyRegistry {
    private let diagLog = DiagLog(category: "HotkeyRegistry")

    /// The point in a key press at which a handler runs.
    enum EventKind {
        case keyUp
        case keyDown

        /// Rejects Carbon event kinds other than hotkey press and release.
        fileprivate init?(carbonEventKind: UInt32) {
            switch Int(carbonEventKind) {
            case kEventHotKeyPressed:
                self = .keyDown
            case kEventHotKeyReleased:
                self = .keyUp
            default:
                return nil
            }
        }
    }

    /// Bindings survive temporary release during menu tracking; carbonRef becomes nil until reclaimed.
    private final class Binding {
        let identifier: EventHotKeyID
        let eventKind: EventKind
        let carbonKeyCode: UInt32
        let carbonModifiers: UInt32
        let perform: () -> Void

        /// Nil while the key combination is released to the system.
        var carbonRef: EventHotKeyRef?

        init(
            identifier: EventHotKeyID,
            eventKind: EventKind,
            carbonKeyCode: UInt32,
            carbonModifiers: UInt32,
            perform: @escaping () -> Void
        ) {
            self.identifier = identifier
            self.eventKind = eventKind
            self.carbonKeyCode = carbonKeyCode
            self.carbonModifiers = carbonModifiers
            self.perform = perform
        }
    }

    private let signature = OSType(1_231_250_720) // OSType for Ice

    /// A process-wide counter prevents ID collisions between registries sharing the signature.
    @MainActor private static var lastIdentifier: UInt32 = 0

    /// Installed lazily on the first registration.
    private var eventHandlerRef: EventHandlerRef?

    private var bindings = [UInt32: Binding]()

    private var cancellables = Set<AnyCancellable>()

    /// Claims a hotkey, installing the Carbon handler lazily for the app's lifetime.
    ///
    /// - Parameters:
    ///   - hotkey: Must have a key combination to claim.
    ///   - eventKind: Whether handler runs on key down or key up.
    ///   - handler: The work to perform when the combination is pressed.
    ///
    /// - Returns: An ID for unregister(_:), or nil if the combination cannot be claimed.
    @MainActor
    func register(hotkey: Hotkey, eventKind: EventKind, handler: @escaping () -> Void) -> UInt32? {
        guard let keyCombination = hotkey.keyCombination else {
            diagLog.error("Hotkey does not have a valid key combination")
            return nil
        }

        let installStatus = installEventHandlerIfNeeded()
        guard installStatus == noErr else {
            diagLog.error("Hotkey event handler installation failed with status \(installStatus)")
            return nil
        }

        Self.lastIdentifier += 1
        let id = Self.lastIdentifier

        guard bindings[id] == nil else {
            diagLog.error("Hotkey already registered for id \(id)")
            return nil
        }

        let binding = Binding(
            identifier: EventHotKeyID(signature: signature, id: id),
            eventKind: eventKind,
            carbonKeyCode: UInt32(keyCombination.key.rawValue),
            carbonModifiers: UInt32(keyCombination.modifiers.carbonFlags),
            perform: handler
        )

        guard claim(binding) else {
            return nil
        }

        bindings[id] = binding
        return id
    }

    /// - Parameter id: The ID returned by register(hotkey:eventKind:handler:).
    func unregister(_ id: UInt32) {
        guard let binding = bindings.removeValue(forKey: id) else {
            diagLog.error("No registered key combination for id \(id)")
            return
        }
        release(binding)
    }

    /// - Returns: noErr if installed, otherwise Carbon's error status.
    private func installEventHandlerIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }

        observeMenuTracking()

        // The C callback receives the registry through userData rather than a capture.
        let callback: EventHandlerUPP = { _, event, userData in
            guard
                let event,
                let userData
            else {
                return OSStatus(eventNotHandledErr)
            }
            let registry = Unmanaged<HotkeyRegistry>.fromOpaque(userData).takeUnretainedValue()
            return registry.dispatch(event)
        }

        let hotKeyEvents = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        return InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            hotKeyEvents.count,
            hotKeyEvents,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    /// Release hotkeys during menu tracking so the open menu gets first refusal; reclaim them on close.
    private func observeMenuTracking() {
        guard cancellables.isEmpty else {
            return
        }

        let center = NotificationCenter.default
        let menuOpened = center.publisher(for: NSMenu.didBeginTrackingNotification).map { _ in true }
        let menuClosed = center.publisher(for: NSMenu.didEndTrackingNotification).map { _ in false }

        menuOpened
            .merge(with: menuClosed)
            .sink { [weak self] isTracking in
                guard let self else {
                    return
                }
                if isTracking {
                    releaseAll()
                } else {
                    reclaimAll()
                }
            }
            .store(in: &cancellables)
    }

    /// - Returns: true if the registry now owns the key combination.
    @discardableResult
    private func claim(_ binding: Binding) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.carbonKeyCode,
            binding.carbonModifiers,
            binding.identifier,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            diagLog.error("Hotkey registration failed with status \(status)")
            return false
        }
        guard let hotKeyRef else {
            diagLog.error("Hotkey registration failed due to invalid EventHotKeyRef")
            return false
        }

        binding.carbonRef = hotKeyRef
        return true
    }

    /// Releases the combination without discarding its binding.
    private func release(_ binding: Binding) {
        guard let hotKeyRef = binding.carbonRef else {
            return
        }
        let status = UnregisterEventHotKey(hotKeyRef)
        guard status == noErr else {
            diagLog.error("Hotkey unregistration failed with status \(status)")
            return
        }
        binding.carbonRef = nil
    }

    private func releaseAll() {
        for binding in bindings.values {
            release(binding)
        }
    }

    /// Discards bindings whose released key combinations cannot be reclaimed.
    private func reclaimAll() {
        var refused = [UInt32]()
        for (id, binding) in bindings where binding.carbonRef == nil {
            if !claim(binding) {
                refused.append(id)
            }
        }
        for id in refused {
            bindings.removeValue(forKey: id)
        }
    }

    /// Carbon sends dispatcher events to every handler; leave other registries' events unhandled.
    private func dispatch(_ event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )

        guard status == noErr else {
            return status
        }

        guard
            identifier.signature == signature,
            let binding = bindings[identifier.id],
            binding.eventKind == EventKind(carbonEventKind: GetEventKind(event))
        else {
            return OSStatus(eventNotHandledErr)
        }

        binding.perform()
        return noErr
    }
}
