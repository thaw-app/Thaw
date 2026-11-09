//
//  RetitleIdentityMemory.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin

/// Keeps an item's identifier-based identity when a read misses the identifier and falls back to its title.
/// A slot takes it back only when the same process lists the same number of items, so a changed set isn't relabelled.
public struct RetitleIdentityMemory: Sendable {
    /// One item's identity in a read, and whether it came from a stable identifier rather than the title.
    public struct Slot: Equatable, Sendable {
        public let identity: String
        public let isStable: Bool

        public init(_ identity: String, isStable: Bool) {
            self.identity = identity
            self.isStable = isStable
        }
    }

    private var lastSlots: [pid_t: (app: String?, slots: [Slot])] = [:]
    private var owners: [pid_t] = []
    private let capacity: Int

    public init(capacity: Int = 256) {
        self.capacity = capacity
    }

    /// The identities to use for slots, in order.
    /// - Parameter app: What names the app behind owner, such as its bundle identifier. macOS gives a
    ///   process identifier out again after its process ends, so memory kept under another app is not used.
    public mutating func resolve(owner: pid_t, app: String? = nil, slots: [Slot]) -> [String] {
        var resolved = slots
        if let (previousApp, previous) = lastSlots[owner], previousApp == app, previous.count == slots.count {
            for index in slots.indices where !slots[index].isStable && previous[index].isStable {
                let kept = previous[index].identity
                guard !resolved.contains(where: { $0.identity == kept }) else { continue }
                resolved[index] = previous[index]
            }
        }
        remember(resolved, for: owner, app: app)
        return resolved.map(\.identity)
    }

    /// The owner read last goes to the back, so the ones dropped at capacity are those not read for longest.
    private mutating func remember(_ slots: [Slot], for owner: pid_t, app: String?) {
        if lastSlots.updateValue((app, slots), forKey: owner) != nil {
            owners.removeAll { $0 == owner }
        }
        owners.append(owner)
        while owners.count > capacity {
            lastSlots.removeValue(forKey: owners.removeFirst())
        }
    }
}
