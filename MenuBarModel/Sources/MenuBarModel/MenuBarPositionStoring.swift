//
//  MenuBarPositionStoring.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// A parsed status: key from the preferred-position table.
public struct PositionStatusKey: Equatable, Sendable {
    /// The owning app's bundle identifier, or the display name it registered
    /// under. The key alone cannot say which of the two it holds.
    public let owner: String

    /// The item identifier, matching the item's tag.title.
    public let identifier: String

    public init(owner: String, identifier: String) {
        self.owner = owner
        self.identifier = identifier
    }
}

/// The preferred-position table the menu bar host sorts by, and the rules for
/// reading it.
///
/// Writes here are cursor-free and work while the bar is concealed, so move
/// paths prefer them over the drag engine. The host rewrites the file
/// continuously, so callers re-read before writing.
@MainActor
public protocol MenuBarPositionStoring: Sendable {
    // MARK: Reading

    /// The host's current sort weights, keyed as the host keys them.
    func currentPositions() -> [String: Int]

    /// The key item is stored under, or nil when the table has no slot for it.
    ///
    /// Resolution needs the surrounding context because a key names its owner
    /// ambiguously: existingKeys and liveItems are what disambiguate an
    /// item from a sibling registered under the same owner.
    func resolveKey(
        for item: MenuBarItem,
        existingKeys: [String],
        positions: [String: Int],
        liveItems: [MenuBarItem]
    ) -> String?

    /// Parses status:<owner>::<identifier>, or nil when the key is a
    /// module: key or otherwise not in that form.
    func parseStatusKey(_ key: String) -> PositionStatusKey?

    /// Whether weight is one the hiding backend parks items at, rather than
    /// an ordinary position on the bar.
    func isParkedWeight(_ weight: Int) -> Bool

    // MARK: Writing

    /// Writes item's weight so the host sorts it into destination,
    /// reporting whether a write was made.
    @discardableResult
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool
    ) -> Bool

    /// move(item:to:liveItems:experimentalSystemItemHiding:) with authority
    /// over segments that contain an item whose position key cannot be
    /// resolved. See
    /// applyOrder(desiredOrder:liveItems:experimentalSystemItemHiding:mayRewriteAroundUnplaceableItems:):
    /// without the authority the move's segment-respace rung declines and the
    /// caller falls back to the cursor-using drag.
    @discardableResult
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems: Bool
    ) -> Bool

    /// Rewrites weights so the host sorts liveItems into desiredOrder,
    /// returning the keys written. Empty means nothing needed changing.
    func applyOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool
    ) -> [String]

    /// Spreads desiredOrder's weights back out after they have bunched up.
    ///
    /// Repeated midpoint writes run out of room between neighbours, at which
    /// point a group reads as interleaved even though the order is right.
    /// Respacing restores the gaps without changing the sequence.
    func respaceOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool
    ) -> [String]

    /// applyOrder(desiredOrder:liveItems:experimentalSystemItemHiding:)
    /// with authority over segments that contain an item whose position key
    /// cannot be resolved.
    ///
    /// Declined by default, since rewriting around such an item moves its
    /// neighbours. Callers answering an explicit request pass true.
    func applyOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems: Bool
    ) -> [String]

    /// respaceOrder(desiredOrder:liveItems:experimentalSystemItemHiding:)
    /// with authority over segments that contain an item whose position key
    /// cannot be resolved. See
    /// applyOrder(desiredOrder:liveItems:experimentalSystemItemHiding:mayRewriteAroundUnplaceableItems:).
    func respaceOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems: Bool
    ) -> [String]

    /// Breaks a weight shared by two or more live icons of one app.
    ///
    /// Tied icons swap places between passes. The leading icon keeps the
    /// weight and the rest step away in rendered order. Returns the keys written.
    func breakTiedSiblingWeights(liveItems: [MenuBarItem]) -> [String]

    /// Orders Thaw's own control items, naming opaqueVisibleKeys so the
    /// permutation does not hand their slots away.
    func applyControlItemOrder(
        desiredOrder: [MenuBarItem],
        opaqueVisibleKeys: [String],
        liveItems: [MenuBarItem]
    ) -> [String]

    /// Whether this process may reach the host's position table. Without
    /// consent cfprefsd refuses every read, so callers skip the store path.
    func positionsDomainIsAccessible() -> Bool
    /// Reads the raw table, for callers that prune it rather than sort by it.
    func readPositions() -> [String: Int]

    /// Replaces the whole table. Callers subtract from a fresh read rather than
    /// writing back a stale snapshot, since the host writes between reads.
    func writePositions(_ positions: [String: Int])

    // MARK: Keys proven to name no icon

    /// Whether key has been settled as naming nothing that renders.
    ///
    /// Recovering such a key would re-materialize a phantom item, so the
    /// recovery paths consult this before reserving a slot for one.
    func isProvenAbsent(_ key: String) -> Bool

    /// Records a capture pass, returning the keys it retired.
    ///
    /// seen clears prior strikes; blank adds one. A key is only settled
    /// after repeat evidence, because an app that is merely slow to draw would
    /// otherwise lose its position.
    @discardableResult
    func recordAbsenceEvidence(seen: Set<String>, blank: Set<String>) -> Set<String>

    /// Forgets everything settled this launch.
    func resetAbsenceEvidence()
}

public extension MenuBarPositionStoring {
    /// In-memory and test stores are always reachable; only the runtime store
    /// over the protected group container can be denied.
    func positionsDomainIsAccessible() -> Bool {
        true
    }

    /// Default authority: decline, which older published conformers must keep
    /// meaning.
    func applyOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems _: Bool
    ) -> [String] {
        applyOrder(
            desiredOrder: desiredOrder,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
    }

    /// See the applyOrder default above.
    func respaceOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems _: Bool
    ) -> [String] {
        respaceOrder(
            desiredOrder: desiredOrder,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
    }

    /// See the applyOrder default above.
    @discardableResult
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems _: Bool
    ) -> Bool {
        move(
            item: item,
            to: destination,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
    }
}
