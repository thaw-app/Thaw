//
//  EventMonitor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import os.lock

struct EventMonitor {
    private static let diagLog = DiagLog(category: "EventMonitor")
    private final class LocalMonitorState: @unchecked Sendable {
        private let mask: NSEvent.EventTypeMask
        private let handler: (NSEvent) -> NSEvent?
        private var monitor: Any?

        /// Whether the monitor is currently installed.
        var isRunning: Bool {
            monitor != nil
        }

        init(
            mask: NSEvent.EventTypeMask,
            handler: @escaping (NSEvent) -> NSEvent?
        ) {
            self.mask = mask
            self.handler = handler
        }

        deinit {
            stop()
        }

        func start() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else {
                    return event
                }
                return handler(event)
            }
            if monitor == nil {
                EventMonitor.diagLog.error("Failed to create local event monitor for mask \(self.mask.rawValue)")
            }
        }

        func stop() {
            guard let monitor = monitor.take() else {
                return
            }
            NSEvent.removeMonitor(monitor)
        }

        func restart() {
            stop()
            start()
        }
    }

    private final class GlobalMonitorState: @unchecked Sendable {
        private let mask: NSEvent.EventTypeMask
        private let handler: (NSEvent) -> Void
        private var monitor: Any?

        /// Whether the monitor is currently installed.
        var isRunning: Bool {
            monitor != nil
        }

        init(
            mask: NSEvent.EventTypeMask,
            handler: @escaping (NSEvent) -> Void
        ) {
            self.mask = mask
            self.handler = handler
        }

        deinit {
            stop()
        }

        func start() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else {
                    return
                }
                handler(event)
            }
            if monitor == nil {
                EventMonitor.diagLog.error("Failed to create global event monitor for mask \(self.mask.rawValue)")
            }
        }

        func stop() {
            guard let monitor = monitor.take() else {
                return
            }
            NSEvent.removeMonitor(monitor)
        }

        func restart() {
            stop()
            start()
        }
    }

    private final class UniversalMonitorState: @unchecked Sendable {
        private let mask: NSEvent.EventTypeMask
        private let localHandler: (NSEvent) -> NSEvent?
        private let globalHandler: (NSEvent) -> Void
        private var monitors: (local: Any, global: Any)?

        /// Whether both monitors are currently installed.
        var isRunning: Bool {
            monitors != nil
        }

        init(
            mask: NSEvent.EventTypeMask,
            localHandler: @escaping (NSEvent) -> NSEvent?,
            globalHandler: @escaping (NSEvent) -> Void
        ) {
            self.mask = mask
            self.localHandler = localHandler
            self.globalHandler = globalHandler
        }

        init(
            mask: NSEvent.EventTypeMask,
            handler: @escaping (NSEvent) -> NSEvent?
        ) {
            self.mask = mask
            self.localHandler = handler
            self.globalHandler = { _ = handler($0) }
        }

        deinit {
            stop()
        }

        func start() {
            guard monitors == nil else {
                return
            }

            let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else {
                    return event
                }
                return localHandler(event)
            }

            guard let local else {
                EventMonitor.diagLog.error("Failed to create local event monitor for mask \(self.mask.rawValue)")
                return
            }

            let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else {
                    return
                }
                globalHandler(event)
            }

            guard let global else {
                EventMonitor.diagLog.error("Failed to create global event monitor for mask \(self.mask.rawValue)")
                NSEvent.removeMonitor(local)
                return
            }

            monitors = (local, global)
        }

        func stop() {
            guard let monitors = monitors.take() else {
                return
            }
            NSEvent.removeMonitor(monitors.local)
            NSEvent.removeMonitor(monitors.global)
        }

        func restart() {
            stop()
            start()
        }
    }

    private enum State: @unchecked Sendable {
        case local(LocalMonitorState)
        case global(GlobalMonitorState)
        case universal(UniversalMonitorState)

        var scope: Scope {
            switch self {
            case .local: .local
            case .global: .global
            case .universal: .universal
            }
        }

        var isRunning: Bool {
            switch self {
            case let .local(state): state.isRunning
            case let .global(state): state.isRunning
            case let .universal(state): state.isRunning
            }
        }

        func start() {
            switch self {
            case let .local(state): state.start()
            case let .global(state): state.start()
            case let .universal(state): state.start()
            }
        }

        func stop() {
            switch self {
            case let .local(state): state.stop()
            case let .global(state): state.stop()
            case let .universal(state): state.stop()
            }
        }

        func restart() {
            switch self {
            case let .local(state): state.restart()
            case let .global(state): state.restart()
            case let .universal(state): state.restart()
            }
        }
    }

    /// Scopes where an event monitor can listen for events.
    enum Scope {
        case local
        case global
        case universal
    }

    private let state: OSAllocatedUnfairLock<State>

    /// The scope where the monitor listens for events.
    var scope: Scope {
        state.withLock { $0.scope }
    }

    /// A Boolean value indicating whether the monitor is currently installed and running.
    var isRunning: Bool {
        state.withLock { $0.isRunning }
    }

    private init(state: State) {
        self.state = OSAllocatedUnfairLock(initialState: state)
    }

    private init(
        mask: NSEvent.EventTypeMask,
        scope: Scope,
        passiveHandler: @escaping (NSEvent) -> Void
    ) {
        lazy var activeHandler: (NSEvent) -> NSEvent? = { event in
            passiveHandler(event)
            return event
        }
        switch scope {
        case .local:
            let baseState = LocalMonitorState(mask: mask, handler: activeHandler)
            self.init(state: .local(baseState))
        case .global:
            let baseState = GlobalMonitorState(mask: mask, handler: passiveHandler)
            self.init(state: .global(baseState))
        case .universal:
            let baseState = UniversalMonitorState(mask: mask, localHandler: activeHandler, globalHandler: passiveHandler)
            self.init(state: .universal(baseState))
        }
    }

    /// Installs the monitor and begins listening for events.
    func start() {
        state.withLock { $0.start() }
    }

    /// Uninstalls the monitor and stops listening for events.
    func stop() {
        state.withLock { $0.stop() }
    }

    /// Stops and restarts the monitor. Use this to recover from a potentially
    /// broken state where the underlying NSEvent monitor may have become invalid.
    func restart() {
        state.withLock { state in
            let scope = state.scope
            EventMonitor.diagLog.info("Restarting \(scope) event monitor")
            state.restart()
            if state.isRunning {
                EventMonitor.diagLog.info("Successfully restarted \(scope) event monitor")
            } else {
                EventMonitor.diagLog.error("Failed to restart \(scope) event monitor")
            }
        }
    }

    /// Checks whether the monitor is running and restarts it if not.
    /// Returns `true` if the monitor is running after this call.
    @discardableResult
    func ensureRunning() -> Bool {
        state.withLock { state in
            if !state.isRunning {
                let scope = state.scope
                EventMonitor.diagLog.warning("\(scope) event monitor not running, attempting restart")
                state.restart()
                if state.isRunning {
                    EventMonitor.diagLog.info("Successfully restarted \(scope) event monitor")
                } else {
                    EventMonitor.diagLog.error("Failed to restart \(scope) event monitor after ensureRunning")
                }
            }
            return state.isRunning
        }
    }
}

