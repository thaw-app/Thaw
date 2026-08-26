//
//  LayoutBarItemView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
final class LayoutBarItemView: LayoutBarArrangedView {
    private static let diagLog = DiagLog(category: "LayoutBarItemView")

    private enum Metrics {
        static let minWidth: CGFloat = 14
        static let maxWidth: CGFloat = 240
        static let minHeight: CGFloat = 18
        static let placeholderCornerRadius: CGFloat = 6
        static let placeholderHorizontalInset: CGFloat = 2
        static let placeholderVerticalInset: CGFloat = 2
        static let iconInset: CGFloat = 2
        static let fallbackSymbolPointSize: CGFloat = 11
        static let unresponsiveBadgeWidth: CGFloat = 15
        static let triggerBadgeWidth: CGFloat = 11
        static let triggerControlledFraction: CGFloat = 0.45
    }

    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// Observes `appState.imageCache.images` (wave 3: `MenuBarItemImageCache`
    /// is @Observable rather than a Combine `ObservableObject`, so its old
    /// `$images` projection is gone). This is an AppKit view (not a SwiftUI
    /// body), so the Observations-async-sequence pattern is used instead of
    /// `withObservationTracking`'s recursive-registration form, matching
    /// this class's existing Combine-`sink`-based subscription style.
    private var imageObservationTask: Task<Void, Never>?

    /// Observes trigger ownership of this item. The container rebuilds item
    /// views only on cache changes, so without this a trigger toggled while
    /// the layout editor is open (its own switch, or the menu bar's
    /// "All Trigger Features Off") would leave the badge and dimming stale
    /// until an unrelated recache.
    private var triggerObservationTask: Task<Void, Never>?

    @MainActor
    deinit {
        imageObservationTask?.cancel()
        triggerObservationTask?.cancel()
    }

    /// The item that the view represents.
    let item: MenuBarItem

    /// The app-owned identity an AX correlation promoted an
    /// `unresolvedControlCenterPlaceholder` to during this view's lifetime, or
    /// `nil` when no alias has been resolved. Non-nil only after
    /// ``aliasForUnresolvedControlCenterPlaceholder()`` succeeded; once set,
    /// it stays so the drag and the alert copy both report the app-owned form.
    private var aliasedItem: MenuBarItem?

    /// The item the view should be addressed by — the alias when one was
    /// resolved, otherwise the captured `item`. Drag dispatch reads this so a
    /// promoted placeholder drags as its app-owned tag, not the parked
    /// Control Center slot.
    private var effectiveItem: MenuBarItem {
        aliasedItem ?? item
    }

    private lazy var tooltipController = CustomTooltipController(text: item.displayName, view: self)
    private var tooltipTrackingArea: NSTrackingArea?
    private let placeholderImage: NSImage?

    /// The image displayed inside the view.
    private var cachedImage: MenuBarItemImageCache.CapturedImage? {
        didSet {
            let previousSize = preferredSize(for: oldValue)
            let newSize = preferredSize(for: cachedImage)
            setFrameSize(newSize)
            if previousSize != newSize {
                (superview as? LayoutBarContainer)?.itemPreferredSizeDidChange(self)
            }
            needsDisplay = true
        }
    }

    override var kind: Kind {
        .item(effectiveItem)
    }

    /// The enabled trigger that owns this item's placement, or `nil`.
    ///
    /// A trigger-owned item is not where the user put it:
    /// `MenuBarItemManager` shields it from both the saved-layout reconciler
    /// and `saveSectionOrder`, and the trigger's own reveal/hide sections
    /// decide where it sits. The drag is deliberately still allowed — the
    /// trigger re-asserts the placement, and refusing it would take away the
    /// only manual correction available when a trigger hasn't applied yet.
    /// The badge exists so the snap-back isn't a mystery.
    private var isTriggerControlled: Bool {
        appState?.settings.triggers.isControlledByTrigger(
            identifier: effectiveItem.tag.tagIdentifier
        ) ?? false
    }

    /// The owning trigger itself. Resolved only on hover, for the tooltip —
    /// `draw` uses the O(1) ``isTriggerControlled`` instead.
    private var controllingTrigger: MenuBarItemTrigger? {
        appState?.settings.triggers.controllingTrigger(
            forIdentifier: effectiveItem.tag.tagIdentifier
        )
    }

