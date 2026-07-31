//
//  CustomTooltip.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - CustomTooltipPanel

/// A lightweight panel that mimics the native macOS tooltip appearance
/// but allows full control over display timing.
final class CustomTooltipPanel: NSPanel {
    static let shared = CustomTooltipPanel()

    /// An opaque token identifying the current owner of the tooltip.
    /// Only the owner that showed the tooltip can dismiss it.
    private(set) var currentOwner: AnyHashable?

    /// Safety-net timer that force-dismisses the tooltip if no owner ever
    /// calls `dismiss(owner:)`.
    ///
    /// A missed hover-exit (a stalled event tap, a deallocated owner, …)
    /// must never leave this singleton on screen forever (#734). The
    /// timer is refreshed on every `show(...)`, so a genuine long hover
    /// keeps the tooltip alive; it only fires after 10s of silence.
    private var hideWatchdog: Task<Void, Never>?

    private let label: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = .toolTipsFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .labelColor
        field.backgroundColor = .clear
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        return field
    }()

    private let glassView: NSGlassEffectView = {
        let view = NSGlassEffectView()
        view.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Must stay above IceBarPanel (`.mainMenu + 1`, see IceBar.swift) so
        // Thaw Bar grid items can't obscure tooltips (#782); pinned by
        // CustomTooltipPanelTests.
        level = .mainMenu + 2
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        hidesOnDeactivate = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let labelContainer = NSView()
        labelContainer.translatesAutoresizingMaskIntoConstraints = false
        labelContainer.addSubview(label)

        glassView.contentView = labelContainer
        contentView.addSubview(glassView)
        self.contentView = contentView

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: contentView.topAnchor),
            glassView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            label.topAnchor.constraint(equalTo: labelContainer.topAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: labelContainer.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: labelContainer.trailingAnchor, constant: -6),
            label.bottomAnchor.constraint(equalTo: labelContainer.bottomAnchor, constant: -2),
        ])
    }

    /// Shows the tooltip with the given text near the specified screen point.
    /// The `owner` token is used to prevent other callers from dismissing
    /// a tooltip they didn't show.
    func show(text: String, near point: CGPoint, in screen: NSScreen?, owner: AnyHashable? = nil) {
        label.stringValue = text
        label.sizeToFit()

        let padding = NSSize(width: 12, height: 4)
        let labelSize = label.intrinsicContentSize
        let panelSize = NSSize(
            width: labelSize.width + padding.width,
            height: labelSize.height + padding.height
        )

        let screens = NSScreen.screens.map { (frame: $0.frame, visibleFrame: $0.visibleFrame) }
        guard let origin = Self.placementOrigin(
            for: panelSize,
            near: point,
            screens: screens,
            preferred: screen?.frame
        ) else {
            // The point doesn't fall inside any known screen, which is the
            // source of the #734 "random position" reports (stale/parked
            // bounds). Don't show a tooltip we can't place sanely — and
            // dismiss any tooltip that's already visible so stale content
            // and ownership don't linger on screen.
            dismiss()
            return
        }

        currentOwner = owner
        setContentSize(panelSize)
        setFrameOrigin(origin)
        orderFrontRegardless()

        // (Re)arm the watchdog on every show, so a stuck owner can never
        // pin the tooltip on screen indefinitely (#734).
        hideWatchdog?.cancel()
        hideWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.forceDismiss()
        }
    }

    /// Computes the origin at which a panel of `panelSize` should be placed
    /// near `point`, clamped to whichever screen's `frame` contains `point`.
    ///
    /// Returns `nil` if `point` falls outside every screen's `frame` — that
    /// indicates stale or parked coordinates that shouldn't be trusted to
    /// place a visible panel (#734).
    ///
    /// `preferred` is used only to break ties between overlapping screen
    /// frames that both contain `point`; it has no effect otherwise.
    static nonisolated func placementOrigin(
        for panelSize: NSSize,
        near point: NSPoint,
        screens: [(frame: NSRect, visibleFrame: NSRect)],
        preferred: NSRect?
    ) -> NSPoint? {
        let candidates = screens.filter { $0.frame.contains(point) }
        guard !candidates.isEmpty else {
            return nil
        }

        let match: (frame: NSRect, visibleFrame: NSRect) = if let preferred, let preferredMatch = candidates.first(where: { $0.frame == preferred }) {
            preferredMatch
        } else {
            candidates[0]
        }

        let screenFrame = match.visibleFrame

        // Position: centered horizontally below the cursor, offset down by 18pt.
        var origin = NSPoint(
            x: point.x - panelSize.width / 2,
            y: point.y - panelSize.height - 18
        )

        // Clamp to screen bounds.
        origin.x = max(screenFrame.minX + 2, min(origin.x, screenFrame.maxX - panelSize.width - 2))
        origin.y = max(screenFrame.minY + 2, min(origin.y, screenFrame.maxY - panelSize.height - 2))

        return origin
    }

    /// Hides the tooltip immediately.
    ///
    /// If `owner` is provided, the tooltip is only dismissed when the
    /// current owner matches. Pass `nil` to dismiss unconditionally.
    func dismiss(owner: AnyHashable? = nil) {
        if let owner, let currentOwner, owner != currentOwner {
            return
        }
        currentOwner = nil
        orderOut(nil)
        hideWatchdog?.cancel()
        hideWatchdog = nil
    }

    /// Force-dismisses the tooltip regardless of owner, invoked by the
    /// watchdog timer when no owner has dismissed it in time (#734).
    private func forceDismiss() {
        currentOwner = nil
        orderOut(nil)
        hideWatchdog?.cancel()
        hideWatchdog = nil
    }
}

// MARK: - CustomTooltipController

/// A per-view controller that manages showing and hiding the shared
/// tooltip panel with a configurable delay.
///
/// Each `NSView` that wants custom-delayed tooltips should own an
/// instance of this controller.
@MainActor
final class CustomTooltipController {
    private var timer: Task<Void, Never>?
    private weak var view: NSView?

    /// A unique identifier for this controller, used as the tooltip owner token.
    private let id = UUID()

    /// The text to display in the tooltip.
    var text: String

    init(text: String, view: NSView? = nil) {
        self.text = text
        self.view = view
    }

    isolated deinit {
        timer?.cancel()
    }

    @MainActor
    func scheduleShow(delay: TimeInterval) {
        cancel()
        if delay <= 0 {
            showNow()
        } else {
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.showNow()
            }
        }
    }

    @MainActor
    func cancel() {
        timer?.cancel()
        timer = nil
        CustomTooltipPanel.shared.dismiss(owner: id)
    }

    @MainActor
    private func showNow() {
        guard let view, let window = view.window else { return }

        // Position the tooltip below the center of the view.
        let viewCenter = NSPoint(x: view.bounds.midX, y: view.bounds.minY)
        let windowPoint = view.convert(viewCenter, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)

        CustomTooltipPanel.shared.show(
            text: text,
            near: screenPoint,
            in: window.screen,
            owner: id
        )
    }
}