extension EventMonitor {
    static func local(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        let state = LocalMonitorState(mask: mask, handler: handler)
        return EventMonitor(state: .local(state))
    }

    static func global(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        let state = GlobalMonitorState(mask: mask, handler: handler)
        return EventMonitor(state: .global(state))
    }

    static func universal(
        for mask: NSEvent.EventTypeMask,
        localHandler: @escaping (NSEvent) -> NSEvent?,
        globalHandler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        let state = UniversalMonitorState(
            mask: mask,
            localHandler: localHandler,
            globalHandler: globalHandler
        )
        return EventMonitor(state: .universal(state))
    }

    static func universal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        let state = UniversalMonitorState(mask: mask, handler: handler)
        return EventMonitor(state: .universal(state))
    }

    static func passive(
        for mask: NSEvent.EventTypeMask,
        scope: Scope,
        handler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        EventMonitor(mask: mask, scope: scope, passiveHandler: handler)
    }
}

extension EventMonitor {
    @discardableResult
    static func startLocal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        let monitor = local(for: mask, handler: handler)
        monitor.start()
        return monitor
    }

    @discardableResult
    static func startGlobal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        let monitor = global(for: mask, handler: handler)
        monitor.start()
        return monitor
    }

    @discardableResult
    static func startUniversal(
        for mask: NSEvent.EventTypeMask,
        localHandler: @escaping (NSEvent) -> NSEvent?,
        globalHandler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        let monitor = universal(for: mask, localHandler: localHandler, globalHandler: globalHandler)
        monitor.start()
        return monitor
    }

    @discardableResult
    static func startUniversal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        let monitor = universal(for: mask, handler: handler)
        monitor.start()
        return monitor
    }

    @discardableResult
    static func startPassive(
        for mask: NSEvent.EventTypeMask,
        scope: Scope,
        handler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        let monitor = passive(for: mask, scope: scope, handler: handler)
        monitor.start()
        return monitor
    }
}

extension EventMonitor {
    /// A publisher that emits events received within a defined scope.
    struct EventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        /// The event type mask that determines the events the publisher receives.
        let mask: NSEvent.EventTypeMask

        /// The scope where the publisher receives events.
        let scope: EventMonitor.Scope

        func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let subscription = EventSubscription(mask: mask, scope: scope, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }

    /// Returns a publisher that emits events received within a defined scope.
    ///
    /// - Parameters:
    ///   - events: A mask that determines the events the publisher receives.
    ///   - scope: A scope that determines where the publisher receives events.
    static func publish(events: NSEvent.EventTypeMask, scope: Scope) -> EventPublisher {
        EventPublisher(mask: events, scope: scope)
    }
}

extension EventMonitor.EventPublisher {
    private final class EventSubscription<S: Subscriber>: Subscription where S.Input == Output, S.Failure == Failure {
        private final class SubscriberBox {
            private let subscriber: S

            init(subscriber: S) {
                self.subscriber = subscriber
            }

            @discardableResult
            func receive(_ event: NSEvent) -> Subscribers.Demand {
                subscriber.receive(event)
            }
        }

        private var box: SubscriberBox?
        private let monitor: EventMonitor

        init(mask: NSEvent.EventTypeMask, scope: EventMonitor.Scope, subscriber: S) {
            self.box = SubscriberBox(subscriber: subscriber)
            self.monitor = .startPassive(for: mask, scope: scope) { [weak box] event in
                box?.receive(event)
            }
        }

        func request(_: Subscribers.Demand) {
            // Intentionally empty: AppKit pushes events as they occur, so this passive monitor cannot honor Combine backpressure.
        }

        func cancel() {
            box = nil
            monitor.stop()
        }
    }
}
