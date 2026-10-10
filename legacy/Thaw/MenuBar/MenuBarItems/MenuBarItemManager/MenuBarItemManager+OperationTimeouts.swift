//
//  MenuBarItemManager+OperationTimeouts.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - Operation Timeouts

extension MenuBarItemManager {
    /// A budget, not a cost: the response poll returns as soon as the item moves.
    /// 100 ms was too little under contention, worst at startup (#687).
    private func getDefaultMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if item.isBentoBox {
            // Control Center groups respond a little slower.
            return .milliseconds(350)
        }
        return .milliseconds(250)
    }

    func getMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = moveOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultMoveOperationTimeout(for: item)
    }

    /// Growth is adopted as is; only shrinkage is smoothed. Smoothing growth
    /// too crept up too slowly to help (#687).
    ///
    /// Floor 75 ms, below which retry cascades start. Ceiling 1 s, past which
    /// the item is unresponsive rather than slow.
    static nonisolated func mergedMoveOperationTimeout(
        proposed: Duration,
        current: Duration
    ) -> Duration {
        let next = proposed > current ? proposed : (proposed + current) / 2
        return next.clamped(min: .milliseconds(75), max: .seconds(1))
    }

    /// Covers a single move's worst case: every attempt at the ceiling, four
    /// waits each, plus a 100 ms fallback. Never below 10 s, so a slow item
    /// can't outlast it and show the cursor mid-sequence.
    static nonisolated func cursorHideWatchdogTimeout(
        operationCeiling: Duration = .seconds(1),
        maxAttempts: Int = 8,
        fallbackPost: Duration = .milliseconds(100),
        floor: Duration = .seconds(10)
    ) -> Duration {
        // One millisecond is 10^15 attoseconds.
        let attosecondsPerMillisecond = 1_000_000_000_000_000.0
        let perAttemptComponents = operationCeiling.components
        let perAttemptMs = Double(perAttemptComponents.seconds) * 1000.0
            + Double(perAttemptComponents.attoseconds) / attosecondsPerMillisecond
        let attempts = max(1, maxAttempts)
        let fallbackMs = Double(fallbackPost.components.seconds) * 1000.0
            + Double(fallbackPost.components.attoseconds) / attosecondsPerMillisecond
        let floorMs = Double(floor.components.seconds) * 1000.0
            + Double(floor.components.attoseconds) / attosecondsPerMillisecond
        let totalMs = max(floorMs, perAttemptMs * Double(attempts) * 4 + fallbackMs)
        return .milliseconds(Int(totalMs.rounded(.up)))
    }

    func updateMoveOperationTimeout(_ timeout: Duration, for item: MenuBarItem) {
        moveOperationTimeouts[item.tag] = Self.mergedMoveOperationTimeout(
            proposed: timeout,
            current: getMoveOperationTimeout(for: item)
        )
    }

    func pruneMoveOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        moveOperationTimeouts = moveOperationTimeouts.filter { validTags.contains($0.key) }
    }

    private func getDefaultClickOperationTimeout(for item: MenuBarItem) -> Duration {
        // Slow apps with dynamic content.
        let slowAppBundleIDs = [
            "com.bitsplash.PasteNow",
            "com.charliemonroe.Downie-setapp",
            "com.if.Amphetamine",
            "com.hegenberg.BetterTouchTool",
            "net.matthewpalmer.Vanilla",
        ]

        let namespaceString = item.tag.namespace.description
        if slowAppBundleIDs.contains(where: { namespaceString.contains($0) }) {
            return .milliseconds(500) // Extra time for slow apps
        }

        return .milliseconds(350) // Default
    }

    func getClickOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = clickOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultClickOperationTimeout(for: item)
    }

    func updateClickOperationTimeout(_ duration: Duration, for item: MenuBarItem) {
        let current = getClickOperationTimeout(for: item)
        let average = (duration + current) / 2
        let clamped = average.clamped(min: .milliseconds(200), max: .milliseconds(1000))
        clickOperationTimeouts[item.tag] = clamped
        MenuBarItemManager.diagLog.debug("Updated click timeout for \(item.logString): \(Int(clamped.milliseconds))ms (measured: \(Int(duration.milliseconds))ms)")
    }

    func pruneClickOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        clickOperationTimeouts = clickOperationTimeouts.filter { validTags.contains($0.key) }
    }
}
