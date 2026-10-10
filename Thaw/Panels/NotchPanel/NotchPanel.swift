//
//  NotchPanel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import SwiftUI

/// Geometry shared by every descender. Body sizes belong to the widgets; what
/// is fixed here is how a body attaches to the bar.
@MainActor
enum NotchMetrics {
    static let shoulderRadius: CGFloat = 10
    static let bottomRadius: CGFloat = 12

    /// Free width on each side of the body, so both shoulders have somewhere
    /// to be painted and an off-centre body still has room to slide.
    static let horizontalSlack: CGFloat = shoulderRadius + 22

    /// Room below the body for the shadow it casts, which would otherwise be
    /// clipped at the panel's bottom edge.
    static let shadowSlack: CGFloat = 14

    /// How long a descender takes to grow out of the bar or retract into it.
    static let revealDuration: Duration = .milliseconds(240)
}

// MARK: - NotchPresentation

/// One descender: the widget, the geometry it resolved to, and the item it
/// belongs to. Rebuilt from scratch for each descent rather than mutated, so a
/// stale anchor cannot outlive the hover that produced it.
struct NotchPresentation: Identifiable {
    let id: String
    let widget: any NotchWidget
    let itemWindowID: CGWindowID
    let bodySize: CGSize
    /// Signed displacement of the body from the panel's centre, non-zero only
    /// when the panel had to be pushed inward to stay on screen.
    let bodyOffset: CGFloat
    let panelFrame: CGRect
}

// MARK: - NotchAnchor

/// Places a descender under the menu bar item it describes.
enum NotchAnchor {
    /// Builds the presentation for an item, or nil when the item cannot be
    /// measured or the body cannot be made to fit on screen.
    ///
    /// The item's live window bounds are preferred over its cached bounds:
    /// bridging bounds stay reliable across the reflow that menu bar items go
    /// through constantly, including the moves Thaw itself performs.
    @MainActor
    static func present(
        widget: any NotchWidget,
        for item: MenuBarItem,
        on screen: NSScreen
    ) -> NotchPresentation? {
        let liveBounds = Bridging.getWindowBounds(for: item.windowID)
        let itemBounds = liveBounds ?? item.bounds
        guard itemBounds.width > 0 else {
            return nil
        }
        let itemMidX = itemBounds.midX

        let bodySize = widget.bodySize
        let panelWidth = bodySize.width + NotchMetrics.horizontalSlack * 2
        let panelHeight = bodySize.height + NotchMetrics.shoulderRadius + NotchMetrics.shadowSlack

        let minX = screen.frame.minX
        let maxX = screen.frame.maxX - panelWidth
        guard minX <= maxX else {
            return nil
        }

        let panelMinX = (itemMidX - panelWidth / 2).clamped(to: minX ... maxX)
        let panelMidX = panelMinX + panelWidth / 2

        // The body follows its item, but never so far that a shoulder runs off
        // the panel and the descent stops meeting the bar cleanly.
        let offsetLimit = panelWidth / 2 - bodySize.width / 2 - NotchMetrics.shoulderRadius
        let bodyOffset = (itemMidX - panelMidX).clamped(to: -offsetLimit ... offsetLimit)

        let barHeight = screen.getMenuBarHeightEstimate()
        let topY = screen.frame.maxY - barHeight

        return NotchPresentation(
            id: "\(widget.id)-\(item.windowID)",
            widget: widget,
            itemWindowID: item.windowID,
            bodySize: bodySize,
            bodyOffset: bodyOffset,
            panelFrame: CGRect(
                x: panelMinX,
                y: topY - panelHeight,
                width: panelWidth,
                height: panelHeight
            )
        )
    }
}

// MARK: - NotchPanelModel

/// Drives what is drawn and whether it is currently descended.
@MainActor
final class NotchPanelModel: ObservableObject {
    @Published private(set) var presentation: NotchPresentation?
    @Published private(set) var isRevealed = false

    /// Installs a presentation while nothing is drawn. Revealing is a separate
    /// step so the panel can be moved and resized before anything animates.
    func stage(_ presentation: NotchPresentation?) {
        guard self.presentation?.id != presentation?.id else {
            return
        }
        isRevealed = false
        self.presentation = presentation
    }

    func setRevealed(_ revealed: Bool) {
        guard isRevealed != revealed else {
            return
        }
        isRevealed = revealed
        guard revealed, let widget = presentation?.widget else {
            return
        }
        if widget.refreshPolicy == .whileRevealed {
            widget.refresh()
        }
    }
}

// MARK: - NotchHostingView

/// Hosting view that passes clicks through everywhere except the drawn body.
///
/// The window is wider than the body so the shoulders can be painted; without
/// this override that surround would swallow clicks meant for the windows
/// underneath it.
final class NotchHostingView: NSHostingView<NotchContentView> {
    /// The drawn body's rect in view coordinates, which have their origin at
    /// the bottom left because the hosting view is not flipped.
    var hitRegion: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitRegion().contains(point) ? super.hitTest(point) : nil
    }
}

// MARK: - NotchPanel

/// A nonactivating borderless panel that hangs flush from the menu bar's
/// underside, directly beneath one menu bar item.
@MainActor
final class NotchPanel: NSPanel {
    private(set) weak var hostingView: NotchHostingView?

    init(content: NotchContentView) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.animationBehavior = .none
        self.backgroundColor = .clear
        self.isOpaque = false
        // The descender casts its own shadow in SwiftUI, shaped to the
        // silhouette. A window shadow on top of that would outline the whole
        // transparent panel instead, and because AppKit recomputes it from
        // content alpha only lazily, the outline left behind while the body
        // animates reads as a second shape hanging under the first.
        self.hasShadow = false
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace, .stationary]
        self.hidesOnDeactivate = false
        self.canHide = false
        self.ignoresMouseEvents = true

        let hosting = NotchHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        contentView = hosting
        hostingView = hosting
    }

    /// Moves and resizes the panel for a presentation. Only ever called while
    /// nothing is drawn: the descent itself animates inside a stable frame, so
    /// the window server is never asked to resize a window mid-animation.
    func apply(_ presentation: NotchPresentation) {
        setFrame(presentation.panelFrame, display: false, animate: false)
        hostingView?.frame = NSRect(origin: .zero, size: presentation.panelFrame.size)
        // Bottom-left origin: the body hangs from the top edge, so it stops
        // short of the panel's bottom by the slack the shadow needs.
        hostingView?.hitRegion = {
            CGRect(
                x: presentation.panelFrame.width / 2 + presentation.bodyOffset
                    - presentation.bodySize.width / 2,
                y: NotchMetrics.shadowSlack,
                width: presentation.bodySize.width,
                height: presentation.panelFrame.height - NotchMetrics.shadowSlack
            )
        }
    }
}
