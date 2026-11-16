//
//  RevealCapturePrewarm.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Chooses the hidden items a prewarm reveals, section by section, and hands each
/// section's choice to a grouped reveal. It holds the reveal capture slot while it runs.
@MainActor
struct RevealCapturePrewarm {
    let slot: RevealCaptureSlot
    /// Whether the screen is locked, logged under the step that asks.
    let isLocked: @MainActor (String) -> Bool
    /// Whether a prewarm may reveal hidden items now. See ConcealedPrewarmGate.
    let mayReveal: @MainActor () -> Bool
    /// The section's items, or nil once the app has gone.
    let sectionItems: @MainActor (MenuBarSection.Name) -> [MenuBarItem]?
    /// The display the item cache describes, asked once per section.
    let displayID: @MainActor () -> CGDirectDisplayID
    let isNativeOverflowActive: @MainActor (CGDirectDisplayID) -> Bool
    /// True while Capture Hidden Items runs under Native hiding, which keeps apps off the bar until revealed.
    let allowsCaptureReveal: @MainActor () -> Bool
    /// The picture a consumer would draw for the tag. Reading it counts as a use.
    let cachedImage: @MainActor (MenuBarItemTag) -> MenuBarItemGlyphCapture?
    /// False while repeated failures keep the item from being tried.
    let wouldAttemptCapture: @MainActor (MenuBarItem) -> Bool
    let forgetFailures: @MainActor (Set<MenuBarItemTag>) -> Void
    /// Reveals and photographs one section's chosen items on the display.
    let captureSection: @MainActor ([MenuBarItem], CGDirectDisplayID) async -> Void
    let save: @MainActor () -> Void
    /// Picks pictures that no longer fit their item for an automatic pass to retake: the one the
    /// Thaw Bar's passes share for the session unless a caller passes another, or nil for none.
    var retakeLedger: GlyphRetakeLedger? = .shared

    /// Briefly reveals concealed sections so their live glyphs can be captured before the assertion hides them again.
    func capture(sections requestedSections: [MenuBarSection.Name], onlyMissingImages: Bool, tally: RequestedCaptureTally?) async {
        // Before the failure reset and the reveal: a locked pass must not toggle
        // the lock screen's bar or clear strikes it did not earn back.
        guard !isLocked("prewarmConcealedImages"), mayReveal() else { return }

        // One pass at a time: overlapping passes land one's conceal inside the
        // other's screenshot. A queued pass whose bar closed stops here.
        await slot.begin(tally: tally)
        defer { slot.end() }
        // The hiding method can change while a pass waits its turn.
        guard !Task.isCancelled, !isLocked("queued prewarm"), mayReveal() else { return }

        let sections = Self.prewarmSections(requestedSections)
        // Only a pass the user asked for retries failed items at once. Automatic
        // passes wait out the cooldown, so they don't rewrite the bar on every open.
        if !onlyMissingImages || tally != nil {
            let tags = sections.reduce(into: Set<MenuBarItemTag>()) { result, section in
                result.formUnion((sectionItems(section) ?? []).map(\.tag))
            }
            if !tags.isEmpty {
                forgetFailures(tags)
                MenuBarItemImageCache.diagLog.debug(
                    "prewarmConcealedImages: forgot recorded failures for \(tags.count) item(s) in " +
                        "\(sections.map(\.rawValue))"
                )
            }
        }

        // Always-hidden items go through the same grouped reveal as hidden ones: closing the Thaw Bar
        // conceals a revealed section again. Inline in the caller's task, so its cancel stops the loop.
        // The width-retake limit holds for the whole pass, not for each section.
        var widthRetakesLeft = GlyphRetakeLedger.widthRetakesPerPass
        for section in sections {
            guard let items = sectionItems(section) else { break }
            guard !items.isEmpty else { continue }

            let displayID = displayID()
            let retakes = onlyMissingImages ? widthRetakes(among: items, on: displayID, limit: widthRetakesLeft) : []
            widthRetakesLeft -= retakes.count
            let itemsToCapture = itemsToCapture(
                from: items, onlyMissingImages: onlyMissingImages, retakes: retakes, retakesClipped: tally != nil, on: displayID
            )
            guard !itemsToCapture.isEmpty else { continue }

            guard !Task.isCancelled else {
                MenuBarItemImageCache.diagLog.debug(
                    "prewarmConcealedImages: capture cancelled before start for \(section.logString)"
                )
                break
            }
            await captureSection(itemsToCapture, displayID)
            // A screen locked during the capture revealed nothing, so its retakes are still due.
            if !isLocked("recording width retakes") {
                retakeLedger?.noteRetaken(retakes)
            }
        }

        // One save after the whole pass: every save rewrites the entire cache.
        save()
    }

