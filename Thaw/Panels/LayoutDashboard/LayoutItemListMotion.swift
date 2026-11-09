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

    /// Rows lit for a moment after they moved.
    private(set) var flashing: Set<String> = []
    /// The first moved row, which the list scrolls to.
    private(set) var scrollTarget: String?
    /// A drag down the checkboxes under way. Only the rows read it, so a sweep redraws them and not the list.
    var sweep: LayoutCheckboxSweep?

    /// Each row's vertical span in the list. Unobserved: a gap opening must not rebuild the list.
    @ObservationIgnored var rowSpans: [String: ClosedRange<CGFloat>] = [:]

    @ObservationIgnored var scroll = Scroll()
    /// The scroll view's top in the window's content, top-down.
    @ObservationIgnored var viewportTop: CGFloat = 0
    @ObservationIgnored private var pending: [String] = []
    @ObservationIgnored private var flashToken = 0
    @ObservationIgnored private var autoscroll: Task<Void, Never>?

    /// Remembers what a move from the list is moving, to flash once the bar reports it.
    func noteMoved(_ ids: [String]) {
        pending = ids
    }

    /// Called when the sections change: lights the rows the last move carried.
    func revealPending() {
        guard !pending.isEmpty else { return }
        flashing = Set(pending)
        scrollTarget = pending.first
        pending = []
        flashToken &+= 1
        let token = flashToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, flashToken == token else { return }
            flashing = []
            scrollTarget = nil
        }
    }

    /// Scrolls while the mouse button is down and the pointer rests near an edge.
    /// scrollTo moves the list; pointer gets the pointer's height in the content after each step.
    func startAutoscroll(scrollTo: @escaping (CGFloat) -> Void, pointer: @escaping (CGFloat) -> Void = { _ in }) {
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
struct LayoutListScrollTracking: ViewModifier {
    let motion: LayoutListMotion
    @Binding var position: ScrollPosition
    let proxy: ScrollViewProxy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .onChange(of: motion.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(reduceMotion ? nil : ThawMotion.settle) { proxy.scrollTo(target) }
            }
    }
}
