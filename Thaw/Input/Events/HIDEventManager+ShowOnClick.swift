//
//  HIDEventManager+ShowOnClick.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation
import MenuBarModel
import ThawCapture

extension HIDEventManager {
    /// Tracks the state of the swallow/disarm lifecycle for the click guard tap.
    nonisolated enum GuardMouseUpState {
        /// No mouse-down has been swallowed; guard tap is idle between clicks.
        case idle
        /// A mouse-down was swallowed; swallow the matching mouse-up but keep
        /// the guard armed afterward (double-click window still open).
        case swallowing
        /// A mouse-down was swallowed and teardown is pending; swallow the
        /// matching mouse-up then fully disarm the guard.
        case swallowingThenDisarm
    }

    /// The input driving a GuardMouseUpState transition.
    nonisolated enum GuardMouseUpSignal {
        /// A leftMouseUp arrived while the guard tap was armed.
        case mouseUp
        /// A leftMouseDown landed in the guard region and should be
        /// swallowed while keeping the guard armed for the following
        /// mouse-up.
        case swallow
        /// A leftMouseDown landed in the guard region and completed an
        /// action (double-click reveal, option-click toggle) that also
        /// requires disarming the guard once the matching mouse-up is
        /// swallowed.
        case swallowThenDisarm
        /// The guard's deadline expired, or the guard is being torn down,
        /// while a mouse button may still be held; disarming must be
        /// deferred until the pending mouse-up is swallowed.
        case disarmRequested
    }

    /// Next GuardMouseUpState for the guard tap. Pure, so the swallow/disarm
    /// contract is testable without a live CGEventTap.
    static nonisolated func nextGuardState(
        from current: GuardMouseUpState,
        given signal: GuardMouseUpSignal
    ) -> GuardMouseUpState {
        switch signal {
        case .mouseUp:
            return .idle
        case .swallow:
            return .swallowing
        case .swallowThenDisarm:
            return .swallowingThenDisarm
        case .disarmRequested:
            return current == .idle ? .idle : .swallowingThenDisarm
        }
    }

    // MARK: Handle Show On Click

    /// The gesture is timed from pendingMenuBarClick rather than the event's
    /// clickCount, which cannot see a first click that revealed nothing.
    func handleShowOnClick(
        appState: AppState,
        screen: NSScreen,
        clickLocation: CGPoint,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        guard configuration.showOnClick else {
            return
        }

        // No items on screen means a fullscreen app auto-hid the bar and the
        // click hit the trigger zone. currentSystemPresentationOptions is
        // per-app and cannot see another app's fullscreen state.
        if !screen.isSystemMenuBarVisible() {
            Self.diagLog.debug("handleShowOnClick: suppressing, no menu bar items on-screen for active space")
            return
        }

        guard isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) else {
            return
        }
        let hiddenIsOut = appState.menuBarManager.section(withName: .hidden)?.isHidden == false
        Self.diagLog.debug(
            "click: empty menu bar space, hidden section \(hiddenIsOut ? "shown" : "hidden"), hover pending \(String(describing: pendingHoverAction))"
        )

        // Defer to widgets such as notch overlays that the items query misses;
        // the AX hit-test finds the real element under the cursor.
        if isCursorOverForeignWidgetUIElement() {
            Self.diagLog.debug("handleShowOnClick: suppressing, cursor over foreign UI element")
            return
        }

        // A second click inside the double-click window is the always-hidden
        // gesture, timed here because clickCount cannot see a quiet first click.
        if let pending = pendingMenuBarClick,
           pending.displayID == screen.displayID,
           ContinuousClock.now - pending.timestamp < .seconds(NSEvent.doubleClickInterval)
        {
            cancelPendingMenuBarClick()
            // Not re-armed: the first click's guard is still inside its window,
            // and re-arming resets guardMouseUpState, stranding the mouse-up.
            Self.diagLog.debug("click: second click, toggling always-hidden")
            revealSection(.alwaysHidden)
            return
        }

        if modifierFlags.contains(.control) {
            cancelPendingMenuBarClick()
            disarmShowOnClickGuard()
            handleSecondaryContextMenu(appState: appState, screen: screen, modifierFlags: modifierFlags)
            return
        }

        if modifierFlags.contains(.option) {
            cancelPendingMenuBarClick()
            disarmShowOnClickGuard()
            if let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
               alwaysHiddenSection.isEnabled
            {
                revealSection(.alwaysHidden)
            }
            return
        }

        guard
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            hiddenSection.isEnabled
        else {
            return
        }

