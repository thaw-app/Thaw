//
//  EventMonitor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import os.lock

/// A handle to one or two AppKit event monitors, installed and removed
/// together.
///
/// A monitor can watch events delivered to this app (local), events
/// delivered to other apps (global), or both at once (universal). Only a
/// local monitor sits in the delivery path and can alter or swallow an event;
/// a global monitor is always a bystander.
nonisolated struct EventMonitor {
    /// The places a monitor can watch for events.
    enum Scope {
        case local
        case global
        case universal
    }

    private static let diagLog = DiagLog(category: "EventMonitor")

    /// The installed AppKit monitors behind an EventMonitor, plus the
    /// handlers used to reinstall them.
    ///
    /// A local handler, a global handler, or both may be present; which are
    /// present is what defines the monitor's scope. Installation is all
    /// or nothing, so tokens is either empty or holds one token per handler.
    ///
    /// Every mutation happens inside EventMonitor's OSAllocatedUnfairLock,
    /// which is what makes the @unchecked Sendable conformance sound. The
    /// closures handed to AppKit run outside that lock, but they only touch
    /// the immutable handler lets and a weak back reference, never tokens.
    private final class Installation: @unchecked Sendable {
        private let mask: NSEvent.EventTypeMask
        private let localHandler: ((NSEvent) -> NSEvent?)?
        private let globalHandler: ((NSEvent) -> Void)?

        /// Opaque tokens handed back by AppKit, one per installed monitor.
        /// Empty whenever the monitor is not listening.
        private var tokens: [Any] = []

        /// Where this monitor listens, implied by which handlers it carries.
        var scope: Scope {
            switch (localHandler, globalHandler) {
            case (.some, .some): .universal
            case (.some, .none): .local
            default: .global
            }
        }

        /// Whether the monitor is currently installed.
        var isRunning: Bool {
            !tokens.isEmpty
        }

        init(
            mask: NSEvent.EventTypeMask,
            localHandler: ((NSEvent) -> NSEvent?)?,
            globalHandler: ((NSEvent) -> Void)?
        ) {
            self.mask = mask
            self.localHandler = localHandler
            self.globalHandler = globalHandler
        }

        deinit {
            stop()
        }

        func start() {
            guard tokens.isEmpty else {
                return
            }

            var installed: [Any] = []

            if let localHandler {
                // The handler is captured directly rather than through self,
                // so a still-registered monitor cannot resurrect a dead
                // installation; the weak check turns it into a pass-through.
                let token = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                    guard self != nil else {
                        return event
                    }
                    return localHandler(event)
                }
                guard let token else {
                    EventMonitor.diagLog.error("Failed to create local event monitor for mask \(self.mask.rawValue)")
                    return
                }
                installed.append(token)
            }

            if let globalHandler {
                let token = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                    guard self != nil else {
                        return
                    }
                    globalHandler(event)
                }
                guard let token else {
                    EventMonitor.diagLog.error("Failed to create global event monitor for mask \(self.mask.rawValue)")
                    // Never leave half a universal monitor behind.
                    for token in installed {
                        NSEvent.removeMonitor(token)
                    }
                    return
                }
                installed.append(token)
            }

            tokens = installed
        }

        func stop() {
            guard !tokens.isEmpty else {
                return
            }
            let installed = tokens
            tokens = []
            for token in installed {
                NSEvent.removeMonitor(token)
            }
        }

        func restart() {
            stop()
            start()
        }
    }

    private let installation: OSAllocatedUnfairLock<Installation>

    /// Where this monitor watches for events.
    var scope: Scope {
        installation.withLock { $0.scope }
    }

    /// A Boolean value indicating whether the monitor is currently installed and running.
    var isRunning: Bool {
        installation.withLock { $0.isRunning }
    }

    private init(
        mask: NSEvent.EventTypeMask,
        localHandler: ((NSEvent) -> NSEvent?)?,
        globalHandler: ((NSEvent) -> Void)?
    ) {
        self.installation = OSAllocatedUnfairLock(
            initialState: Installation(
                mask: mask,
                localHandler: localHandler,
                globalHandler: globalHandler
            )
        )
    }

    /// Registers the underlying AppKit monitors, if they are not already up.
    func start() {
        installation.withLock { $0.start() }
    }

    /// Removes the underlying AppKit monitors, if any are up.
    func stop() {
        installation.withLock { $0.stop() }
    }

    /// Stops and restarts the monitor. Use this to recover from a potentially
    /// broken state where the underlying NSEvent monitor may have become invalid.
    func restart() {
        installation.withLock { installation in
            let scope = installation.scope
            EventMonitor.diagLog.info("Restarting \(scope) event monitor")
            installation.restart()
            if installation.isRunning {
                EventMonitor.diagLog.info("Successfully restarted \(scope) event monitor")
            } else {
                EventMonitor.diagLog.error("Failed to restart \(scope) event monitor")
            }
        }
    }

    /// Checks whether the monitor is running and restarts it if not.
    /// Returns true if the monitor is running after this call.
    @discardableResult
    func ensureRunning() -> Bool {
        installation.withLock { installation in
            if !installation.isRunning {
                let scope = installation.scope
                EventMonitor.diagLog.warning("\(scope) event monitor not running, attempting restart")
                installation.restart()
                if installation.isRunning {
                    EventMonitor.diagLog.info("Successfully restarted \(scope) event monitor")
                } else {
                    EventMonitor.diagLog.error("Failed to restart \(scope) event monitor after ensureRunning")
                }
            }
            return installation.isRunning
        }
    }
}

