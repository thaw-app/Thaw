//
//  MenuBarSearchModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Ifrit
import MenuBarModel
import Observation
import ThawCapture

/// Observable state behind MenuBarSearchPanel: the query, the rows it
/// renders, the highlighted row, the inline rename in progress, and the
/// average menu bar color those rows are previewed against.
///
/// One model for all three modes. The launcher modes never rename or preview,
/// so renameSession and averageColorInfo stay nil there; they add only the
/// inventory they rank against.
@MainActor
@Observable
final class MenuBarSearchModel {
    /// Identifies a single row of the search list.
    enum ItemID: Hashable {
        /// A section heading. Headings are never selectable.
        case header(MenuBarSection.Name)
        /// The recents heading, shown above recently activated items when
        /// the query is empty.
        case recentsHeader
        case item(MenuBarItemTag, windowID: CGWindowID?)
    }

    /// Text currently typed into the search field.
    var searchText = ""

    /// Rows to render, already filtered and ranked against searchText.
    var displayedItems = [SectionedListItem<ItemID, MenuBarSearchListContent>]()

    /// The highlighted row, if there is one.
    var selection: ItemID?

    /// Color sampled from behind the menu bar, used to tint item previews.
    private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// An inline rename in progress. Bundling the target and the draft into
    /// one value means a draft can never outlive the row it belongs to.
    struct RenameSession: Equatable {
        /// Tag of the item being renamed.
        let tag: MenuBarItemTag

        /// Window the rename was started from, when the row knew it. Lookups
        /// prefer this over the tag, which can be ambiguous.
        let windowID: CGWindowID?

        /// Text typed so far, not yet committed.
        var draft: String

        /// Whether this session is renaming item.
        func targets(_ item: MenuBarItem) -> Bool {
            tag == item.tag && windowID == item.windowID
        }
    }

    /// The rename in progress, or nil while nothing is being renamed.
    var renameSession: RenameSession?

    /// Subscriptions tying this model to the panel it is attached to.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// The capture still in flight, if any, so a clear or a newer capture can
    /// supersede it and its late completion can't overwrite a freshly cleared
    /// value or a newer capture's result.
    @ObservationIgnored
    private let captureSlot = TaskSlot()

    /// Fuzzy matcher that ranks items against the query. One instance for all
    /// three modes, so they agree on what counts as a match at all.
    let fuse = Fuse(threshold: 0.5)

    /// The launcher modes' inventory, as the matcher sees it.
    ///
    /// Cached here rather than rebuilt per keystroke: building a candidate
    /// resolves each item's owning application, and the content view empties
    /// this whenever the item cache it was derived from turns over. Ignored by
    /// Observation because no view body reads it, the rows built from it are
    /// what SwiftUI renders.
    @ObservationIgnored
    var launcherCandidates = [PaletteCandidate]()

    /// Attaches the model to panel, replacing any earlier attachment.
    ///
    /// While attached, the average menu bar color tracks whichever screen the
    /// panel is showing on, and is dropped again once the panel hides or the
    /// display arrangement changes underneath it.
    func attach(to panel: MenuBarSearchPanel) {
        cancellables.removeAll()

        panel.publisher(for: \.isVisible)
            .combineLatest(panel.publisher(for: \.screen))
            .compactMap { isVisible, screen in isVisible ? screen : nil }
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] screen in self?.updateAverageColorInfo(for: screen) }
            .store(in: &cancellables)

        // Clear average color when search panel closes to free memory
        // and invalidate any in-flight capture from the open lifetime.
        panel.publisher(for: \.isVisible)
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.clearAverageColorInfo()
            }
            .store(in: &cancellables)

        // Clear on display changes to prevent stale color info and invalidate
        // any in-flight capture targeting the previous screen geometry.
        DisplayTopology.shared.screenParametersChanged
            .sink { [weak self] in
                self?.clearAverageColorInfo()
            }
            .store(in: &cancellables)
    }

    /// Drops the attachment, so nothing is sampled until the model is attached
    /// again. Called when the search panel's mode stops previewing rows over
    /// the menu bar color.
    func detach() {
        cancellables.removeAll()
        clearAverageColorInfo()
    }

    /// Clears averageColorInfo and cancels any in-flight capture so a late
    /// completion can't overwrite the cleared state with a stale value.
    private func clearAverageColorInfo() {
        captureSlot.cancel()
        averageColorInfo = nil
    }

    /// Samples the color behind the menu bar on screen and publishes it.
    ///
    /// The capture is a one pixel tall slice of the wallpaper with the menu
    /// bar composited over it, which is all the average needs.
    private func updateAverageColorInfo(for screen: NSScreen) {
        let displayID = screen.displayID
        let onScreenWindows = WindowInfo.createWindows(option: .onScreen)

        // The slot supersedes the previous capture before we suspend. If
        // clearAverageColorInfo cancels it or a newer update replaces it while
        // we await, our completion is stale and must skip the write so we
        // don't undo an intentional clear or clobber a fresher capture.
        captureSlot.replace { [weak self] ticket in
            let image = await MenuBarColorSampler.captureStrip(
                for: displayID,
                from: onScreenWindows
            )?.image
            guard let color = image?.averageColor(option: .ignoreAlpha) else {
                return
            }
            guard let self, self.captureSlot.isCurrent(ticket) else { return }
            let info = MenuBarAverageColorInfo(color: color, source: .menuBarWindow)
            if self.averageColorInfo != info {
                self.averageColorInfo = info
            }
        }
    }
}
