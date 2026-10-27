//
//  SavedSectionOrderMerge.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Splices closed apps from a saved section order back next to their old neighbours.
/// It keeps the list as linked nodes indexed by identifier, so the work grows with the input instead of its cube.
nonisolated struct SavedSectionOrderMerge {
    private var values: [String] = []
    private var next: [Int] = []
    private var previous: [Int] = []
    private var head = -1
    private var tail = -1
    /// The node of each identifier's first occurrence, which is where an anchor lookup lands.
    private var firstNode: [String: Int] = [:]

    private init(_ initial: [String]) {
        values.reserveCapacity(initial.count)
        for identifier in initial {
            append(identifier)
        }
    }

    /// See LayoutSolver.planSectionOrder for the placement rules.
    static func merge(
        currentInSection: [String],
        oldSavedForSection: [String],
        isOwnedElsewhere: (String) -> Bool
    ) -> [String] {
        var list = SavedSectionOrderMerge(currentInSection)
        let saved = oldSavedForSection

        var laterPositions: [String: [Int]] = [:]
        for (index, identifier) in saved.enumerated() {
            laterPositions[identifier, default: []].append(index)
        }
        // nextPresent[i] is the first index at or after i whose identifier is already in the section.
        var nextPresent = [Int](repeating: saved.count, count: saved.count + 1)
        for index in stride(from: saved.count - 1, through: 0, by: -1) {
            nextPresent[index] = list.contains(saved[index]) ? index : nextPresent[index + 1]
        }
        // Later copies of an identifier spliced in earlier become anchors too; kept as a min-heap of positions.
        var splicedCopies = MinHeap()
        var lastPresentBefore = -1

        for (oldIndex, savedUID) in saved.enumerated() {
            if list.contains(savedUID) {
                lastPresentBefore = oldIndex
                continue
            }
            if isOwnedElsewhere(savedUID) {
                continue
            }

            while let top = splicedCopies.peek, top <= oldIndex {
                splicedCopies.pop()
            }
            let forward = min(nextPresent[oldIndex + 1], splicedCopies.peek ?? saved.count)
            if forward < saved.count {
                list.insert(savedUID, before: saved[forward])
            } else if lastPresentBefore >= 0 {
                list.insert(savedUID, after: saved[lastPresentBefore])
            } else {
                list.append(savedUID)
            }
            lastPresentBefore = oldIndex
            for position in laterPositions[savedUID] ?? [] where position > oldIndex {
                splicedCopies.push(position)
            }
        }

        return list.ordered()
    }

    private func contains(_ identifier: String) -> Bool {
        firstNode[identifier] != nil
    }

    private mutating func makeNode(_ identifier: String) -> Int {
        let node = values.count
        values.append(identifier)
        next.append(-1)
        previous.append(-1)
        if firstNode[identifier] == nil {
            firstNode[identifier] = node
        }
        return node
    }

    private mutating func append(_ identifier: String) {
        let node = makeNode(identifier)
        if tail >= 0 {
            next[tail] = node
            previous[node] = tail
        } else {
            head = node
        }
        tail = node
    }

    private mutating func insert(_ identifier: String, before anchor: String) {
        guard let anchorNode = firstNode[anchor] else {
            append(identifier)
            return
        }
        let node = makeNode(identifier)
        let before = previous[anchorNode]
        previous[node] = before
        next[node] = anchorNode
        previous[anchorNode] = node
        if before >= 0 {
            next[before] = node
        } else {
            head = node
        }
    }

    private mutating func insert(_ identifier: String, after anchor: String) {
        guard let anchorNode = firstNode[anchor] else {
            append(identifier)
            return
        }
        let node = makeNode(identifier)
        let after = next[anchorNode]
        next[node] = after
        previous[node] = anchorNode
        next[anchorNode] = node
        if after >= 0 {
            previous[after] = node
        } else {
            tail = node
        }
    }

    private func ordered() -> [String] {
        var result = [String]()
        result.reserveCapacity(values.count)
        var node = head
        while node >= 0 {
            result.append(values[node])
            node = next[node]
        }
        return result
    }
}

/// A small binary min-heap of positions.
private nonisolated struct MinHeap {
    private var storage: [Int] = []

    var peek: Int? {
        storage.first
    }

    mutating func push(_ value: Int) {
        storage.append(value)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child] < storage[parent] else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() {
        guard !storage.isEmpty else { return }
        storage.swapAt(0, storage.count - 1)
        storage.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < storage.count, storage[left] < storage[smallest] {
                smallest = left
            }
            if right < storage.count, storage[right] < storage[smallest] {
                smallest = right
            }
            guard smallest != parent else { return }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
