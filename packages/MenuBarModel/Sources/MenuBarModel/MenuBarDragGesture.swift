//
//  MenuBarDragGesture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Transport-independent Command-drag sequencing. Posting is supplied by the
/// caller; this type neither touches the pointer nor knows private runtime APIs.
public struct MenuBarDragGesture: Sendable {
    public enum Phase: Sendable {
        case moved, down, dragged, up
    }

    public struct Metrics: Sendable {
        public var duration: Duration = .zero
        public var motionEvents: Int = 0
        public var maximumMotionGap: Duration = .zero
    }

    public var settleBeforePress: Duration
    public var pressHold: Duration
    public var travelDuration: Duration
    public var frameInterval: Duration
    public var holdBeforeRelease: Duration
    public var postRelease: Duration
    /// Limits catch-up after scheduler stalls to the old gesture's spatial
    /// increment. Late frames stretch the travel instead of jumping slots.
    public var maximumProgressStep: Double

    public init(
        settleBeforePress: Duration,
        pressHold: Duration,
        travelDuration: Duration,
        frameInterval: Duration = .seconds(1.0 / 60),
        holdBeforeRelease: Duration,
        postRelease: Duration = .zero,
        maximumProgressStep: Double = 1.0 / 20
    ) {
        precondition(travelDuration > .zero && frameInterval > .zero)
        precondition(maximumProgressStep > 0 && maximumProgressStep <= 1)
        self.settleBeforePress = settleBeforePress
        self.pressHold = pressHold
        self.travelDuration = travelDuration
        self.frameInterval = frameInterval
        self.holdBeforeRelease = holdBeforeRelease
        self.postRelease = postRelease
        self.maximumProgressStep = maximumProgressStep
    }

    /// Conservative holds. Shortening the holds and travel together caused
    /// missed slot crossings; increase sampling first.
    public static let held = Self(
        settleBeforePress: .milliseconds(200),
        pressHold: .milliseconds(40),
        travelDuration: .milliseconds(800),
        holdBeforeRelease: .milliseconds(300)
    )

    /// Runs on the caller's isolation, with an injectable monotonic clock and
    /// sleep for deterministic tests. A failed/cancelled gesture attempts a
    /// release at the last accepted point, never at the intended destination.
    /// Cleanup posting must accept mouse-up even when the task is cancelled.
    public func perform(
        from start: CGPoint,
        to end: CGPoint,
        isolation _: isolated (any Actor)? = #isolation,
        now: () -> Duration,
        sleep: (Duration) async throws -> Void,
        post: (Phase, CGPoint) throws -> Void
    ) async throws -> Metrics {
        // Properties are mutable for timing experiments; validate at use too.
        precondition(travelDuration > .zero && frameInterval > .zero)
        precondition(maximumProgressStep > 0 && maximumProgressStep <= 1)
        func pause(_ duration: Duration) async throws {
            try Task.checkCancellation()
            if duration > .zero {
                try await sleep(duration)
            }
            try Task.checkCancellation()
        }

        let began = now()
        var metrics = Metrics()
        var pressed = false
        var lastPoint = start
        defer {
            if pressed {
                try? post(.up, lastPoint)
            }
        }

        try Task.checkCancellation()
        try post(.moved, start)
        try await pause(settleBeforePress)
        try post(.down, start)
        pressed = true
        try await pause(pressHold)

        var motionStart = now()
        var lastMotion = motionStart
        var nextFrame = motionStart + frameInterval
        var progress = 0.0
        while progress < 1 {
            try await pause(max(.zero, nextFrame - now()))
            let instant = now()
            let desired = min(1, max(0, (instant - motionStart) / travelDuration))
            let next = min(desired, progress + maximumProgressStep)
            // A missed deadline never triggers a burst of catch-up events.
            // If the spatial bound held us back, give that remaining travel
            // its own time rather than accumulating debt on every frame.
            if next < desired {
                motionStart = instant - travelDuration * next
            }
            progress = next
            let point = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            try post(.dragged, point)
            lastPoint = point
            metrics.motionEvents += 1
            metrics.maximumMotionGap = max(metrics.maximumMotionGap, instant - lastMotion)
            lastMotion = instant
            nextFrame += frameInterval
            if nextFrame <= now() {
                nextFrame = now() + frameInterval
            }
            nextFrame = min(nextFrame, motionStart + travelDuration)
        }

        try await pause(holdBeforeRelease)
        try post(.up, end)
        pressed = false
        try await pause(postRelease)
        metrics.duration = now() - began
        return metrics
    }
}
