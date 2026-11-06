import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Alphabetical item order")
@MainActor
struct AlphabeticalItemOrderTests {
    private func item(_ title: String, index: Int = 0) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("test.sort.\(title)"), title: title, instanceIndex: index),
            windowID: UInt32(index + 1), ownerPID: -1, sourcePID: nil, bounds: .zero,
            title: title, isOnScreen: true
        )
    }

    @Test func sortsBothDirectionsWithoutChangingMembership() {
        let items = [item("Zulu"), item("Alpha"), item("Beta")]
        let ascending = MenuBarItemAlphabeticalOrder.sorted(items, groups: [], direction: .ascending)
        let descending = MenuBarItemAlphabeticalOrder.sorted(items, groups: [], direction: .descending)
        #expect(ascending.map(\.title) == ["Alpha", "Beta", "Zulu"])
        #expect(descending.map(\.title) == ["Zulu", "Beta", "Alpha"])
        #expect(Set(ascending.map(\.uniqueIdentifier)) == Set(items.map(\.uniqueIdentifier)))
    }

    @Test func keepsGroupMembersInTheirOriginalOrder() {
        let items = [item("Zulu"), item("Beta"), item("Alpha")]
        let group = ResolvedGroup(origin: .user(UUID()), displayName: "A group", isCollapsed: false, memberIndices: [0, 2])
        let sorted = MenuBarItemAlphabeticalOrder.sorted(items, groups: [group], direction: .ascending)
        #expect(sorted.map(\.title) == ["Zulu", "Alpha", "Beta"])
    }

    @Test func equalNamesKeepTheirOrderInBothDirections() {
        let items = [item("Same", index: 1), item("Same", index: 2)]
        for direction in [MenuBarItemSortDirection.ascending, .descending] {
            #expect(MenuBarItemAlphabeticalOrder.sorted(items, groups: [], direction: direction).map(\.uniqueIdentifier) == items.map(\.uniqueIdentifier))
        }
    }

    @Test func fixedAnchorSeparatesSortableRuns() {
        let anchor = MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            windowID: 90, ownerPID: -1, sourcePID: nil, bounds: .zero,
            title: "Clock", isOnScreen: true
        )
        let items = [item("Zulu"), item("Beta"), anchor, item("Delta"), item("Alpha")]
        let sorted = MenuBarItemAlphabeticalOrder.sorted(items, groups: [], direction: .ascending)
        #expect(sorted.map(\.title) == ["Beta", "Zulu", "Clock", "Alpha", "Delta"])
    }
}
