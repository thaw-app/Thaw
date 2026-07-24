//
//  LocalEventMonitorModifier.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation
import SwiftUI

private struct LocalEventMonitorModifier: ViewModifier {
    @MainActor
    @Observable
    final class Model {
        var isEnabled = false {
            didSet {
                if isEnabled {
                    monitor.start()
                } else {
                    monitor.stop()
                }
            }
        }

        @ObservationIgnored
        private let monitor: EventMonitor

        init(mask: NSEvent.EventTypeMask, action: @escaping (NSEvent) -> NSEvent?) {
            self.monitor = EventMonitor.local(for: mask, handler: action)
        }
    }

    @State private var model: Model
    @Binding var isEnabled: Bool

    init(mask: NSEvent.EventTypeMask, isEnabled: Binding<Bool>, action: @escaping (NSEvent) -> NSEvent?) {
        self._model = State(wrappedValue: Model(mask: mask, action: action))
        self._isEnabled = isEnabled
    }

    func body(content: Content) -> some View {
        content.onChange(of: isEnabled, initial: true) { _, newValue in
            model.isEnabled = newValue
        }
    }
}

extension View {
    /// Returns a view that performs the given action when events corresponding
    /// to the given event type mask are received.
    ///
    /// - Parameters:
    ///   - mask: An event type mask specifying which events to monitor.
    ///   - isEnabled: A Boolean value that determines whether the event monitor
    ///     is enabled.
    ///   - action: An action to perform when the event monitor receives events
    ///     corresponding to `mask`.
    func localEventMonitor(mask: NSEvent.EventTypeMask, isEnabled: Bool = true, action: @escaping (NSEvent) -> NSEvent?) -> some View {
        modifier(LocalEventMonitorModifier(mask: mask, isEnabled: .constant(isEnabled), action: action))
    }
}
