//
//  ControlItemPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

// MARK: - Hiding state

extension ControlItem {
    /// Which side of its section a control item currently represents.
    ///
    /// A control item does not own its section's visibility, MenuBarSection
    /// does, but every appearance decision the item makes is a function of this
    /// value, so it is modelled explicitly rather than derived from AppKit.
    nonisolated enum HidingState {
        /// The section behind this control item is revealed.
        case showSection
        /// The section behind this control item is concealed.
        case hideSection
    }
}

// MARK: - Section divider presentation

extension ControlItem {
    /// The visual treatment a section-divider control item should adopt.
    nonisolated enum SectionDividerPresentation: Equatable {
        /// Collapse the status item to nothing.
        case hidden
        /// Draw the small interactive chevron that separates two sections.
        case chevron
    }

    /// Decides how a section divider should present itself.
    ///
    /// Kept free of AppKit state so the rule stays readable and checkable on its
    /// own: a divider is only ever drawn for a section that is currently
    /// revealed, and only when the user has asked for a divider at all.
    static nonisolated func sectionDividerPresentation(
        state: HidingState,
        style: SectionDividerStyle
    ) -> SectionDividerPresentation {
        switch state {
        case .hideSection:
            .hidden
        case .showSection:
            switch style {
            case .noDivider: .hidden
            case .chevron: .chevron
            }
        }
    }
}

// MARK: - Primary action intent

extension ControlItem {
    struct PrimaryActivationSequence {
        private var previous: (timestamp: TimeInterval, location: CGPoint, modifiers: NSEvent.ModifierFlags)?

        mutating func clickCount(
            at timestamp: TimeInterval,
            location: CGPoint,
            modifiers: NSEvent.ModifierFlags,
            interval: TimeInterval,
            enabled: Bool
        ) -> Int {
            guard enabled else {
                previous = nil
                return 1
            }
            if let previous,
               timestamp > previous.timestamp,
               timestamp - previous.timestamp <= interval,
               hypot(location.x - previous.location.x, location.y - previous.location.y) <= 4,
               modifiers == previous.modifiers
            {
                self.previous = nil
                return 2
            }
            previous = (timestamp, location, modifiers)
            return 1
        }
    }

    /// What a click on a control item is asking Thaw to do.
    nonisolated enum PrimaryActionIntent: Equatable {
        /// Toggle the section this control item belongs to.
        case toggleSection
        /// Reveal the always-hidden section.
        case showAlwaysHidden
        /// Flip the always-hidden section between revealed and concealed.
        case toggleAlwaysHidden
        /// Present the control item's context menu.
        case contextMenu
        /// Deliberately do nothing.
        case none
    }

    /// Resolves a click delivered through AppKit's target/action path.
    ///
    /// Modifier precedence: a double-click shortcut wins over any modifier,
    /// control opens the menu, and option reaches the always-hidden section only
    /// when the user has enabled that shortcut, otherwise the click is
    /// swallowed rather than falling through to a plain toggle.
    static nonisolated func primaryActionIntent(
        identifier: Identifier,
        modifierFlags: NSEvent.ModifierFlags,
        clickCount: Int,
        usesDoubleClick: Bool,
        usesOptionClick: Bool
    ) -> PrimaryActionIntent {
        if usesDoubleClick, clickCount > 1, identifier == .visible {
            return .showAlwaysHidden
        }
        if modifierFlags.contains(.control) {
            return .contextMenu
        }
        if modifierFlags.contains(.option) {
            return usesOptionClick ? .toggleAlwaysHidden : .none
        }
        return .toggleSection
    }

    /// Resolves the macOS 27 forwarded activation's modifiers: the recorded
    /// press state, then the forwarded event, then the live keyboard state.
    static nonisolated func resolvedPrimaryModifierFlags(
        pressModifiers: NSEvent.ModifierFlags?,
        eventModifiers: NSEvent.ModifierFlags?,
        liveModifiers: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        if let pressModifiers, !pressModifiers.isEmpty {
            return pressModifiers
        }
        if let eventModifiers, !eventModifiers.isEmpty {
            return eventModifiers
        }
        return liveModifiers
    }

    /// Resolves the semantic primary activation MenuBarAgent forwards on
    /// macOS 27.
    ///
    /// This differs from primaryActionIntent(identifier:modifierFlags:clickCount:usesDoubleClick:usesOptionClick:)
    /// in one respect: the control modifier is ignored. primaryActionTriggered
    /// arrives without an event of its own, so NSApp.currentEvent can hand
    /// back stale flags from an unrelated click. Control-click context menus
    /// reach HIDEventManager on leftMouseDown instead, and honouring a
    /// stale control bit here would swallow an ordinary toggle.
    static nonisolated func menuBarAgentPrimaryActionIntent(
        identifier: Identifier,
        modifierFlags: NSEvent.ModifierFlags,
        clickCount: Int,
        usesDoubleClick: Bool,
        usesOptionClick: Bool,
        diagLog: DiagLog? = nil
    ) -> PrimaryActionIntent {
        let intent: PrimaryActionIntent = if usesDoubleClick, clickCount > 1, identifier == .visible {
            .showAlwaysHidden
        } else if modifierFlags.contains(.option) {
            usesOptionClick ? .toggleAlwaysHidden : .none
        } else {
            .toggleSection
        }
        diagLog?.debug(
            """
            menuBarAgentPrimaryActionIntent: identifier=\(identifier.rawValue), \
            modifierFlags=\(modifierFlags), clickCount=\(clickCount), \
            usesDoubleClick=\(usesDoubleClick), usesOptionClick=\(usesOptionClick) → \(intent)
            """
        )
        return intent
    }
}

// MARK: - Runtime bridging predicates

extension ControlItem {
    /// Whether encoding is a type encoding Thaw recognizes for
    /// addTarget:action:forControlEvents:.
    ///
    /// The IMP is invoked through an unsafeBitCast to a
    /// (void, id, SEL, id, SEL, NSUInteger) C function, so the runtime's own
    /// description of the method has to agree before the call is made. Two
    /// spellings of the same signature are known to ship: the compact form and
    /// the offset-annotated arm64 form (v40@0:8@16:24Q32).
    static nonisolated func isSupportedAddTargetTypeEncoding(_ encoding: String) -> Bool {
        let knownSignatures = [
            (prefix: "v@:@:", suffix: "Q"),
            (prefix: "v40@0:8", suffix: "Q32"),
        ]
        return knownSignatures.contains { encoding.hasPrefix($0.prefix) && encoding.hasSuffix($0.suffix) }
    }

    /// A temporary status-item length that invalidates AppKit's layout without
    /// visibly resizing the item, or nil if the item has not been laid out yet.
    ///
    /// MenuBarAgent does not reliably notice a cross-process write to
    /// the preferred-position table until the owning status item's layout is
    /// invalidated. Pinning the item to the width it already renders at forces
    /// that pass. When the item is already pinned to exactly that width the
    /// assignment would be a no-op, so half a point is added to guarantee a
    /// change AppKit acts on, imperceptible on screen, but a real edit.
    static nonisolated func menuBarAgentLayoutNudgeLength(
        currentLength: CGFloat,
        renderedWidth: CGFloat
    ) -> CGFloat? {
        guard renderedWidth > 0 else {
            return nil
        }
        let alreadyPinnedToRenderedWidth = currentLength != NSStatusItem.variableLength
            && abs(currentLength - renderedWidth) <= 0.25
        return alreadyPinnedToRenderedWidth ? renderedWidth + 0.5 : renderedWidth
    }
}