    /// Creates a view that displays the given menu bar item.
    init(appState: AppState, item: MenuBarItem) {
        self.item = item
        self.appState = appState
        self.placeholderImage = Self.makePlaceholderImage(for: item)

        let initialImage = appState.imageCache.image(for: item.tag)
        self.cachedImage = initialImage

        super.init(frame: CGRect(origin: .zero, size: Self.preferredSize(for: item, image: initialImage)))
        unregisterDraggedTypes()

        // Addressing the window's owner lifts the unresolved-placeholder
        // reason, so the panel offers items it can actually move.
        isEnabled = item.isMovableAddressingWindowOwner

        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var tooltipDelay: TimeInterval {
        appState?.settings.advanced.tooltipDelay ?? 0.5
    }

    override func draggingImage() -> NSImage? {
        cachedImage?.nsImage ?? placeholderBitmapImage()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tooltipTrackingArea {
            removeTrackingArea(tooltipTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tooltipTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Refreshed on hover rather than at init: a trigger can be added or
        // removed while the layout editor is open.
        tooltipController.text = if let trigger = controllingTrigger {
            String(localized: "\(effectiveItem.displayName) \u{2014} placed by trigger \u{201C}\(trigger.displayName)\u{201D}")
        } else {
            effectiveItem.displayName
        }
        tooltipController.scheduleShow(delay: tooltipDelay)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        tooltipController.cancel()
    }

    private func configureCancellables() {
        let c = Set<AnyCancellable>()

        if let appState {
            let tag = item.tag
            imageObservationTask = Task { @MainActor [weak self, weak appState] in
                var previous: MenuBarItemImageCache.CapturedImage?
                let changes = Observations { appState?.imageCache.images[tag] ?? nil }
                for await image in changes {
                    guard let self else { return }
                    guard !MenuBarItemImageCache.CapturedImage.isVisuallyEqual(previous, image) else { continue }
                    previous = image
                    self.cachedImage = image
                }
            }

            // `controlledIdentifiers` is stored (not lazily memoized)
            // precisely so this closure registers a dependency on every read.
            // The base is read through `effectiveItem` so an AX alias resolved
            // mid-life queries the same identity `draw` does.
            triggerObservationTask = Task { @MainActor [weak self, weak appState] in
                let changes = Observations { [weak self, weak appState] in
                    guard let self, let appState else { return false }
                    return appState.settings.triggers.isControlledByTrigger(
                        identifier: self.effectiveItem.tag.tagIdentifier
                    )
                }
                var previous: Bool?
                for await controlled in changes {
                    guard let self else { return }
                    guard controlled != previous else { continue }
                    previous = controlled
                    self.needsDisplay = true
                }
            }
        }

        cancellables = c
    }

    /// Provides an alert to display when the item view is disabled.
    ///
    /// The copy names the gate honestly. "macOS prohibits" is only true for
    /// the static system items; an unresolved Control Center slot is Thaw's
    /// own safety gate, and blaming macOS for it sent #905's reporter
    /// chasing the wrong condition. When an AX correlation identified the
    /// hosted slot's real owner, the alert names it instead of the generic
    /// fallback the identity the decision was made on never matched.
    func provideAlertForDisabledItem(axResolvedName: String? = nil) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Menu bar item is not movable.")
        switch item.immovabilityReason {
        case .unresolvedControlCenterPlaceholder:
            let name = axResolvedName ?? item.displayName
            alert.informativeText = String(localized: "\(Constants.displayName) can't currently tell which app owns \"\(name)\", so moving it is disabled. This usually resolves on its own; relaunching the app that owns the item can help.")
        case .prohibitedSystemItem, nil:
            alert.informativeText = String(localized: "macOS prohibits \"\(item.displayName)\" from being moved.")
        }
        return alert
    }

    /// Emits the diagnostic #905 asked for: the resolved identifier and the
    /// exact condition the refusal was decided on. Returns the app-owned
    /// name AX correlation found for a degraded identity, so the alert can
    /// show it.
    ///
    /// Takes the identity the alias attempt already correlated rather than
    /// running its own snapshot: the refusal path reaches here right after
    /// ``aliasForUnresolvedControlCenterPlaceholder()`` paid for the same
    /// bounded AX work, and paying twice is a visible main-thread hitch
    /// mid-drag.
    private func logMoveRefusal(
        correlatedIdentity: AXIdentityCatalog.AXItemIdentity?
    ) -> String? {
        let reason = item.immovabilityReason?.logDescription ?? "isMovable false with no named gate"
        Self.diagLog.warning(
            "Move refused for \(item.logString): \(reason); uniqueIdentifier=\(item.uniqueIdentifier), windowID=\(item.windowID), sourcePID=\(item.sourcePID.map(String.init) ?? "nil"), ownerPID=\(item.ownerPID)"
        )
        guard item.immovabilityReason == .unresolvedControlCenterPlaceholder else {
            return nil
        }
        guard let identity = correlatedIdentity else {
            Self.diagLog.warning(
                "Move refusal: AX correlation found no confident identity for windowID \(item.windowID)"
            )
            return nil
        }
        Self.diagLog.warning(
            "Move refusal: AX names windowID \(item.windowID) as identifier=\(identity.identifier ?? "nil"), title=\(identity.title ?? "nil"), help=\(identity.help ?? "nil")"
        )
        return identity.identifier ?? identity.title ?? identity.help
    }

    /// #905 identity-preference fallback. When the captured `item` is an
    /// `unresolvedControlCenterPlaceholder` — `com.apple.controlcenter:Item-N`,
    /// `sourcePID == nil` — but Control Center's AX tree already names the
    /// owning app for the slot's frame, build a synthetic `MenuBarItem`
    /// re-tagged under that app's bundle ID namespace and carrying the owner's
    /// PID as `sourcePID`. `isMovable` becomes true for the alias, so the
    /// Layout editor drag (and `MenuBarItemManager.move(...)`'s inner guard)
    /// proceed; AppKit repositions the slot by `windowID`. The post-move
    /// `cacheItemsRegardless` writes the app-owned identifier into
    /// `savedSectionOrder` once the source-PID cache catches up, or AppKit's
    /// own autosave position holds the slot in place meanwhile.
    ///
    /// The bounded AX snapshot (`maxSnapshotDuration` = 500 ms) runs at most
    /// once per drag: a successful alias flips `isEnabled` to `true` so
    /// subsequent `mouseDragged` events skip the guard, and a failed attempt
    /// hands its correlated identity (when it found one) to
    /// ``logMoveRefusal(correlatedIdentity:)`` so the refusal path does not
    /// pay for the same snapshot again.
    private func aliasForUnresolvedControlCenterPlaceholder(
    ) -> (alias: MenuBarItem?, correlatedIdentity: AXIdentityCatalog.AXItemIdentity?) {
        precondition(item.immovabilityReason == .unresolvedControlCenterPlaceholder)

        let hosts = ["com.apple.controlcenter", "com.apple.systemuiserver"]
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        guard !hosts.isEmpty else { return (nil, nil) }

        let snapshot = AXIdentityCatalog.snapshot(hosts: hosts)
        let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        guard let identity = AXIdentityCatalog.identity(for: bounds, in: snapshot) else {
            Self.diagLog.warning(
                "Move alias: AX correlation found no confident identity for \(item.logString) (windowID=\(item.windowID))"
            )
            return (nil, nil)
        }

        let hostBundleIDs: Set = ["com.apple.controlcenter", "com.apple.systemuiserver"]
        guard let bundleID = UnresolvedPlaceholderAlias.appBundleID(
            from: identity,
            excluding: hostBundleIDs,
            thawBundleID: Constants.bundleIdentifier
        ) else {
            Self.diagLog.warning(
                "Move alias: AX names \(item.logString) (windowID=\(item.windowID)) as identifier=\(identity.identifier ?? "nil"), title=\(identity.title ?? "nil"), help=\(identity.help ?? "nil"); none is a non-host bundle identifier"
            )
            return (nil, identity)
        }

        guard
            let hostApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
            hostApp.processIdentifier != 0
        else {
            Self.diagLog.warning(
                "Move alias: AX named \(item.logString) (windowID=\(item.windowID)) as \(bundleID), but no running application matches that bundle ID"
            )
            return (nil, identity)
        }

        let alias = UnresolvedPlaceholderAlias.aliasedItem(
            for: item,
            appBundleID: bundleID,
            hostPID: hostApp.processIdentifier
        )
        return (alias, identity)
    }

    /// Provides an alert to display when a menu bar item is unresponsive.
    func provideAlertForUnresponsiveItem() -> NSAlert {
        let alert = provideAlertForDisabledItem()
        alert.informativeText = String(localized: "\(item.displayName) is unresponsive. Until it is restarted, it cannot be moved. Movement of other menu bar items may also be affected until this is resolved.")
        return alert
    }

    override func draw(_: NSRect) {
        if !isDraggingPlaceholder {
            let triggerControlled = isTriggerControlled
            if let capturedImage = cachedImage?.nsImage {
                capturedImage.draw(
                    in: bounds,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: triggerControlled
                        ? Metrics.triggerControlledFraction
                        : (isEnabled ? 1.0 : 0.67)
                )
            } else {
                drawPlaceholder()
            }
            if triggerControlled {
                drawTriggerBadge()
            }
            if Bridging.isProcessUnresponsive(item.ownerPID) {
                let warningImage = NSImage.warning
                let width = Metrics.unresponsiveBadgeWidth
                let scale = width / warningImage.size.width
                let size = CGSize(
                    width: width,
                    height: warningImage.size.height * scale
                )
                warningImage.draw(
                    in: CGRect(
                        x: bounds.maxX - size.width,
                        y: bounds.minY,
                        width: size.width,
                        height: size.height
                    )
                )
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        tooltipController.cancel()

        // #905 fallback: before refusing an `unresolvedControlCenterPlaceholder`
        // drag, attempt to re-tag the slot with its app-owned identity (when
        // Control Center's AX tree already names the owning app for the
        // slot's frame). On a confident hit the alias becomes the view's
        // effective item and `isEnabled` flips to `true`, so the guard below
        // passes and `MenuBarItemManager.move(...)`'s inner `isMovable`
        // guard (keyed off the same alias) does too. On a miss or a static
        // prohibition the guard falls through to the alert path as before.
        var correlatedIdentity: AXIdentityCatalog.AXItemIdentity?
        if !isEnabled,
           item.immovabilityReason == .unresolvedControlCenterPlaceholder
        {
            let attempt = aliasForUnresolvedControlCenterPlaceholder()
            correlatedIdentity = attempt.correlatedIdentity
            if let alias = attempt.alias {
                Self.diagLog.info(
                    "Move enabled for \(item.logString) via AX-correlated identity: re-tagged as \(alias.uniqueIdentifier) (sourcePID=\(alias.sourcePID.map(String.init) ?? "nil")); windowID=\(item.windowID)"
                )
                aliasedItem = alias
                isEnabled = true
            }
        }

        guard isEnabled else {
            let axResolvedName = logMoveRefusal(correlatedIdentity: correlatedIdentity)
            let alert = provideAlertForDisabledItem(axResolvedName: axResolvedName)
            alert.runModal()
            return
        }

        guard !Bridging.isProcessUnresponsive(item.ownerPID) else {
            Self.diagLog.warning(
                "Move refused for \(item.logString): owner process \(item.ownerPID) is unresponsive; uniqueIdentifier=\(item.uniqueIdentifier)"
            )
            let alert = provideAlertForUnresponsiveItem()
            alert.runModal()
            return
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: draggingImage())

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func preferredSize(for image: MenuBarItemImageCache.CapturedImage?) -> CGSize {
        Self.preferredSize(for: item, image: image)
    }

    private static func preferredSize(
        for item: MenuBarItem,
        image: MenuBarItemImageCache.CapturedImage?
    ) -> CGSize {
        if let image {
            return image.scaledSize
        }

        let width = item.bounds.width.clamped(to: Metrics.minWidth ... Metrics.maxWidth)
        let height = max(item.bounds.height, Metrics.minHeight)
        return CGSize(width: width, height: height)
    }

    /// Routed through ``MenuBarItemIconFallback`` so the layout bar and the
    /// Thaw Bar substitute the same image for the same item, and so both
    /// share its per-process icon cache.
    @MainActor
    private static func makePlaceholderImage(for item: MenuBarItem) -> NSImage? {
        MenuBarItemIconFallback.image(for: item)
    }

    /// Draws the marker identifying a trigger-owned item. Placed at the
    /// leading edge so it never collides with the unresponsive badge, which
    /// owns the trailing edge and can apply to the same item.
    private func drawTriggerBadge() {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor])
        guard
            let badge = NSImage(
                systemSymbolName: "bolt.fill",
                accessibilityDescription: String(localized: "Controlled by a trigger")
            )?.withSymbolConfiguration(configuration)
        else {
            return
        }
        let width = Metrics.triggerBadgeWidth
        let scale = width / badge.size.width
        let size = CGSize(width: width, height: badge.size.height * scale)
        badge.draw(
            in: CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: size.width,
                height: size.height
            )
        )
    }

    private func drawPlaceholder() {
        let placeholderRect = bounds.insetBy(
            dx: Metrics.placeholderHorizontalInset,
            dy: Metrics.placeholderVerticalInset
        )
        let backgroundPath = NSBezierPath(
            roundedRect: placeholderRect,
            xRadius: Metrics.placeholderCornerRadius,
            yRadius: Metrics.placeholderCornerRadius
        )
        NSColor.quaternaryLabelColor.withAlphaComponent(0.35).setFill()
        backgroundPath.fill()

        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        guard let placeholderImage else {
            return
        }

        let iconBounds = placeholderRect.insetBy(
            dx: Metrics.iconInset,
            dy: Metrics.iconInset
        )
        let iconSide = min(iconBounds.width, iconBounds.height)
        guard iconSide > 0 else {
            return
        }

        let iconRect = CGRect(
            x: placeholderRect.midX - (iconSide / 2),
            y: placeholderRect.midY - (iconSide / 2),
            width: iconSide,
            height: iconSide
        )

        if placeholderImage.isTemplate {
            let tinted = placeholderImage.copy() as? NSImage
            tinted?.isTemplate = true
            NSColor.secondaryLabelColor.set()
            tinted?.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: isEnabled ? 0.8 : 0.5
            )
        } else {
            placeholderImage.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: isEnabled ? 0.9 : 0.5
            )
        }
    }

    private func placeholderBitmapImage() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: Layout Bar Item Pasteboard Type

extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Constants.bundleIdentifier).layout-bar-item")
}