    /// Prewarms both hidden sections for the user. Items whose picture is already good are left
    /// alone unless retakingAll, since each reveal risks a worse one. Nil when no capture can run.
    func captureHiddenItems(retakingAll: Bool) async -> HiddenItemCaptureResult? {
        guard mayReveal() else { return nil }
        // The section loop would skip every section; say why instead of listing each item as missing.
        guard !isNativeOverflowActive(displayID()) else { return .fullBar }

        let sections: [MenuBarSection.Name] = [.hidden, .alwaysHidden]
        let alreadyGood = retakingAll ? [] : Set(sections.flatMap { sectionItems($0) ?? [] }
            .filter { !MenuBarItemImageCache.prewarmNeedsCapture(cachedImage: cachedImage($0.tag), wouldAttemptCapture: true, retakesClipped: true) }
            .map(\.tag))
        let tally = RequestedCaptureTally()
        await capture(sections: sections, onlyMissingImages: !retakingAll, tally: tally)
        let newlyCaptured = tally.tags

        let items = sections.flatMap { sectionItems($0) ?? [] }
        return MenuBarItemImageCache.hiddenItemCaptureResult(items: items, alreadyGood: alreadyGood, newlyCaptured: newlyCaptured)
    }

    /// The items of one section a prewarm reveals, in section order: those missing a picture, and
    /// retakes. A pass the user asked for also retakes pictures clipped at their left edge.
    private func itemsToCapture(
        from items: [MenuBarItem], onlyMissingImages: Bool, retakes: Set<String>, retakesClipped: Bool, on displayID: CGDirectDisplayID
    ) -> [MenuBarItem] {
        // Native notch overflow stays in force when Thaw lifts an item's concealment,
        // so a prewarm then captures only the system chevron.
        guard !isNativeOverflowActive(displayID) else { return [] }
        let allowsCaptureReveal = allowsCaptureReveal()
        return items.filter { item in
            guard !Self.skips(item, allowsCaptureReveal: allowsCaptureReveal) else { return false }
            return !onlyMissingImages || retakes.contains(item.tag.tagIdentifier) || MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: cachedImage(item.tag),
                wouldAttemptCapture: wouldAttemptCapture(item),
                retakesClipped: retakesClipped
            )
        }
    }

    /// The items whose picture no longer fits them and the ledger has this pass retake, limit at most.
    private func widthRetakes(among items: [MenuBarItem], on displayID: CGDirectDisplayID, limit: Int) -> Set<String> {
        guard let retakeLedger, limit > 0, !isNativeOverflowActive(displayID) else { return [] }
        let allowsCaptureReveal = allowsCaptureReveal()
        let candidates = items.compactMap { item -> GlyphRetakeLedger.Candidate? in
            guard !Self.skips(item, allowsCaptureReveal: allowsCaptureReveal), wouldAttemptCapture(item),
                  let picture = cachedImage(item.tag)
            else { return nil }
            return GlyphRetakeLedger.Candidate(identifier: item.tag.tagIdentifier, pictureWidth: picture.pointSize.width, itemWidth: item.bounds.width)
        }
        let retakes = retakeLedger.retakes(among: candidates, limit: limit)
        if !retakes.isEmpty {
            MenuBarItemImageCache.diagLog.debug("prewarmConcealedImages: retaking \(retakes.sorted()), whose picture no longer fits the item")
        }
        return retakes
    }

    /// The requested sections without the visible one or repeats, in request order.
    static nonisolated func prewarmSections(_ requested: [MenuBarSection.Name]) -> [MenuBarSection.Name] {
        requested.reduce(into: [MenuBarSection.Name]()) { result, section in
            guard section != .visible, !result.contains(section) else { return }
            result.append(section)
        }
    }

    /// Whether a prewarm leaves this item out: a switched-off Control Center module never draws, and a
    /// blank item has no size unless Native hiding parks it until this capture reveals it.
    static nonisolated func skips(_ item: MenuBarItem, allowsCaptureReveal: Bool) -> Bool {
        item.tag.isControlCenterGovernable || !allowsCaptureReveal && MenuBarItemImageCache.isBlankItem(item.bounds)
    }
}
