//
//  SourcePIDSeedStore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// One exact launch of a process.
///
/// macOS reuses PIDs, so the launch date tells the original owner apart from
/// a later process with the same PID.
nonisolated struct ProcessGeneration: Codable, Equatable, Hashable {
    let pid: pid_t
    let launchDate: Date
}

/// The current identity and exact generation of a running process.
nonisolated struct SourceProcessIdentity: Equatable {
    let generation: ProcessGeneration
    let bundleIdentifier: String?
    let processName: String?
}

/// Stable-enough evidence that a numeric window ID still describes the same
/// hosted status-item window.
///
/// Window IDs are recycled; this rejects reuse within one host launch.
/// Horizontal position is excluded because Thaw moves items.
nonisolated struct SourcePIDWindowFingerprint: Codable, Equatable {
    private static let pointsPerUnit: CGFloat = 8

    let title: String?
    let ownerName: String?
    let layer: Int
    let minYUnits: Int
    let widthUnits: Int
    let heightUnits: Int

    init(window: WindowInfo) {
        self.title = window.title
        self.ownerName = window.ownerName
        self.layer = window.layer
        self.minYUnits = Self.units(window.bounds.minY)
        self.widthUnits = Self.units(window.bounds.width)
        self.heightUnits = Self.units(window.bounds.height)
    }

    private static func units(_ value: CGFloat) -> Int {
        Int((value * pointsPerUnit).rounded())
    }
}

/// A source-process attribution remembered for a menu bar window.
///
/// On macOS 26 the Accessibility resolver is slow to warm up, and item
/// windows outlive Thaw, so a seed bridges the next launch. Accepted only
/// while host, fingerprint, source process, and age all match; never
/// replaces a fresh resolution.
nonisolated struct SourcePIDSeed: Codable, Equatable {
    let windowID: CGWindowID
    let windowOwnerGeneration: ProcessGeneration
    let windowFingerprint: SourcePIDWindowFingerprint
    let sourceGeneration: ProcessGeneration
    let bundleIdentifier: String?
    let processName: String?
    let capturedAt: Date

    var pid: pid_t {
        sourceGeneration.pid
    }

    /// Whether two records identify the same observed source/window lifetime.
    /// Capture time is freshness metadata, not part of the incarnation.
    func describesSameIncarnation(as other: SourcePIDSeed) -> Bool {
        windowID == other.windowID &&
            windowOwnerGeneration == other.windowOwnerGeneration &&
            windowFingerprint == other.windowFingerprint &&
            sourceGeneration == other.sourceGeneration &&
            bundleIdentifier == other.bundleIdentifier &&
            processName == other.processName
    }
}

