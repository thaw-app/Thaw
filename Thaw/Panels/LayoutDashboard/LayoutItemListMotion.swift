//
//  LayoutItemListMotion.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Observation
import SwiftUI
import ThawUI

/// How far the list scrolls on each frame while a drag rests near its top or bottom edge.
nonisolated enum LayoutListAutoscroll {
    /// The band at each edge that scrolls, in points.
    static let edge: CGFloat = 36
    /// The fastest step, with the pointer at or past the edge.
    static let maxStep: CGFloat = 18

    /// Negative scrolls up, positive down, zero outside both bands. Deeper in a band scrolls faster.
    static func step(pointerY: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard viewportHeight > edge * 2 else { return 0 }
        if pointerY < edge {
            return -maxStep * min(1, (edge - pointerY) / edge)
        }
        if pointerY > viewportHeight - edge {
            return maxStep * min(1, (pointerY - (viewportHeight - edge)) / edge)
        }
        return 0
    }

    /// The offset after a step, kept inside the content.
    static func offset(_ offset: CGFloat, by step: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        min(max(0, offset + step), max(0, contentHeight - viewportHeight))
    }
}

/// The list's motion around a move: rows that moved flash where they landed, and a drag near
/// the edge scrolls the list.
@MainActor
@Observable
final class LayoutListMotion {
    struct Scroll: Equatable {
        var offset: CGFloat = 0
        var viewportHeight: CGFloat = 0
        var contentHeight: CGFloat = 0
    }

    /// The token makes a second move of the same row scroll again.
    struct ScrollRequest: Equatable {
        let id: String
        let token: Int
    }

    /// Rows lit for a moment after they moved.
    private(set) var flashing: Set<String> = []
    /// The first moved row, which the list scrolls to.
    private(set) var scrollTarget: ScrollRequest?
    /// A drag down the checkboxes under way. Only the rows read it, so a sweep redraws them and not the list.
    var sweep: LayoutCheckboxSweep?

    /// Each row's vertical span in the list. Unobserved: a gap opening must not rebuild the list.
    @ObservationIgnored var rowSpans: [String: ClosedRange<CGFloat>] = [:]

    @ObservationIgnored var scroll = Scroll()
    /// Moves the list to an offset. The scroll tracking sets it, so the pane holds no scroll state.
    @ObservationIgnored var scrollTo: (CGFloat) -> Void = { _ in }
    /// The scroll view's top in the window's content, top-down.
    @ObservationIgnored var viewportTop: CGFloat = 0
    @ObservationIgnored private var pending: [String] = []
    @ObservationIgnored private var pendingFallback: Task<Void, Never>?
    @ObservationIgnored private var flashToken = 0
    /// When a sweep last moved a batch, so the checkbox it ended on doesn't move them again.
    @ObservationIgnored private var batchSweepEnd: ContinuousClock.Instant?
    @ObservationIgnored private var autoscroll: Task<Void, Never>?

    /// Flashes a landed move's rows when the bar reports it, or after 250 ms if the report came first.
    func noteMoved(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        pending = ids
        pendingFallback?.cancel()
        pendingFallback = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.revealPending()
        }
    }

    /// Called when the sections change: lights the rows the last move carried.
    func revealPending() {
        guard !pending.isEmpty else { return }
        pendingFallback?.cancel()
        pendingFallback = nil
        flashToken &+= 1
        let token = flashToken
        flashing = Set(pending)
        scrollTarget = pending.first.map { ScrollRequest(id: $0, token: token) }
        pending = []
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, flashToken == token else { return }
            flashing = []
            scrollTarget = nil
        }
    }

    func noteBatchSweepEnded() {
        batchSweepEnd = .now
    }

    /// Whether a checkbox click belongs to a sweep over other rows, under way or just ended.
    /// The click and the drag's end arrive in either order.
    func isSweepClick() -> Bool {
        if let sweep, sweep.covered.contains(where: { $0 != sweep.startID }) {
            return true
        }
        guard let end = batchSweepEnd else { return false }
        return ContinuousClock.now - end < .milliseconds(500)
    }

    /// Scrolls while the mouse button is down and the pointer rests near an edge.
    /// pointer gets the pointer's height in the content after each step.
    func startAutoscroll(pointer: @escaping (CGFloat) -> Void = { _ in }) {
        autoscroll?.cancel()
        autoscroll = Task { @MainActor [weak self] in
            while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0, let self {
                if let y = pointerInViewport() {
                    let step = LayoutListAutoscroll.step(pointerY: y, viewportHeight: scroll.viewportHeight)
                    if step != 0 {
                        let next = LayoutListAutoscroll.offset(
                            scroll.offset,
                            by: step,
                            contentHeight: scroll.contentHeight,
                            viewportHeight: scroll.viewportHeight
                        )
                        if next != scroll.offset {
                            scroll.offset = next
                            scrollTo(next)
                            pointer(y + next)
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// The pointer's height inside the scroll view, top-down, read from the key window.
    private func pointerInViewport() -> CGFloat? {
        guard let window = NSApp.keyWindow, let content = window.contentView else { return nil }
        let local = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let top = content.isFlipped ? local.y : content.bounds.height - local.y
        return top - viewportTop
    }
}

/// Feeds the list's scroll position and frame to its motion, and scrolls to rows that just moved.
/// It owns the scroll position: SwiftUI writes it on every scroll frame, and in the pane that rebuilt the list.
struct LayoutListScrollTracking: ViewModifier {
    let motion: LayoutListMotion
    let proxy: ScrollViewProxy
    @State private var position = ScrollPosition()

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: LayoutListMotion.Scroll.self) { geometry in
                LayoutListMotion.Scroll(
                    offset: geometry.contentOffset.y,
                    viewportHeight: geometry.containerSize.height,
                    contentHeight: geometry.contentSize.height
                )
            } action: { _, scroll in motion.scroll = scroll }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { motion.viewportTop = $0 }
            .onAppear {
                let position = $position
                motion.scrollTo = { position.wrappedValue.scrollTo(y: $0) }
            }
            .onChange(of: motion.scrollTarget) { _, target in
                guard let target else { return }
                withThawAnimation(ThawMotion.settle) { proxy.scrollTo(target.id) }
            }
    }
}
