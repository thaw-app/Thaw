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
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        hidesOnDeactivate = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let labelContainer = NSView()
        labelContainer.translatesAutoresizingMaskIntoConstraints = false
        labelContainer.addSubview(label)

        glassView.addSubview(label)
        contentView.addSubview(glassView)
        self.contentView = contentView

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: contentView.topAnchor),
            glassView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            label.topAnchor.constraint(equalTo: glassView.topAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: glassView.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: glassView.trailingAnchor, constant: -6),
            label.bottomAnchor.constraint(equalTo: glassView.bottomAnchor, constant: -2),
        ])
    }

    /// Shows the tooltip with the given text near the specified screen point.
    /// The `owner` token is used to prevent other callers from dismissing
    /// a tooltip they didn't show.
    func show(text: String, near point: CGPoint, in screen: NSScreen?, owner: AnyHashable? = nil) {
        currentOwner = owner
        label.stringValue = text
        label.sizeToFit()

        let padding = NSSize(width: 12, height: 4)
        let labelSize = label.intrinsicContentSize
        let panelSize = NSSize(
            width: labelSize.width + padding.width,
            height: labelSize.height + padding.height
        )

        let screen = screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? .zero

        // Position: centered horizontally below the cursor, offset down by 18pt.
        var origin = NSPoint(
            x: point.x - panelSize.width / 2,
            y: point.y - panelSize.height - 18
        )

        // Clamp to screen bounds.
        origin.x = max(screenFrame.minX + 2, min(origin.x, screenFrame.maxX - panelSize.width - 2))
        origin.y = max(screenFrame.minY + 2, min(origin.y, screenFrame.maxY - panelSize.height - 2))

        setContentSize(panelSize)
        setFrameOrigin(origin)
        orderFrontRegardless()
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
    }
}

// MARK: - CustomTooltipController

/// A per-view controller that manages showing and hiding the shared
/// tooltip panel with a configurable delay.
///
/// Each `NSView` that wants custom-delayed tooltips should own an
/// instance of this controller.
final class CustomTooltipController {
    private var timer: Timer?
    private weak var view: NSView?

    /// A unique identifier for this controller, used as the tooltip owner token.
    private let id = UUID()

    /// The text to display in the tooltip.
    var text: String

    init(text: String, view: NSView? = nil) {
        self.text = text
        self.view = view
    }

    deinit {
        cancel()
    }

    /// Schedules the tooltip to appear after `delay` seconds.
    /// If `delay` is 0, the tooltip is shown immediately.
    func scheduleShow(delay: TimeInterval) {
        cancel()
        if delay <= 0 {
            showNow()
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.showNow()
            }
        }
    }

    /// Hides the tooltip and cancels any pending show timer.
    func cancel() {
        timer?.invalidate()
        timer = nil
        CustomTooltipPanel.shared.dismiss(owner: id)
    }

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
