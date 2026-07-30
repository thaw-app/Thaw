//
//  RunLoopLocalEventMonitor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
@preconcurrency import Combine

final class RunLoopLocalEventMonitor {
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
    private final class RunLoopLocalEventSubscription<S: Subscriber<Output, Failure> & Sendable>: Subscription, @unchecked Sendable {
        let mask: NSEvent.EventTypeMask
        let mode: RunLoop.Mode
        private var subscriber: S?

        private lazy var monitor = RunLoopLocalEventMonitor(mask: mask, mode: mode) { [weak self] event in
            _ = self?.subscriber?.receive(event)
            return event
        }

        init(mask: NSEvent.EventTypeMask, mode: RunLoop.Mode, subscriber: S) {
            self.mask = mask
            self.mode = mode
            self.subscriber = subscriber
            self.monitor.start()
        }

        func request(_: Subscribers.Demand) {
            // Backpressure is not applicable — events are pushed by the run loop regardless of demand.
        }

        func cancel() {
            monitor.stop()
            subscriber = nil
        }
    }
}
