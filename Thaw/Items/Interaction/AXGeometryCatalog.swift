//
//  AXGeometryCatalog.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import ThawAXCore

/// Validates frames with their process and AX root; equal rectangles need not share an owner.
/// On-demand synchronous AX walks run on a private serial actor to avoid blocking MainActor or overlapping capture passes.
nonisolated enum AXGeometryCatalog {
    struct Entry: Sendable {
        let ownerPID: pid_t
        let itemIndex: Int
        let identityTitle: String?
        let frame: CGRect

        var isCollapsedThawDivider: Bool {
            // Zero-length dividers, and the visible control while its icon is
            // hidden, can still publish a 2-point AX frame that draws nothing.
            // The 3-point drag marker and expanded chevrons remain occluders.
            ownerPID == ProcessInfo.processInfo.processIdentifier
                && (identityTitle == MenuBarItemTag.hiddenControlItem.title
                    || identityTitle == MenuBarItemTag.alwaysHiddenControlItem.title
                    || identityTitle == MenuBarItemTag.visibleControlItem.title)
                && frame.width >= 0 && frame.width <= 2
        }
    }

    enum Match: Equatable {
        case frame(CGRect)
        case unavailable
        case ambiguous
    }

    static func identityTitle(
        namespace: MenuBarItemTag.Namespace,
        attributes: AXHelpers.MenuBarChildAttributes,
        descendants: [AXHelpers.MenuBarChildAttributes]
    ) -> String? {
        func nonEmpty(_ value: String?) -> String? {
            value.flatMap { $0.isEmpty ? nil : $0 }
        }
        func stableIdentifier(_ value: String?) -> String? {
            guard let value = nonEmpty(value), !value.contains(/^_NS:\d+$/) else { return nil }
            return value
        }
        let identifier = stableIdentifier(attributes.identifier)
            ?? descendants.compactMap { stableIdentifier($0.identifier) }.first
        let description = nonEmpty(attributes.accessibilityDescription)
            ?? descendants.compactMap { nonEmpty($0.accessibilityDescription) }.first
        let title = nonEmpty(attributes.title)
        if let legacyIdentity = MenuBarItemTag.legacySystemUIServerIdentity(
            namespace: namespace,
            identifier: identifier,
            accessibilityDescription: description,
            axTitle: title
        ) {
            return legacyIdentity
        }
        guard let display = title ?? description ?? identifier else { return nil }
        return MenuBarItemAXProvider.identityTitle(
            namespace: namespace,
            identifier: identifier,
            accessibilityDescription: description,
            displayTitle: display
        )
    }

    /// Keeps fallback numbering in AX child order, independent of on-screen order.
    static func rootIdentityTitle(
        namespace: MenuBarItemTag.Namespace,
        attributes: AXHelpers.MenuBarChildAttributes,
        descendants: [AXHelpers.MenuBarChildAttributes],
        maximumItemHeight: CGFloat,
        fallbackIndex: inout Int
    ) -> String? {
        if let identity = identityTitle(namespace: namespace, attributes: attributes, descendants: descendants) {
            return identity
        }
        // MenuBarAgent's unnamed extras are transition noise, not inventory items.
        guard namespace != .menuBarAgent,
              MenuBarItemAXProvider.itemFrame(attributes.frame, maximumHeight: maximumItemHeight) != nil
        else { return nil }
        let identity = MenuBarItemAXProvider.identityTitle(
            namespace: namespace,
            identifier: nil,
            accessibilityDescription: nil,
            displayTitle: "Item-\(fallbackIndex)"
        )
        fallbackIndex += 1
        return identity
    }

    static func match(ownerPID: pid_t, identityTitle: String, bounds: CGRect, in entries: [Entry]) -> Match {
        let owned = entries.filter { $0.ownerPID == ownerPID }
        let identified = owned.filter { $0.identityTitle == identityTitle }
        let roots = Set(owned.map(\.itemIndex))
        let selected: [Entry]
        if !identified.isEmpty {
            selected = identified
        } else if roots.count == 1, owned.allSatisfy({ $0.identityTitle == nil }) {
            selected = owned
        } else {
            return entries.contains(where: {
                !$0.isCollapsedThawDivider && significantlyOverlaps(bounds, $0.frame)
            }) ? .ambiguous : .unavailable
        }
        guard Set(selected.map(\.itemIndex)).count == 1, let root = selected.first else {
            return .ambiguous
        }
        // Include other owners even when their frames are byte-for-byte equal.
        // Only descendants of the selected AX root may repeat its rectangle.
        if entries.contains(where: {
            !$0.isCollapsedThawDivider
                && ($0.ownerPID != ownerPID || $0.itemIndex != root.itemIndex)
                && significantlyOverlaps(bounds, $0.frame)
        }) {
            return .ambiguous
        }
        guard let frame = frame(overlapping: bounds, in: selected.map(\.frame)) else { return .unavailable }
        return .frame(frame)
    }

    private static func significantlyOverlaps(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = lhs.intersection(rhs)
        guard !overlap.isNull, !overlap.isEmpty else { return false }
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        return smallerArea > 0 && overlap.width * overlap.height > smallerArea * minOverlapFraction
    }

    static func diagnosticSummary(ownerPID: pid_t, identityTitle: String, bounds: CGRect, in entries: [Entry]) -> String {
        let owned = entries.filter { $0.ownerPID == ownerPID }
        let identified = owned.filter { $0.identityTitle == identityTitle }
        let overlaps = entries.filter { !$0.isCollapsedThawDivider && significantlyOverlaps(bounds, $0.frame) }
        let roots = Set(owned.map(\.itemIndex))
        let reason: String = if identified.isEmpty, !(roots.count == 1 && owned.allSatisfy { $0.identityTitle == nil }) {
            owned.isEmpty ? "requested-owner-absent" : "identity-unresolved"
        } else if Set(identified.map(\.itemIndex)).count > 1 {
            "identity-shared-by-roots"
        } else {
            "overlapping-other-root"
        }
        // Prioritize occupied geometry, then include owned metadata if the
        // requested identity was absent. Never print an entire AX snapshot.
        let relevant = overlaps + owned.filter { !significantlyOverlaps(bounds, $0.frame) && !$0.frame.isEmpty }
        let details = relevant.prefix(6).map {
            "pid=\($0.ownerPID),root=\($0.itemIndex),identity=\(String(($0.identityTitle ?? "nil").prefix(100))),frame=\($0.frame)"
        }.joined(separator: "; ")
        return "reason=\(reason) requestedPID=\(ownerPID) requestedTitle=\(String(identityTitle.prefix(100))) " +
            "snapshotEntries=\(entries.count) ownedRoots=\(roots.count) identifiedEntries=\(identified.count) " +
            "overlappingEntries=\(overlaps.count) relevantTotal=\(relevant.count) entries=[\(details)]"
    }

    /// Messaging timeout applied to AX handles created here, so a
    /// non-responsive app can't block a snapshot indefinitely.
    private static nonisolated let messagingTimeout = AXPrimitives.defaultMessagingTimeout

    /// Budget is checked between reads; an in-flight read can overrun by its timeout.
    /// Missing entries stay unvalidated, forcing capture fallback rather than a trusted crop.
    private static nonisolated let snapshotBudget: Duration = .seconds(2)

    /// Maximum depth walked below each host's extras menu bar element.
    private static nonisolated let maxWalkDepth = 6

    /// Caps visits across all hosts to bound snapshot cost regardless of AX tree shape.
    private static nonisolated let maxElementsVisited = 512

    /// Require this fraction of the smaller rectangle's area; weaker correlations return nil rather than guessing.
    private static nonisolated let minOverlapFraction: CGFloat = 0.5

    /// Frames correlate host AX items with CG bounds; only PIDs and immutable results cross the actor boundary.
    /// The actor hop leaves the caller's executor, unlike nonisolated async with NonisolatedNonsendingByDefault.
    /// AppKit answers reads of Thaw's own elements in-process and is not thread-safe,
    /// so Thaw's own bar is walked on the main actor and every other host on the executor.
    static nonisolated func snapshot(hostProcessIdentifiers: [pid_t]) async -> [Entry] {
        let deadline = ContinuousClock.now + snapshotBudget
        let foreign = hostProcessIdentifiers.filter { !AXPrimitives.isOwnProcess($0) }
        var entriesByPID = await Dictionary(grouping: GeometryWalkExecutor.shared.snapshot(
            hostProcessIdentifiers: foreign,
            deadline: deadline
        ), by: \.ownerPID)
        for pid in hostProcessIdentifiers where AXPrimitives.isOwnProcess(pid) {
            entriesByPID[pid] = await MainActor.run {
                performSnapshot(hostProcessIdentifiers: [pid], deadline: deadline)
            }
        }
        return hostProcessIdentifiers.flatMap { entriesByPID[$0] ?? [] }
    }

    fileprivate static func performSnapshot(hostProcessIdentifiers: [pid_t], deadline: ContinuousClock.Instant) -> [Entry] {
        var results = [Entry]()
        var visited = 0

        for pid in hostProcessIdentifiers {
            guard canContinue(until: deadline), visited < maxElementsVisited else { break }
            guard let host = NSRunningApplication(processIdentifier: pid),
                  let app = AXHelpers.application(for: host)
            else { continue }
            guard canContinue(until: deadline),
                  let bar = AXHelpers.extrasMenuBar(for: app)
            else { continue }
            // Skip the macOS 27 extras-bar container: its frame matches its first child, causing an ambiguous nil match.
            let children = AXHelpers.children(for: bar)
            // Preserve root cardinality even if the read budget expires before
            // visiting every child. A partial walk must not invent a singleton.
            for itemIndex in children.indices {
                results.append(Entry(ownerPID: pid, itemIndex: itemIndex, identityTitle: nil, frame: .zero))
            }
            let itemHeightCeiling = MenuBarItemAXProvider.maxItemHeight(menuBarHeight: NSScreen.tallestCachedMenuBarHeight)
            var fallbackIndex = 0
            for (itemIndex, child) in children.enumerated() {
                guard canContinue(until: deadline), visited < maxElementsVisited else { break }
                child.setMessagingTimeout(messagingTimeout)
                let namespace = MenuBarItemAXProvider.namespace(forBundleIdentifier: host.bundleIdentifier)
                let attributes = AXHelpers.menuBarChildAttributes(for: child)
                var innerAttributes = [AXHelpers.MenuBarChildAttributes]()
                for inner in attributes.children {
                    guard canContinue(until: deadline),
                          visited + innerAttributes.count + 1 < maxElementsVisited else { break }
                    inner.setMessagingTimeout(messagingTimeout)
                    innerAttributes.append(AXHelpers.descendantAttributes(for: inner, includingChildren: true))
                }
                let identity = rootIdentityTitle(
                    namespace: namespace,
                    attributes: attributes,
                    descendants: innerAttributes,
                    maximumItemHeight: itemHeightCeiling,
                    fallbackIndex: &fallbackIndex
                )
                walk(
                    child,
                    ownerPID: pid,
                    itemIndex: itemIndex,
                    identityTitle: identity,
                    attributes: attributes,
                    childAttributes: innerAttributes,
                    depth: 1,
                    visited: &visited,
                    into: &results,
                    deadline: deadline
                )
            }
        }
        return results
    }

    private static func canContinue(until deadline: ContinuousClock.Instant) -> Bool {
        !Task.isCancelled && ContinuousClock.now < deadline
    }

    /// Depth-limited, element-capped walk collecting frames from element
    /// and its children.
    private static nonisolated func walk(
        _ element: AXElement,
        ownerPID: pid_t,
        itemIndex: Int,
        identityTitle: String?,
        attributes: AXHelpers.MenuBarChildAttributes? = nil,
        childAttributes: [AXHelpers.MenuBarChildAttributes]? = nil,
        depth: Int,
        visited: inout Int,
        into results: inout [Entry],
        deadline: ContinuousClock.Instant
    ) {
        guard depth <= maxWalkDepth, visited < maxElementsVisited else { return }
        guard canContinue(until: deadline) else { return }
        visited += 1

        element.setMessagingTimeout(messagingTimeout)

        let attributes = attributes ?? AXHelpers.descendantAttributes(
            for: element,
            includingChildren: depth < maxWalkDepth
        )
        // Clamped like discovery's item frames, so a crop is checked against the same rectangle.
        let ceiling = MenuBarItemAXProvider.maxItemHeight(menuBarHeight: NSScreen.tallestCachedMenuBarHeight)
        let frame = attributes.frame.map { AXPrimitives.itemFrame($0, maximumHeight: ceiling) ?? $0 } ?? .zero
        results.append(Entry(
            ownerPID: ownerPID,
            itemIndex: itemIndex,
            identityTitle: identityTitle,
            frame: frame
        ))

        guard depth < maxWalkDepth, canContinue(until: deadline) else { return }
        let children = attributes.children
        for (index, child) in children.enumerated() {
            guard visited < maxElementsVisited else { return }
            guard canContinue(until: deadline) else { return }
            walk(
                child,
                ownerPID: ownerPID,
                itemIndex: itemIndex,
                identityTitle: identityTitle,
                attributes: childAttributes.flatMap { index < $0.count ? $0[index] : nil },
                depth: depth + 1,
                visited: &visited,
                into: &results,
                deadline: deadline
            )
        }
    }

    /// Selects the greatest intersection exceeding minOverlapFraction of the smaller rectangle.
    /// Returns nil for no confident candidate or a tie between distinct frames.
    static nonisolated func frame(
        overlapping windowBounds: CGRect,
        in snapshot: [CGRect]
    ) -> CGRect? {
        var best: (frame: CGRect, area: CGFloat)?
        var bestIsTied = false

        for candidate in snapshot {
            let intersection = candidate.intersection(windowBounds)
            guard !intersection.isNull, !intersection.isEmpty else { continue }

            let intersectionArea = intersection.width * intersection.height
            let candidateArea = candidate.width * candidate.height
            let targetArea = windowBounds.width * windowBounds.height
            let smallerArea = min(candidateArea, targetArea)
            guard smallerArea > 0, intersectionArea > smallerArea * minOverlapFraction else { continue }

            if let current = best {
                if intersectionArea > current.area {
                    best = (candidate, intersectionArea)
                    bestIsTied = false
                } else if intersectionArea == current.area, candidate != current.frame {
                    // Distinct tied frames are ambiguous; equal frames from a root and descendant give the same geometry.
                    bestIsTied = true
                }
            } else {
                best = (candidate, intersectionArea)
                bestIsTied = false
            }
        }

        guard let best, !bestIsTied else { return nil }
        return best.frame
    }
}

/// The synchronous actor method cannot interleave walks at suspension points.
/// Awaiting it from MainActor frees the UI while AX requests are in flight.
private actor GeometryWalkExecutor {
    static let shared = GeometryWalkExecutor()

    func snapshot(hostProcessIdentifiers: [pid_t], deadline: ContinuousClock.Instant) -> [AXGeometryCatalog.Entry] {
        AXGeometryCatalog.performSnapshot(hostProcessIdentifiers: hostProcessIdentifiers, deadline: deadline)
    }
}
