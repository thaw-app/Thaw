//
//  CustomTooltip.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - CustomTooltipPanel

/// Native-looking tooltip with custom display timing.
final class CustomTooltipPanel: NSPanel {
    static let shared = CustomTooltipPanel()

    /// Owner token prevents other owners from dismissing the shared tooltip.
    private(set) var currentOwner: AnyHashable?

    /// Missed hover exits must not strand the singleton onscreen.
    /// Each show rearms the watchdog; it dismisses after 10 seconds without a refresh.
    private var hideWatchdog: Timer?

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
        // Stay above ThawBarPanel's mainMenu + 1 level so grid items cannot obscure tooltips.
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

    /// The owner token prevents other callers from dismissing this tooltip.
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
            // Stale or parked bounds outside all screens cannot place a tooltip safely.
            return
        }

        currentOwner = owner
        setContentSize(panelSize)
        setFrameOrigin(origin)
        orderFrontRegardless()

        // Rearm on every show to prevent a stuck owner from pinning the tooltip indefinitely.
        hideWatchdog?.invalidate()
        hideWatchdog = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.forceDismiss()
            }
        }
    }

    /// Clamp to the screen containing point; return nil for stale or parked coordinates outside all screens.
    /// preferred only breaks ties between overlapping screens that contain point.
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

        origin.x = max(screenFrame.minX + 2, min(origin.x, screenFrame.maxX - panelSize.width - 2))
        origin.y = max(screenFrame.minY + 2, min(origin.y, screenFrame.maxY - panelSize.height - 2))

        return origin
    }

    /// Dismiss only for a matching owner; nil dismisses unconditionally.
    func dismiss(owner: AnyHashable? = nil) {
        if let owner, let currentOwner, owner != currentOwner {
            return
        }
        currentOwner = nil
        orderOut(nil)
        hideWatchdog?.invalidate()
        hideWatchdog = nil
    }

    /// The watchdog dismisses regardless of owner after its timeout.
    private func forceDismiss() {
        currentOwner = nil
        orderOut(nil)
        hideWatchdog?.invalidate()
        hideWatchdog = nil
    }
}

// MARK: - CustomTooltipController

/// Each view needing delayed tooltips owns a controller for the shared panel.
@MainActor
final class CustomTooltipController {
    private var timer: Timer?
    private weak var view: NSView?

    /// A unique identifier for this controller, used as the tooltip owner token.
    private let id = UUID()

    var text: String

    init(text: String, view: NSView? = nil) {
        self.text = text
        self.view = view
    }

    isolated deinit {
        timer?.invalidate()
    }

    @MainActor
    func scheduleShow(delay: TimeInterval) {
        cancel()
        if delay <= 0 {
            showNow()
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.showNow()
                }
            }
        }
    }

    @MainActor
    func cancel() {
        timer?.invalidate()
        timer = nil
        CustomTooltipPanel.shared.dismiss(owner: id)
    }

    @MainActor
    private func showNow() {
        guard let view, let window = view.window else { return }

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
