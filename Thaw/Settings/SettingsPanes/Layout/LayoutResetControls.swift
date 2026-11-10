//
//  LayoutResetControls.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

struct LayoutResetControls: View {
    let itemManager: MenuBarItemManager
    let controlItemsDisabled: Bool
    let alwaysHiddenEnabled: Bool

    var body: some View {
        ThawSection {
            Text("Reset menu bar layout")
        } content: {
            LayoutResetFlow(
                itemManager: itemManager,
                controlItemsDisabled: controlItemsDisabled,
                alwaysHiddenEnabled: alwaysHiddenEnabled
            )
        }
    }
}

/// Reset, in its titled section: a sentence beside a glass button.
struct LayoutResetFlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let itemManager: MenuBarItemManager
    let controlItemsDisabled: Bool
    let alwaysHiddenEnabled: Bool

    @State private var isResetting = false
    @State private var isConfirming = false
    @State private var status: ResetStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            HStack(alignment: .top, spacing: ThawSpacing.inset) {
                Text("Moves every movable item except the \(Constants.displayName) icon to the selected section, just like a fresh install.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                Spacer(minLength: 16)
                trigger
                    .disabled(isResetting || controlItemsDisabled)
            }

            if let status {
                HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.compact) {
                    if status.isError {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                    Text(status.message)
                        .foregroundStyle(status.isError ? Color.primary : ThawInk.supporting)
                }
                .font(ThawType.footnote)
                .transition(resetTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            "Choose where to move the menu bar items:",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Visible") { reset(to: .visible) }
            Button("Hidden") { reset(to: .hidden) }
            if alwaysHiddenEnabled {
                Button("Always Hidden") { reset(to: .alwaysHidden) }
            }
            Button("Cancel", role: .cancel) { /* The dialog dismisses itself; cancelling needs no other work. */ }
        }
    }

    private var trigger: some View {
        Button {
            isConfirming = true
        } label: {
            if isResetting {
                ProgressView().controlSize(.small)
            } else {
                Text("Reset Layout…")
            }
        }
        .buttonStyle(.settingsGlass)
    }

    private var resetTransition: AnyTransition {
        .fade(reduceMotion: reduceMotion, animation: ThawMotion.settle)
    }

    private func reset(to target: ResetTarget) {
        isConfirming = false
        isResetting = true
        status = nil

        Task { @MainActor in
            let newStatus: ResetStatus
            do {
                let failures = switch target {
                case .visible: try await itemManager.resetLayoutToVisible()
                case .hidden: try await itemManager.resetLayoutToFreshState()
                case .alwaysHidden: try await itemManager.resetLayoutToAlwaysHidden()
                }
                newStatus = .completed(target: target, failures: failures)
            } catch {
                newStatus = .thrown(error)
            }
            status = newStatus
            if newStatus.isAnnounced {
                AccessibilityAnnouncements.post(newStatus.message)
            }
            isResetting = false
        }
    }

    /// Internal for tests that prevent untouched menu bars from being reported as reset.
    enum ResetTarget: Equatable {
        case visible
        case hidden
        case alwaysHidden
    }

    enum ResetStatus: Equatable {
        case success(ResetTarget)
        /// The reset never started: the menu bar backend is not running, so
        /// nothing was moved and there is nothing to check.
        case notRun
        case partialFailure(Int)
        case failure(String)

        /// Zero failed moves means success only for resets that ran; unstarted resets must not reach here.
        static func completed(target: ResetTarget, failures: Int) -> ResetStatus {
            failures == 0 ? .success(target) : .partialFailure(failures)
        }

        /// engineNotRunning means no attempt, not a failed sweep; report notRun rather than claiming items moved.
        static func thrown(_ error: any Error) -> ResetStatus {
            if case .engineNotRunning? = error as? MenuBarItemManager.LayoutResetError {
                return .notRun
            }
            return .failure(error.localizedDescription)
        }

        /// Announce completion outcomes for VoiceOver; underlying failure text is displayed but not spoken.
        var isAnnounced: Bool {
            switch self {
            case .success, .notRun, .partialFailure: true
            case .failure: false
            }
        }

        var message: String {
            switch self {
            case .success(.hidden): String(localized: "Layout reset. Items were moved to the Hidden section.")
            case .success(.alwaysHidden): String(localized: "Layout reset. Items were moved to the Always Hidden section.")
            case .success(.visible): String(localized: "Layout reset. Items were moved to the Visible section.")
            case .notRun: String(localized: "Nothing was moved: \(Constants.displayName) is not managing the menu bar yet. Try again once your menu bar items appear.")
            case let .partialFailure(count): String(localized: "Reset completed with \(count) items that could not be moved. Check the menu bar and try again if needed.")
            case let .failure(message): String(localized: "Reset failed: \(message)")
            }
        }

        var isError: Bool {
            switch self {
            case .success: false
            case .notRun, .partialFailure, .failure: true
            }
        }
    }
}

/// Shown instead of the editor while macOS auto-hides the menu bar.
struct CannotArrangeLayoutView: View {
    var body: some View {
        ThawEmptyState(
            systemImage: "menubar.rectangle",
            title: "\(Constants.displayName) cannot arrange menu bar items in automatically hidden menu bars.",
            caption: "Turn off automatic menu bar hiding in System Settings > Control Center"
        )
    }
}
