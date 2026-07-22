//
//  RunLoopLocalEventMonitor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import os.lock

final nonisolated class RunLoopLocalEventMonitor {
    private let runLoop = CFRunLoopGetCurrent()
    private let mask: NSEvent.EventTypeMask
    private let mode: RunLoop.Mode
    private let handler: @Sendable (NSEvent) -> NSEvent?
    private let observer: CFRunLoopObserver?

    init(
        mask: NSEvent.EventTypeMask,
        mode: RunLoop.Mode,
        handler: @escaping @Sendable (_ event: NSEvent) -> NSEvent?
    ) {
        self.mask = mask
        self.mode = mode
        self.handler = handler
        let capturedMask = mask
        let capturedHandler = handler
        let obs = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeSources.rawValue,
            true,
            0
        ) { _, _ in
            let events = Self.drainMainRunLoop()

            for event in events {
                var handledEvent: NSEvent?

                if !capturedMask.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)) {
                    handledEvent = event
                } else if let eventFromHandler = capturedHandler(event) {
                    handledEvent = eventFromHandler
                }

                guard let handledEvent else {
                    continue
                }

                Self.postEvent(handledEvent, atStart: false)
            }
        }
        self.observer = obs
    }

    private static nonisolated var sharedApp: NSApplication {
        let sel = #selector(getter: NSApplication.shared)
        typealias SharedImp = @convention(c) (AnyClass, Selector) -> NSApplication
        let imp = unsafeBitCast(NSApplication.self.method(for: sel), to: SharedImp.self)
        return imp(NSApplication.self, sel)
    }

    private static nonisolated func drainMainRunLoop() -> [NSEvent] {
        var events = [NSEvent]()
        let app = sharedApp
        let nextSel = #selector(NSApplication.nextEvent(matching:until:inMode:dequeue:))
        typealias NextImp = @convention(c) (AnyObject, Selector, NSEvent.EventTypeMask, Date?, RunLoop.Mode, Bool) -> NSEvent?
        let nextImp = unsafeBitCast(app.method(for: nextSel), to: NextImp.self)
        while let event = nextImp(app, nextSel, .any, nil, .default, true) {
            events.append(event)
        }
        return events
    }

    private static nonisolated func postEvent(_ event: NSEvent, atStart: Bool) {
        let app = sharedApp
        let sel = #selector(NSApplication.postEvent(_:atStart:))
        typealias PostImp = @convention(c) (AnyObject, Selector, NSEvent, Bool) -> Void
        let postImp = unsafeBitCast(app.method(for: sel), to: PostImp.self)
        postImp(app, sel, event, atStart)
    }

    deinit {
        stop()
    }

    func start() {
        CFRunLoopAddObserver(
            runLoop,
            observer,
            CFRunLoopMode(mode.rawValue as CFString)
        )
    }

    func stop() {
        CFRunLoopRemoveObserver(
            runLoop,
            observer,
            CFRunLoopMode(mode.rawValue as CFString)
        )
    }
}

extension RunLoopLocalEventMonitor {
    struct RunLoopLocalEventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        let mask: NSEvent.EventTypeMask
        let mode: RunLoop.Mode

        func receive(subscriber: some Subscriber<Output, Failure> & Sendable) {
            let subscription = RunLoopLocalEventSubscription(mask: mask, mode: mode, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }

    static func publisher(for mask: NSEvent.EventTypeMask, mode: RunLoop.Mode) -> RunLoopLocalEventPublisher {
        RunLoopLocalEventPublisher(mask: mask, mode: mode)
    }
}

extension RunLoopLocalEventMonitor.RunLoopLocalEventPublisher {
    /// `mask`/`mode` are immutable value-type `let`s. `box`'s mutable state is
    /// behind its own `OSAllocatedUnfairLock` (see `SubscriberBox` below).
    /// `monitor` is a `let` reference whose only mutation entry points,
    /// `start()`/`stop()`, wrap `CFRunLoopAddObserver`/`CFRunLoopRemoveObserver`,
    /// which are documented thread-safe by CoreFoundation — `RunLoopLocalEventMonitor`
    /// itself doesn't need to be `Sendable` for that to be safe.
    private final nonisolated class RunLoopLocalEventSubscription<S: Subscriber<Output, Failure> & Sendable>: Subscription, @unchecked Sendable {
        private final nonisolated class SubscriberBox: Sendable {
            /// `OSAllocatedUnfairLock.withLock` requires a `Sendable` closure.
            /// The callback is synchronous, so the event cannot outlive or cross
            /// an isolation boundary through this wrapper.
            private nonisolated struct SynchronousEvent: @unchecked Sendable {
                let value: NSEvent
            }

            private let subscriber: OSAllocatedUnfairLock<S?>

            init(_ subscriber: S) {
                self.subscriber = OSAllocatedUnfairLock(initialState: subscriber)
            }

            func receive(_ event: NSEvent) {
                let event = SynchronousEvent(value: event)
                subscriber.withLock { _ = $0?.receive(event.value) }
            }

            func cancel() {
                subscriber.withLock { $0 = nil }
            }
        }

        let mask: NSEvent.EventTypeMask
        let mode: RunLoop.Mode
        private let box: SubscriberBox
        private let monitor: RunLoopLocalEventMonitor

        init(mask: NSEvent.EventTypeMask, mode: RunLoop.Mode, subscriber: S) {
            self.mask = mask
            self.mode = mode
            let box = SubscriberBox(subscriber)
            self.box = box
            let monitor = RunLoopLocalEventMonitor(mask: mask, mode: mode) { [weak box] event in
                box?.receive(event)
                return event
            }
            self.monitor = monitor
            monitor.start()
        }

        func request(_: Subscribers.Demand) {
            // Backpressure is not applicable — events are pushed by the run loop regardless of demand.
        }

        func cancel() {
            monitor.stop()
            box.cancel()
        }
    }
}
