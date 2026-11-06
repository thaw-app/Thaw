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
        for section in sections {
            guard let items = sectionItems(section) else { break }
            guard !items.isEmpty else { continue }

            let displayID = displayID()
            let itemsToCapture = itemsToCapture(from: items, onlyMissingImages: onlyMissingImages, on: displayID)
            guard !itemsToCapture.isEmpty else { continue }

            guard !Task.isCancelled else {
                MenuBarItemImageCache.diagLog.debug(
                    "prewarmConcealedImages: capture cancelled before start for \(section.logString)"
                )
                break
            }
            await captureSection(itemsToCapture, displayID)
        }

        // One save after the whole pass: every save rewrites the entire cache.
        save()
    }

    /// Prewarms both hidden sections for the user. Items whose picture is already good are left
    /// alone unless retakingAll, since each reveal risks a worse one. Nil when no capture can run.
    func captureHiddenItems(retakingAll: Bool) async -> HiddenItemCaptureResult? {
        guard mayReveal() else { return nil }

        let sections: [MenuBarSection.Name] = [.hidden, .alwaysHidden]
        let alreadyGood = retakingAll ? [] : Set(sections.flatMap { sectionItems($0) ?? [] }
            .filter { !MenuBarItemImageCache.prewarmNeedsCapture(cachedImage: cachedImage($0.tag), wouldAttemptCapture: true) }
            .map(\.tag))
        let tally = RequestedCaptureTally()
        await capture(sections: sections, onlyMissingImages: !retakingAll, tally: tally)
        let newlyCaptured = tally.tags

        let items = sections.flatMap { sectionItems($0) ?? [] }
            .filter { MenuBarItemImageCache.isCapturable($0) && !MenuBarItemImageCache.isBlankItem($0.bounds) && !$0.tag.isControlCenterGovernable }
        return MenuBarItemImageCache.hiddenItemCaptureResult(items: items, alreadyGood: alreadyGood, newlyCaptured: newlyCaptured)
    }

    /// The items of one section a prewarm reveals, in section order.
    private func itemsToCapture(from items: [MenuBarItem], onlyMissingImages: Bool, on displayID: CGDirectDisplayID) -> [MenuBarItem] {
        // Native notch overflow stays in force when Thaw lifts an item's concealment,
        // so a prewarm then captures only the system chevron.
        guard !isNativeOverflowActive(displayID) else { return [] }
        let allowsCaptureReveal = allowsCaptureReveal()
        return items.filter { item in
            guard !Self.skips(item, allowsCaptureReveal: allowsCaptureReveal) else { return false }
            return !onlyMissingImages || MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: cachedImage(item.tag),
                wouldAttemptCapture: wouldAttemptCapture(item)
            )
        }
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
