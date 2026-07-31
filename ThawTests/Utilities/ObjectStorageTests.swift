//
//  ObjectStorageTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers ``ObjectStorage``, the Objective-C associated-object wrapper used to
/// hang extra state off framework classes the app does not own.
///
/// Two properties carry the weight here and neither is visible from a call
/// site. The first is key identity: the lookup key is the storage instance's
/// own address, so two storages of the same `Value` type must not read each
/// other's entries — if that ever regressed, unrelated pieces of the app would
/// silently share a slot. The second is the strong/weak split: `set(_:for:)`
/// retains, `weakSet(_:for:)` boxes the value in a private `WeakReference` so
/// the association does not extend the value's lifetime. Both are lifetime
/// behavior, so the tests assert through `weak var` observers rather than
/// through the returned values.
@MainActor
@Suite("Object storage")
struct ObjectStorageTests {
    /// An object to hang associated values off of.
    private final class Host {}

    /// A reference-type value, so its lifetime can be observed.
    private final class Payload {
        let id: Int

        init(id: Int) {
            self.id = id
        }
    }

    // MARK: - Basic Storage

    @Test("A stored value reads back out")
    func storedValueReadsBackOut() {
        let storage = ObjectStorage<Int>()
        let host = Host()

        storage.set(42, for: host)

        #expect(storage.value(for: host) == 42)
    }

    @Test("An object that was never written to reads as nil")
    func unwrittenObjectReadsAsNil() {
        let storage = ObjectStorage<Int>()

        #expect(storage.value(for: Host()) == nil)
    }

    @Test("Setting nil clears a previously stored value")
    func settingNilClearsTheValue() {
        let storage = ObjectStorage<Int>()
        let host = Host()

        storage.set(42, for: host)
        storage.set(nil, for: host)

        #expect(storage.value(for: host) == nil)
    }

    @Test("Setting again overwrites rather than appends")
    func settingAgainOverwrites() {
        let storage = ObjectStorage<Int>()
        let host = Host()

        storage.set(1, for: host)
        storage.set(2, for: host)

        #expect(storage.value(for: host) == 2)
    }

    @Test("Values are scoped to the object they were set for")
    func valuesAreScopedToTheirObject() {
        let storage = ObjectStorage<Int>()
        let first = Host()
        let second = Host()

        storage.set(1, for: first)
        storage.set(2, for: second)

        #expect(storage.value(for: first) == 1)
        #expect(storage.value(for: second) == 2)
    }

    /// The lookup key is the storage instance's own address, so two storages
    /// of the same type must occupy separate slots on the same host.
    @Test("Two storages of the same type do not share a slot")
    func distinctStoragesUseDistinctKeys() {
        let first = ObjectStorage<Int>()
        let second = ObjectStorage<Int>()
        let host = Host()

        first.set(1, for: host)
        second.set(2, for: host)

        #expect(first.value(for: host) == 1)
        #expect(second.value(for: host) == 2)
    }

    @Test("A struct value round-trips through the Objective-C runtime")
    func structValueRoundTrips() {
        struct Box: Equatable {
            let name: String
            let count: Int
        }

        let storage = ObjectStorage<Box>()
        let host = Host()
        let box = Box(name: "hidden", count: 3)

        storage.set(box, for: host)

        #expect(storage.value(for: host) == box)
    }

    // MARK: - Reference Lifetime

    /// `set(_:for:)` documents a strong association: the value outlives every
    /// other reference to it for as long as the host is alive.
    @Test("set keeps its value alive after the local reference goes away")
    func setRetainsItsValue() {
        let storage = ObjectStorage<Payload>()
        let host = Host()
        weak var observed: Payload?

        do {
            let payload = Payload(id: 1)
            observed = payload
            storage.set(payload, for: host)
        }

        #expect(observed != nil)
        #expect(storage.value(for: host)?.id == 1)
    }

    /// `weakSet(_:for:)` boxes the value so the association does not extend its
    /// lifetime, and a read after deallocation degrades to nil rather than to a
    /// dangling reference.
    @Test("weakSet does not keep its value alive")
    func weakSetDoesNotRetainItsValue() {
        let storage = ObjectStorage<Payload>()
        let host = Host()
        weak var observed: Payload?

        var payload: Payload? = Payload(id: 1)
        observed = payload
        storage.weakSet(payload, for: host)
        #expect(storage.value(for: host) === payload)

        // End the payload's lifetime explicitly rather than relying on a
        // scope ending to release the last strong reference.
        payload = nil

        #expect(observed == nil)
        #expect(storage.value(for: host) == nil)
    }

    @Test("weakSet reads back through the box while the value is alive")
    func weakSetReadsBackThroughTheBox() {
        let storage = ObjectStorage<Payload>()
        let host = Host()
        let payload = Payload(id: 7)

        storage.weakSet(payload, for: host)

        #expect(storage.value(for: host)?.id == 7)
    }

    @Test("weakSet with nil clears a previously stored reference")
    func weakSetWithNilClearsTheValue() {
        let storage = ObjectStorage<Payload>()
        let host = Host()

        storage.weakSet(Payload(id: 1), for: host)
        storage.weakSet(nil, for: host)

        #expect(storage.value(for: host) == nil)
    }

    @Test("A strong write can be replaced by a weak one")
    func strongWriteCanBeReplacedByAWeakOne() {
        let storage = ObjectStorage<Payload>()
        let host = Host()
        weak var observed: Payload?

        var payload: Payload? = Payload(id: 1)
        observed = payload
        storage.set(payload, for: host)
        storage.weakSet(payload, for: host)

        // End the payload's lifetime explicitly rather than relying on a
        // scope ending to release the last strong reference.
        payload = nil

        #expect(observed == nil)
        #expect(storage.value(for: host) == nil)
    }
}