// MARK: - Making Monitors

extension EventMonitor {
    /// A monitor for events on their way to this app, able to rewrite or
    /// swallow them by returning a different event or nil.
    static func local(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        EventMonitor(mask: mask, localHandler: handler, globalHandler: nil)
    }

    /// A monitor for events on their way to other apps. These are observed
    /// only; the event stream is unaffected.
    static func global(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        EventMonitor(mask: mask, localHandler: nil, globalHandler: handler)
    }

    /// A monitor covering both this app and every other one, with a separate
    /// handler for each side.
    static func universal(
        for mask: NSEvent.EventTypeMask,
        localHandler: @escaping (NSEvent) -> NSEvent?,
        globalHandler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        EventMonitor(mask: mask, localHandler: localHandler, globalHandler: globalHandler)
    }

    /// A monitor covering both this app and every other one, driven by a
    /// single handler. Its return value is honored locally and discarded
    /// globally, where nothing can be changed anyway.
    static func universal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        EventMonitor(
            mask: mask,
            localHandler: handler,
            globalHandler: { _ = handler($0) }
        )
    }

    /// A monitor that only watches, in whichever scope is asked for. Local
    /// events are always forwarded unchanged.
    static func passive(
        for mask: NSEvent.EventTypeMask,
        scope: Scope,
        handler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        let observing: (NSEvent) -> NSEvent? = { event in
            handler(event)
            return event
        }
        return switch scope {
        case .local:
            EventMonitor(mask: mask, localHandler: observing, globalHandler: nil)
        case .global:
            EventMonitor(mask: mask, localHandler: nil, globalHandler: handler)
        case .universal:
            EventMonitor(mask: mask, localHandler: observing, globalHandler: handler)
        }
    }
}

// MARK: - Making Monitors That Are Already Listening

extension EventMonitor {
    /// Starts monitor and hands it straight back, so the start… factories
    /// can stay one-liners.
    private static func listening(_ monitor: EventMonitor) -> EventMonitor {
        monitor.start()
        return monitor
    }

    @discardableResult
    static func startGlobal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        listening(global(for: mask, handler: handler))
    }

    @discardableResult
    static func startUniversal(
        for mask: NSEvent.EventTypeMask,
        localHandler: @escaping (NSEvent) -> NSEvent?,
        globalHandler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        listening(universal(for: mask, localHandler: localHandler, globalHandler: globalHandler))
    }

    @discardableResult
    static func startPassive(
        for mask: NSEvent.EventTypeMask,
        scope: Scope,
        handler: @escaping (NSEvent) -> Void
    ) -> EventMonitor {
        listening(passive(for: mask, scope: scope, handler: handler))
    }
}

// MARK: - Combine

extension EventMonitor {
    /// Turns a passively observed slice of the event stream into a Combine
    /// publisher. Each subscription installs its own monitor and tears it
    /// down again on cancellation.
    struct EventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        /// Picks out the events to republish.
        let mask: NSEvent.EventTypeMask

        /// Where those events are watched for.
        let scope: EventMonitor.Scope

        func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            subscriber.receive(
                subscription: EventSubscription(mask: mask, scope: scope, subscriber: subscriber)
            )
        }
    }

    /// A Combine publisher for the events this monitor would observe.
    ///
    /// - Parameters:
    ///   - events: Picks out the events to republish.
    ///   - scope: Where to watch for them.
    static func publish(events: NSEvent.EventTypeMask, scope: Scope) -> EventPublisher {
        EventPublisher(mask: events, scope: scope)
    }
}

extension EventMonitor.EventPublisher {
    /// Feeds a passive EventMonitor into one Combine subscriber.
    ///
    /// The subscriber sits in a separate Sink object so that the monitor's
    /// closure can reference it weakly. The subscription owns the monitor, so
    /// a strong capture would form a cycle and keep both alive after cancel().
    private final class EventSubscription<S: Subscriber>: Subscription
        where S.Input == Output, S.Failure == Failure
    {
        private final class Sink {
            private let subscriber: S

            init(_ subscriber: S) {
                self.subscriber = subscriber
            }

            func send(_ event: NSEvent) {
                _ = subscriber.receive(event)
            }
        }

        private let monitor: EventMonitor
        private var sink: Sink?

        init(mask: NSEvent.EventTypeMask, scope: EventMonitor.Scope, subscriber: S) {
            let sink = Sink(subscriber)
            self.sink = sink
            self.monitor = .startPassive(for: mask, scope: scope) { [weak sink] event in
                sink?.send(event)
            }
        }

        func request(_: Subscribers.Demand) {
            // Intentionally empty: AppKit pushes events as they occur, so this passive monitor cannot honor Combine backpressure.
        }

        func cancel() {
            sink = nil
            monitor.stop()
        }
    }
}
