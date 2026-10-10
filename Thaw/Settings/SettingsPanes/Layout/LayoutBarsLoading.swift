//
//  LayoutBarsLoading.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import MenuBarModel
import SwiftUI
import ThawCapture
import ThawUI

/// What stands in for the layout bars while there is nothing to drag.
///
/// Shared by the full Layout pane and Simple Mode so both wait, fade, and
/// explain the same way. Three states, one component: the shared
/// ThawEmptyState owns the spinner-or-symbol swap, the type ramp, and
/// the centering.
///
/// The missing-dividers and denied-Screen-Recording cases are the ones worth
/// distinguishing: the dividers usually reappear once Thaw places them, and
/// Screen Recording only the user can grant, so each caption says where to look.
struct LayoutBarsLoading: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager
    @State private var loadDeadlineReached = false

    private let diagLog = DiagLog(category: "MenuBarLayoutPane")

    init(itemManager: MenuBarItemManager) {
        self.itemManager = itemManager
    }

    private var hasItems: Bool {
        // hasNoManagedItems is a stored Bool maintained at the cache's
        // write site, so this both skips materializing managedItems and
        // narrows what the pane observes to the answer it actually asked for.
        !itemManager.hasNoManagedItems
    }

    func body(content: Content) -> some View {
        content
            .thawAnimation(ThawMotion.settle) { content in
                content.opacity(hasItems ? 1 : 0.75)
            }
            .allowsHitTesting(hasItems)
            .overlay {
                if !hasItems {
                    loadingOverlay
                        .transition(layoutTransition)
                }
            }
            .task(id: hasItems) {
                await loadItemsIfNeeded()
            }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if loadDeadlineReached {
            if itemManager.areControlItemsMissing {
                ThawEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "The section dividers are not on the menu bar yet",
                    caption: LocalizedStringKey(String(
                        localized: "\(Constants.displayName) is trying to place them. If this stays for more than a few seconds, check System Settings \(Constants.menuArrow) Menu Bar for a divider that macOS has hidden.",
                        comment: "Layout pane caption while Thaw's own dividers are off the bar. Placement usually completes on its own; System Settings only matters if macOS hid a divider."
                    ))
                )
                .transition(layoutTransition)
            } else if !ScreenCapture.hasCachedScreenRecordingPermission {
                ThawEmptyState(
                    systemImage: "eye.slash",
                    title: "Couldn’t load menu bar items",
                    caption: "Add \(Constants.displayName) to System Settings \(Constants.menuArrow) Privacy & Security \(Constants.menuArrow) Screen Recording, then reopen this window."
                )
                .transition(layoutTransition)
            } else {
                ThawEmptyState(
                    systemImage: "menubar.rectangle",
                    title: "Couldn’t load menu bar items",
                    caption: "Close and reopen this window to try again. If the bars stay empty, quit \(Constants.displayName) and open it again."
                )
                .transition(layoutTransition)
            }
        } else {
            ThawEmptyState(
                systemImage: "menubar.rectangle",
                title: "Loading menu bar items…",
                isLoading: true
            )
            .transition(layoutTransition)
        }
    }

    private var layoutTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.animation(ThawMotion.settle)
    }

    /// What the overlay does before a preload is attempted.
    ///
    /// Not private, and split out of loadItemsIfNeeded(), because this is
    /// the branch that decides whether the spinner can ever resolve: the
    /// denied-Screen-Recording path has no load to wait on, so if it leaves
    /// the deadline unarmed the "Loading menu bar items…" state is permanent.
    /// The suite pins it; the modifier's @State and @Environment put it
    /// out of reach otherwise.
    enum PreloadPlan: Equatable {
        /// The cache already has items, so the bars are live and the overlay
        /// is gone. Nothing to load and nothing to time out.
        case nothingToLoad
        /// Screen Recording is not granted. The prewarm reveals sections on
        /// the live bar to photograph them and the capture it does that for
        /// cannot run without the grant, so there is no load to wait on and
        /// the overlay resolves straight to the state that names the missing
        /// permission.
        case resolveWithoutLoading
        /// Run the preload, and let the deadline arm it if the cache is still
        /// empty when the timeout lands.
        case preload

        /// Whether the overlay resolves immediately instead of spinning.
        ///
        /// Only the denied grant does: the other two either have no overlay
        /// or have a real load whose timeout owns the flag.
        var armsDeadlineImmediately: Bool {
            self == .resolveWithoutLoading
        }
    }

    /// Chooses the plan for one pass of loadItemsIfNeeded().
    static func preloadPlan(hasItems: Bool, hasScreenRecordingPermission: Bool) -> PreloadPlan {
        if hasItems {
            return .nothingToLoad
        }
        guard hasScreenRecordingPermission else {
            return .resolveWithoutLoading
        }
        return .preload
    }

    private func loadItemsIfNeeded() async {
        let plan = Self.preloadPlan(
            hasItems: hasItems,
            hasScreenRecordingPermission: ScreenCapture.hasCachedScreenRecordingPermission
        )
        loadDeadlineReached = plan.armsDeadlineImmediately
        guard plan == .preload else {
            if plan == .resolveWithoutLoading {
                diagLog.debug("Skipping menu bar layout preload: Screen Recording is not granted")
            }
            return
        }

        diagLog.debug("Preloading menu bar layout caches (hasItems=\(self.hasItems), screenRecording=\(ScreenCapture.hasCachedScreenRecordingPermission))")
        async let preloadCaches: Void = preloadLayoutCaches()
        try? await Task.sleep(for: .seconds(3))

        if !Task.isCancelled, !hasItems {
            loadDeadlineReached = true
            diagLog.error("Menu bar layout failed to load items after 3s timeout. cacheItems: \(itemManager.managedItems.count), images: \(appState.imageCache.capturesByTag.count), displayID: \(self.itemManager.itemDisplayID.map { "\($0)" } ?? "nil")")
        }
        await preloadCaches
    }

    private func preloadLayoutCaches() async {
        await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        guard !Task.isCancelled else { return }

        // Fill gaps only so opening Layout cannot overwrite settled
        // Hidden glyphs with native overflow chevron («») crops.
        await appState.imageCache.prewarmConcealedImages(
            sections: [.hidden, .alwaysHidden],
            onlyMissingImages: true
        )
        guard !Task.isCancelled else { return }

        await appState.imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
    }
}

extension View {
    /// Fades the bars and shows the shared loading, failed, or
    /// missing-dividers state until the item cache has something to drag.
    func layoutBarsLoading(itemManager: MenuBarItemManager) -> some View {
        modifier(LayoutBarsLoading(itemManager: itemManager))
    }
}