nonisolated enum SourcePIDSeedStore {
    static let defaultsKey = "MenuBarItemManager.sourcePIDSeeds"

    /// Bounded so a recycled, same-shaped window ID can't look current forever.
    static let maximumSeedAge: TimeInterval = 5 * 60

    /// Avoids rewriting defaults every pass. Well below ``maximumSeedAge``.
    static let seedRefreshInterval: TimeInterval = 60

    /// A launch handoff can briefly show two Control Center processes, and
    /// `runningApplications` has no ordering contract, so pick the newest.
    static func newestGeneration(in generations: [ProcessGeneration]) -> ProcessGeneration? {
        generations.max { lhs, rhs in
            if lhs.launchDate == rhs.launchDate {
                return lhs.pid < rhs.pid
            }
            return lhs.launchDate < rhs.launchDate
        }
    }

    static func currentControlCenterGeneration() -> ProcessGeneration? {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: MenuBarItemTag.Namespace.controlCenter.description
        )
        return newestGeneration(in: applications.compactMap { application in
            guard !application.isTerminated, let launchDate = application.launchDate else { return nil }
            return ProcessGeneration(
                pid: application.processIdentifier,
                launchDate: launchDate
            )
        })
    }

    /// Whether the current source process is the exact launch named by a seed.
    private static func sourceIsTrustworthy(
        _ seed: SourcePIDSeed,
        liveIdentity: SourceProcessIdentity?
    ) -> Bool {
        guard
            let liveIdentity,
            liveIdentity.generation == seed.sourceGeneration
        else { return false }
        if let bundleIdentifier = seed.bundleIdentifier {
            return liveIdentity.bundleIdentifier == bundleIdentifier
        }
        guard let processName = seed.processName, !processName.isEmpty else { return false }
        return liveIdentity.bundleIdentifier == nil && liveIdentity.processName == processName
    }

    /// Whether a seed still names this exact, recent hosted window and source
    /// process under the currently selected Control Center generation.
    static func isTrustworthy(
        _ seed: SourcePIDSeed,
        for window: WindowInfo,
        currentControlCenterGeneration: ProcessGeneration,
        now: Date = .now,
        maximumAge: TimeInterval = maximumSeedAge,
        liveIdentity: (pid_t) -> SourceProcessIdentity?
    ) -> Bool {
        let age = now.timeIntervalSince(seed.capturedAt)
        guard age >= 0, age <= maximumAge else { return false }

        let ownerIdentity = liveIdentity(window.ownerPID)
        guard
            seed.windowID == window.windowID,
            seed.windowOwnerGeneration == currentControlCenterGeneration,
            seed.windowOwnerGeneration.pid == window.ownerPID,
            ownerIdentity?.generation == seed.windowOwnerGeneration,
            ownerIdentity?.bundleIdentifier == MenuBarItemTag.Namespace.controlCenter.description,
            seed.windowFingerprint == SourcePIDWindowFingerprint(window: window)
        else { return false }
        return sourceIsTrustworthy(seed, liveIdentity: liveIdentity(seed.pid))
    }

    /// Creates one useful seed per freshly resolved, non-control item window.
    static func seeds(
        from items: [MenuBarItem],
        excluding excludedWindowIDs: Set<CGWindowID> = [],
        windowsByID: [CGWindowID: WindowInfo],
        currentControlCenterGeneration: ProcessGeneration,
        capturedAt: Date = .now,
        identity: (pid_t) -> SourceProcessIdentity?
    ) -> [SourcePIDSeed] {
        var seen = Set<CGWindowID>()
        var attemptedPIDs = Set<pid_t>()
        var identities = [pid_t: SourceProcessIdentity]()

        func cachedIdentity(for pid: pid_t) -> SourceProcessIdentity? {
            if let cached = identities[pid] {
                return cached
            }
            guard attemptedPIDs.insert(pid).inserted, let resolved = identity(pid) else {
                return nil
            }
            identities[pid] = resolved
            return resolved
        }

        return items.compactMap { item in
            guard
                !item.isControlItem,
                !excludedWindowIDs.contains(item.windowID),
                let window = windowsByID[item.windowID],
                let pid = item.sourcePID,
                seen.insert(item.windowID).inserted,
                let sourceIdentity = cachedIdentity(for: pid),
                let ownerIdentity = cachedIdentity(for: item.ownerPID),
                ownerIdentity.generation == currentControlCenterGeneration,
                ownerIdentity.bundleIdentifier == MenuBarItemTag.Namespace.controlCenter.description,
                sourceIdentity.bundleIdentifier != nil || sourceIdentity.processName?.isEmpty == false
            else { return nil }

            return SourcePIDSeed(
                windowID: item.windowID,
                windowOwnerGeneration: ownerIdentity.generation,
                windowFingerprint: SourcePIDWindowFingerprint(window: window),
                sourceGeneration: sourceIdentity.generation,
                bundleIdentifier: sourceIdentity.bundleIdentifier,
                processName: sourceIdentity.processName,
                capturedAt: capturedAt
            )
        }
        .sorted { $0.windowID < $1.windowID }
    }

    /// Restores only unresolved entries whose current host, window
    /// fingerprint, and source process match a recent seed exactly.
    ///
    /// - Returns: The seed used for each restored window.
    static func apply(
        seeds: [CGWindowID: SourcePIDSeed],
        to pids: inout [pid_t?],
        windows: [WindowInfo],
        currentControlCenterGeneration: ProcessGeneration,
        now: Date = .now,
        maximumAge: TimeInterval = maximumSeedAge,
        liveIdentity: (pid_t) -> SourceProcessIdentity?
    ) -> [CGWindowID: SourcePIDSeed] {
        var applied = [CGWindowID: SourcePIDSeed]()
        var attemptedPIDs = Set<pid_t>()
        var identities = [pid_t: SourceProcessIdentity]()

        func cachedIdentity(for pid: pid_t) -> SourceProcessIdentity? {
            if let cached = identities[pid] {
                return cached
            }
            guard attemptedPIDs.insert(pid).inserted, let resolved = liveIdentity(pid) else {
                return nil
            }
            identities[pid] = resolved
            return resolved
        }

        for (index, window) in windows.enumerated() where index < pids.count && pids[index] == nil {
            guard
                let seed = seeds[window.windowID],
                isTrustworthy(
                    seed,
                    for: window,
                    currentControlCenterGeneration: currentControlCenterGeneration,
                    now: now,
                    maximumAge: maximumAge,
                    liveIdentity: cachedIdentity(for:)
                )
            else { continue }
            pids[index] = seed.pid
            applied[window.windowID] = seed
        }
        return applied
    }

    /// Chooses the current resolver result unless a generation-, window-, and
    /// age-validated in-session baseline proves that result is a transient
    /// miss or stale alternate match.
    static func reconciledSourcePID(
        currentPID: pid_t?,
        previous: SourcePIDSeed?,
        for window: WindowInfo,
        currentControlCenterGeneration: ProcessGeneration,
        now: Date = .now,
        liveIdentity: (pid_t) -> SourceProcessIdentity?
    ) -> pid_t? {
        guard
            let previous,
            currentPID != previous.pid,
            isTrustworthy(
                previous,
                for: window,
                currentControlCenterGeneration: currentControlCenterGeneration,
                now: now,
                liveIdentity: liveIdentity
            )
        else { return currentPID }
        return previous.pid
    }

    /// Carries a confirmed in-session baseline across a provisional resolver
    /// miss without promoting the persisted seed into a new baseline.
    /// Vanished, invalid, or different incarnations are omitted.
    static func mergedConfirmedBaselines(
        previous: [CGWindowID: SourcePIDSeed],
        fresh: [SourcePIDSeed],
        provisional: [CGWindowID: SourcePIDSeed]
    ) -> [CGWindowID: SourcePIDSeed] {
        var merged = Dictionary(
            uniqueKeysWithValues: fresh.map { ($0.windowID, $0) }
        )
        for (windowID, provisionalSeed) in provisional where merged[windowID] == nil {
            guard
                let previousSeed = previous[windowID],
                previousSeed.describesSameIncarnation(as: provisionalSeed)
            else { continue }
            merged[windowID] = previousSeed
        }
        return merged
    }

    /// Persists fresh confirmations alongside only the provisional entries
    /// independently validated in this enumeration. Fresh evidence wins.
    static func mergedPersistedSeeds(
        fresh: [SourcePIDSeed],
        provisional: [CGWindowID: SourcePIDSeed]
    ) -> [SourcePIDSeed] {
        var merged = provisional
        for seed in fresh {
            merged[seed.windowID] = seed
        }
        return merged.values.sorted { $0.windowID < $1.windowID }
    }

    /// Reuses a recent capture timestamp for an unchanged incarnation so the
    /// cache doesn't rewrite identical seeds every pass.
    static func coalescingCaptureTimes(
        proposed: [SourcePIDSeed],
        previous: [CGWindowID: SourcePIDSeed],
        now: Date = .now,
        refreshInterval: TimeInterval = seedRefreshInterval
    ) -> [SourcePIDSeed] {
        proposed.map { seed in
            guard
                let oldSeed = previous[seed.windowID],
                seed.describesSameIncarnation(as: oldSeed)
            else { return seed }

            let age = now.timeIntervalSince(oldSeed.capturedAt)
            return age >= 0 && age < refreshInterval ? oldSeed : seed
        }
        .sorted { $0.windowID < $1.windowID }
    }

    static func liveIdentity(of pid: pid_t) -> SourceProcessIdentity? {
        guard
            let app = NSRunningApplication(processIdentifier: pid),
            !app.isTerminated,
            let launchDate = app.launchDate
        else { return nil }
        return SourceProcessIdentity(
            generation: ProcessGeneration(pid: pid, launchDate: launchDate),
            bundleIdentifier: app.bundleIdentifier,
            processName: app.localizedName
        )
    }

    static func load(from defaults: UserDefaults) -> [CGWindowID: SourcePIDSeed] {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let seeds = try? JSONDecoder().decode([SourcePIDSeed].self, from: data)
        else { return [:] }
        return Dictionary(seeds.map { ($0.windowID, $0) }, uniquingKeysWith: { _, last in last })
    }

    static func save(_ seeds: [SourcePIDSeed], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(seeds) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
