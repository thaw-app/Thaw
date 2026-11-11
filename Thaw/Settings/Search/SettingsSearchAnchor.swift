//
//  SettingsSearchAnchor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

extension View {
    /// Marks the row a settings search result opens: search scrolls it into
    /// view and flashes it. id is the result's SearchEntry id.
    func settingsSearchAnchor(_ id: String) -> some View {
        modifier(SettingsSearchAnchor(id: id))
    }
}

/// The row's scroll id and its flash.
private struct SettingsSearchAnchor: ViewModifier {
    /// Optional: rows are also hosted outside Settings, where there is nothing to flash.
    @Environment(AppState.self) private var appState: AppState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHighlighted = false

    let id: String

    func body(content: Content) -> some View {
        content
            .id(id)
            .background {
                RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
                    .fill(Color.accentColor.opacity(isHighlighted ? SettingsSearchFlash.opacity : 0))
                    .padding(-SettingsSearchFlash.outset)
                    .allowsHitTesting(false)
            }
            .onChange(of: appState?.navigationState.highlightedSettingsRow, initial: true) { _, row in
                guard row == id else { return }
                flash()
            }
    }

    private func flash() {
        withAnimation(SettingsSearchFlash.animation(reduceMotion: reduceMotion, appearing: true)) {
            isHighlighted = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: SettingsSearchFlash.duration)
            withAnimation(SettingsSearchFlash.animation(reduceMotion: reduceMotion, appearing: false)) {
                isHighlighted = false
            }
            if appState?.navigationState.highlightedSettingsRow == id {
                appState?.navigationState.highlightedSettingsRow = nil
            }
        }
    }
}

/// How a found row flashes: a short accent wash that fades, or simply shows
/// and hides under Reduce Motion.
enum SettingsSearchFlash {
    static let opacity = 0.18
    static let outset: CGFloat = 6
    static let duration = Duration.milliseconds(1400)

    static func animation(reduceMotion: Bool, appearing: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return appearing ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.6)
    }
}

/// Scrolls a search result's row into view once its page and tab have
/// switched, then hands it the flash and reads it to VoiceOver.
struct SettingsSearchScroller: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let navigationState: AppNavigationState
    @State private var disarm = SettingsSearchDisarm()

    /// The page and its tab render a beat after the selection changes.
    private static let settle = Duration.milliseconds(150)

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: navigationState.requestedSettingsRow) { _, row in
                guard let row else { return }
                reveal(row, with: proxy)
            }
        }
    }

    private func reveal(_ row: String, with proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: Self.settle)
            guard navigationState.requestedSettingsRow == row else { return }
            navigationState.requestedSettingsRow = nil
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                proxy.scrollTo(row, anchor: .center)
            }
            navigationState.highlightedSettingsRow = row
            if NSWorkspace.shared.isVoiceOverEnabled, let entry = SearchIndex.entry(withID: row) {
                AccessibilityAnnouncements.post(entry.titleText)
            }
            // A row that never rendered can't disarm the highlight itself, and would flash whenever it later appears.
            disarm.schedule(row, on: navigationState)
        }
    }
}

/// Clears a search jump's highlight once its flash is over. A newer jump cancels the pending
/// clear, so jumping to the same row again keeps its whole flash.
@MainActor
final class SettingsSearchDisarm {
    private var pending: Task<Void, Never>?

    func schedule(_ row: String, on navigationState: AppNavigationState, after delay: Duration = SettingsSearchFlash.duration) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, navigationState.highlightedSettingsRow == row else { return }
            navigationState.highlightedSettingsRow = nil
        }
    }
}
