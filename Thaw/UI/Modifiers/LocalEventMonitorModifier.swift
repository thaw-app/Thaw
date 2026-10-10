//
//  LocalEventMonitorModifier.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

private struct LocalEventMonitorModifier: ViewModifier {
    /// Outside the main-actor model because the monitor callback is not
    /// isolated and NSEvent is not Sendable. Unchecked: the callback and view
    /// updates both run on the main thread, so accesses never overlap.
    fileprivate final class Handler: @unchecked Sendable {
        var action: (NSEvent) -> NSEvent? = { $0 }
    }

    @MainActor
    @Observable
    fileprivate final class Model {
        /// The monitor tracks this flag through didSet, so the initial false
        /// does not cost a redundant stop() before anything started.
        var isEnabled = false {
            didSet {
                guard oldValue != isEnabled else { return }
                applyEnablement()
            }
        }

        /// Replaced on every update pass. @State keeps the first Model, so a
        /// captured handler would answer with the first pass's values forever.
        /// Not observed: refreshing it must not trigger a re-render.
        @ObservationIgnored
        let handler = Handler()

        @ObservationIgnored
        private var monitor: EventMonitor?

        /// Builds the monitor on the first update pass, not in init:
        /// State(wrappedValue:) evaluates its argument on every pass.
        func configure(mask: NSEvent.EventTypeMask) {
            guard monitor == nil else { return }
            monitor = EventMonitor.local(for: mask) { [handler] event in
                handler.action(event)
            }
            applyEnablement()
        }

        private func applyEnablement() {
            guard let monitor else { return }
            if isEnabled {
                monitor.start()
            } else {
                monitor.stop()
            }
        }
    }

    @State private var model = Model()

    let mask: NSEvent.EventTypeMask
    let isEnabled: Bool
    let action: (NSEvent) -> NSEvent?

    func body(content: Content) -> some View {
        // Both writes are to @ObservationIgnored storage, so neither invalidates anything.
        model.handler.action = action
        model.configure(mask: mask)

        return content.onChange(of: isEnabled, initial: true) { _, newValue in
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
    ///     corresponding to mask.
    func localEventMonitor(mask: NSEvent.EventTypeMask, isEnabled: Bool = true, action: @escaping (NSEvent) -> NSEvent?) -> some View {
        modifier(LocalEventMonitorModifier(mask: mask, isEnabled: isEnabled, action: action))
    }
}