        // With always-hidden showing in the Thaw Bar, a plain click closes it
        // rather than switching the bar to the hidden section.
        if appState.menuBarManager.thawBarPanel.currentSection == .alwaysHidden,
           let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
        {
            cancelPendingMenuBarClick()
            disarmShowOnClickGuard()
            Self.diagLog.debug("click: closing always-hidden in the Thaw Bar")
            Task { alwaysHiddenSection.hide() }
            return
        }

        // Already out, or the Thaw Bar's outside-click monitor closed it on this
        // press: put it away and don't reveal it again.
        if !hiddenSection.isHidden || MousePressLedger.shared.currentPressDismissedBar {
            cancelPendingMenuBarClick()
            disarmShowOnClickGuard()
            Self.diagLog.debug("click: hiding the hidden section")
            Task { hiddenSection.hide() }
            return
        }
        Self.diagLog.debug("click: revealing the hidden section")

        // Reveal at once instead of waiting out the double-click interval; a
        // second click still reveals always-hidden on top.
        guard appState.menuBarManager.section(withName: .alwaysHidden)?.isEnabled == true else {
            disarmShowOnClickGuard()
            revealSection(.hidden)
            return
        }

        // Arm the guard first, so the tap is live before the second click's
        // mouse-down can reach the system.
        armShowOnClickGuard(screen: screen, at: clickLocation)
        revealSection(.hidden)
        rememberPendingMenuBarClick(on: screen)
    }

    /// Remembers a first click in empty menu bar space for the length of the
    /// double-click window, so a second click there can ask for always-hidden.
    /// The first click has already revealed the hidden section.
    private func rememberPendingMenuBarClick(on screen: NSScreen) {
        cancelPendingMenuBarClick()
        let timestamp = ContinuousClock.now
        pendingMenuBarClick = (timestamp, screen.displayID)
        pendingMenuBarClickTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            } catch {
                return
            }
            guard let self, self.pendingMenuBarClick?.timestamp == timestamp else { return }
            self.pendingMenuBarClick = nil
            self.pendingMenuBarClickTask = nil
        }
    }

    /// Forgets the first click, so a superseding gesture is not read as its
    /// second.
    func cancelPendingMenuBarClick() {
        pendingMenuBarClickTask?.cancel()
        pendingMenuBarClickTask = nil
        pendingMenuBarClick = nil
    }

    /// Drops a pending smart rehide, so a section the user has just revealed
    /// is not put away by the click that preceded the reveal.
    func cancelSmartRehide() {
        rehideController?.note(.inputReveal)
    }

    /// Reveals section at once, the way a scroll does, or puts it away if
    /// it is already out.
    ///
    /// Not under the reveal mask: the mask waits for a fresh capture, so a
    /// click would pay a cold stream start that a scroll does not.
    private func revealSection(_ name: MenuBarSection.Name) {
        guard let appState, let section = appState.menuBarManager.section(withName: name) else { return }
        cancelSmartRehide()
        // A click takes the section over from hover, with the full rehide delay.
        isHoverReveal = false
        // Stamped first: a capture prewarm woken by this click must not undo
        // the reveal the user asked for.
        appState.menuBarManager.noteUserRevealOwnership()
        if section.isHidden {
            section.show()
        } else {
            section.hide()
        }
    }

    private func armShowOnClickGuard(screen: NSScreen, at clickLocation: CGPoint) {
        guard let menuBarHeight = screen.getMenuBarHeight() else {
            disarmShowOnClickGuard()
            return
        }

        let protectionWidth = max(44, menuBarHeight * 2)
        let protectionHeight = menuBarHeight + 6
        let minY = screen.frame.maxY - menuBarHeight - 3
        showOnClickGuardRegion = CGRect(
            x: clickLocation.x - protectionWidth / 2,
            y: minY,
            width: protectionWidth,
            height: protectionHeight
        )
        showOnClickGuardDisplayID = screen.displayID
        showOnClickGuardDeadline = .now + .seconds(NSEvent.doubleClickInterval)
        guardMouseUpState = .idle

        // Validate (and recreate if needed) before enabling; a stale Mach port
        // would silently no-op on start() and leave the guard tap inactive.
        guard showOnClickGuardTap.ensureValid() else {
            disarmShowOnClickGuard()
            return
        }
        showOnClickGuardTap.start()

        clickTask?.cancel()
        let token = UUID()
        clickTaskToken = token
        clickTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            } catch {
                return
            }
            await MainActor.run {
                guard self?.clickTaskToken == token else { return }
                self?.expireShowOnClickGuard()
            }
        }
    }

    private func expireShowOnClickGuard() {
        let deferredState = Self.nextGuardState(from: guardMouseUpState, given: .disarmRequested)
        if deferredState != .idle {
            // Mouse button is still held; defer full teardown until the
            // swallowed mouse-up arrives so the tap stays active.
            guardMouseUpState = deferredState
            showOnClickGuardDeadline = nil
            showOnClickGuardRegion = nil
            showOnClickGuardDisplayID = nil
            clickTask = nil
            clickTaskToken = nil
            scheduleDeferredShowOnClickGuardDisarm()
            return
        }

        disarmShowOnClickGuard()
    }

    func disarmShowOnClickGuard() {
        // Defer disarming until the swallowed mouse-up arrives, so a stray
        // mouse-up never reaches the system.
        let deferredState = Self.nextGuardState(from: guardMouseUpState, given: .disarmRequested)
        if deferredState != .idle {
            guardMouseUpState = deferredState
            scheduleDeferredShowOnClickGuardDisarm()
            return
        }

        clickTask?.cancel()
        clickTask = nil
        clickTaskToken = nil
        showOnClickGuardDeferredDisarmTask?.cancel()
        showOnClickGuardDeferredDisarmTask = nil
        showOnClickGuardDeferredDisarmToken = nil
        showOnClickGuardDeadline = nil
        showOnClickGuardRegion = nil
        showOnClickGuardDisplayID = nil
        guardMouseUpState = .idle
        showOnClickGuardTap.stop()
    }

    private func scheduleDeferredShowOnClickGuardDisarm() {
        showOnClickGuardDeferredDisarmTask?.cancel()
        let token = UUID()
        showOnClickGuardDeferredDisarmToken = token
        showOnClickGuardDeferredDisarmTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            await MainActor.run {
                guard self?.showOnClickGuardDeferredDisarmToken == token else { return }
                guard self?.guardMouseUpState == .swallowingThenDisarm else { return }
                self?.showOnClickGuardDeferredDisarmToken = nil
                self?.showOnClickGuardDeferredDisarmTask = nil
                self?.guardMouseUpState = .idle
                self?.disarmShowOnClickGuard()
            }
        }
    }

    /// Tears down the guard if its deadline has passed. Call this before
    /// reading isShowOnClickGuardActive in contexts that need to react
    /// to expiry (e.g. the tap callback, hit-test helpers).
    func expireShowOnClickGuardIfNeeded() {
        guard let deadline = showOnClickGuardDeadline, deadline <= .now else {
            return
        }
        expireShowOnClickGuard()
    }

    /// Whether the guard is armed and within its deadline. Does not apply
    /// expiry; call expireShowOnClickGuardIfNeeded() first for that.
    var isShowOnClickGuardActive: Bool {
        guard let deadline = showOnClickGuardDeadline else {
            return false
        }
        return deadline > .now && showOnClickGuardRegion != nil
    }

    /// Whether the guard tap should swallow a click at clickLocation. Pure, so
    /// it is testable without a live CGEventTap.
    ///
    /// isDoubleClick does not gate this: the first mouse-down is not yet known
    /// to be part of a double click.
    static nonisolated func shouldSwallowClick(
        clickLocation: CGPoint,
        guardRegion: CGRect,
        isDoubleClick _: Bool,
        withinDoubleClickWindow: Bool
    ) -> Bool {
        guard withinDoubleClickWindow else {
            return false
        }
        return guardRegion.contains(clickLocation)
    }

    func isPointInsideShowOnClickGuardRegion(_ point: CGPoint) -> Bool {
        expireShowOnClickGuardIfNeeded()
        guard let region = showOnClickGuardRegion,
              let displayID = showOnClickGuardDisplayID
        else {
            return false
        }

        guard NSScreen.screenWithMouse?.displayID == displayID else {
            return false
        }

        return Self.shouldSwallowClick(
            clickLocation: point,
            guardRegion: region,
            isDoubleClick: false,
            withinDoubleClickWindow: isShowOnClickGuardActive
        )
    }

    // MARK: Handle Smart Rehide

    /// The rehide controller checks these click-time conditions only under smart rehide.
    func handleSmartRehide(
        with event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) {
        rehideController?.note(.outsideClick { [self] in
            // Clicking the visible control item or the Thaw Bar drives the sections, so it never rehides them.
            if
                let controlItem = appState.menuBarManager.controlItem(withName: .visible),
                event.window === controlItem.window
            {
                return false
            }
            if event.window === appState.menuBarManager.thawBarPanel {
                return false
            }

            // Clicks on the menu bar itself belong to the show-on-click path.
            return appState.menuBarManager.hasVisibleSection
                && !isMouseInsideMenuBar(screen: screen)
        })
    }
}
