//
//  SpacesSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

// MARK: - SpacesSettingsPane

/// Live controls for how macOS presents the system menu bar, per Space.
///
/// Everything here is a command, not a preference: the backend
/// (MenuBarPresentationControlling) has setters and no getters, the menu bar
/// agent owns the state for Thaw's process session and reverts it on quit, and
/// nothing is persisted.
///
/// The @State below is a UI echo of what the user asked for this session, not
/// a source of truth; a failed call reverts its mirror. The "This Space"
/// mirrors reset on Space change, because another Space's overrides cannot be
/// read back. The pane is gated on isSupported; a page of switches that
/// silently do nothing would be worse than one sentence explaining why.
struct SpacesSettingsPane: View {
    @Environment(AppState.self) private var appState

    /// The presentation seam. Resolved once per body evaluation rather than
    /// stored: the provider owns a single process-wide controller, and this is
    /// just a name for it.
    private var presentation: any MenuBarPresentationControlling {
        MenuBarPresentationProvider.current
    }

    var body: some View {
        ThawForm {
            SpacesControlsContent(activeSpaceID: activeSpaceID)
        }
    }

    /// The CGS Space identifier for the Space the user is looking at.
    ///
    /// Sourced from AppState.activeSpace, which the app already keeps
    /// current off NSWorkspace.activeSpaceDidChangeNotification (plus its own
    /// polling fallback), so this pane needs no space-tracking of its own and
    /// cannot disagree with the rest of the app about which Space is active.
    ///
    /// CGSSpaceID is an Int app-side while the presentation seam takes a
    /// UInt64; the bit-pattern conversion is deliberate, so a hypothetical
    /// negative identifier is passed through unchanged instead of trapping in
    /// a settings pane.
    private var activeSpaceID: UInt64 {
        UInt64(bitPattern: Int64(appState.activeSpace.spaceID))
    }
}

// MARK: - SpacesControlsContent

/// The Spaces session controls, without their own ThawForm so they can be
/// embedded as a section inside another pane (the Menu Bar Access surface).
/// SpacesSettingsPane wraps this in a ThawForm for its standalone use.
struct SpacesControlsContent: View {
    let activeSpaceID: UInt64

    private var presentation: any MenuBarPresentationControlling {
        MenuBarPresentationProvider.current
    }

    var body: some View {
        if presentation.isSupported {
            ThisSpaceSection(spaceID: activeSpaceID)
            AllSpacesSection()
            SessionScopeNotice()
        } else {
            UnsupportedSection()
        }
    }
}

/// Menu bar overrides scoped to one Space.
///
/// This is the part macOS has no UI for at all: System Settings' menu bar
/// controls are global, and the reveal-strip height is not exposed anywhere,
/// at any scope.
private struct ThisSpaceSection: View {
    /// The Space these controls act on. A change to this value means the user
    /// switched Spaces, which invalidates every mirror below.
    let spaceID: UInt64

    @State private var isHidden = false
    @State private var isAutoShowDisabled = false
    @State private var revealStripHeight = Self.defaultRevealStripHeight
    /// Set once the user has actually moved the slider. Without it the
    /// debounce task below would push the default height at the agent the
    /// first time the pane appears, an override nobody asked for.
    @State private var hasAdjustedRevealStrip = false
    @State private var failure: LocalizedStringKey?

    /// A plausible neutral starting point for the slider, not a reading of the
    /// system's current value, the seam has no getter. Labeled as such in the
    /// caption so the number is not mistaken for the truth.
    private static let defaultRevealStripHeight: Double = 4

    private var presentation: any MenuBarPresentationControlling {
        MenuBarPresentationProvider.current
    }

    /// Space 0 is the "unknown Space" answer from the bridging layer. Acting
    /// on it would send overrides somewhere unpredictable, so the section
    /// disables itself instead.
    private var hasKnownSpace: Bool {
        spaceID != 0
    }

    var body: some View {
        ThawSection {
            Text("This Space")
        } content: {
            if !hasKnownSpace {
                Text("\(Constants.displayName) can't tell which Space is showing right now, so these controls are off. Switch to another Space and back to try again.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Hide the menu bar in this Space", isOn: hiddenBinding)
                .annotation("Hides the system menu bar only while this Space is showing. Other Spaces keep their current behavior.")

            Toggle("Disable hover reveal in this Space", isOn: autoShowDisabledBinding)
                .annotation("Stops a hidden menu bar from sliding down when the pointer reaches the top edge of the screen in this Space.")

            LabeledContent {
                ThawSlider(
                    value: revealStripHeightBinding,
                    in: 0 ... 48,
                    step: 1
                ) {
                    Text(verbatim: "\(Int(revealStripHeight)) pt")
                        .monospacedDigit()
                }
            } label: {
                Text("Reveal strip height")
            }
            .annotation(
                "How tall the invisible strip at the top of the screen is before a hidden menu bar reveals itself.",
                more: "macOS doesn’t show this setting anywhere, so \(Constants.displayName) can’t read your current value. This starts at a default instead."
            )

            HStack(alignment: .top, spacing: ThawSpacing.inset) {
                Text("Drops every override \(Constants.displayName) set for this Space and returns it to the system default behavior.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                Spacer(minLength: ThawSpacing.gutter)
                Button("Reset This Space") {
                    resetSpace()
                }
                .buttonStyle(.settingsGlass)
            }
        } footer: {
            if let failure {
                SettingsWarningPill(
                    title: "macOS didn't apply that change. Try again.",
                    message: failure,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
        .disabled(!hasKnownSpace)
        .onChange(of: spaceID) { _, _ in
            // A different Space has different overrides, and we cannot read
            // them. Reset to neutral rather than show the previous Space's
            // settings as if they applied here.
            isHidden = false
            isAutoShowDisabled = false
            revealStripHeight = Self.defaultRevealStripHeight
            hasAdjustedRevealStrip = false
            failure = nil
        }
        // Debounced so dragging the slider sends one request at rest instead
        // of one per frame; task(id:) cancels the in-flight sleep on every
        // new value, which is exactly the debounce we want and gets torn down
        // with the view for free.
        .task(id: revealStripHeight) {
            guard hasAdjustedRevealStrip, hasKnownSpace else {
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else {
                return
            }
            let succeeded = await presentation.setSystemMenuBarAutohideHeight(
                revealStripHeight,
                spaceID: spaceID
            )
            failure = succeeded ? nil : "The reveal strip height could not be applied to this Space."
        }
    }

    // MARK: Bindings

    /// Records that the height is now user-chosen, which is what lets the
    /// debounce task tell "the user dragged the slider" apart from "the pane
    /// just appeared with its default".
    private var revealStripHeightBinding: Binding<Double> {
        Binding {
            revealStripHeight
        } set: { newValue in
            hasAdjustedRevealStrip = true
            revealStripHeight = newValue
        }
    }

    /// Optimistic-then-corrected: the switch moves immediately (anything else
    /// feels broken), and reverts if the agent declines. The mirror is only
    /// ever a claim about what we asked for.
    private var hiddenBinding: Binding<Bool> {
        Binding {
            isHidden
        } set: { newValue in
            isHidden = newValue
            failure = nil
            Task {
                let succeeded = await presentation.setSystemMenuBarHidden(newValue, spaceID: spaceID)
                if !succeeded {
                    isHidden = !newValue
                    failure = "Hiding the menu bar in this Space is not available right now."
                }
            }
        }
    }

    private var autoShowDisabledBinding: Binding<Bool> {
        Binding {
            isAutoShowDisabled
        } set: { newValue in
            isAutoShowDisabled = newValue
            failure = nil
            Task {
                let succeeded = await presentation.setSystemMenuBarAutoShowDisabled(newValue, spaceID: spaceID)
                if !succeeded {
                    isAutoShowDisabled = !newValue
                    failure = "The hover reveal setting could not be changed for this Space."
                }
            }
        }
    }

    private func resetSpace() {
        failure = nil
        Task {
            let succeeded = await presentation.clearSystemMenuBarOverrides(forSpace: spaceID)
            if succeeded {
                // The Space is back to system defaults, so the mirrors return
                // to neutral with it.
                isHidden = false
                isAutoShowDisabled = false
                revealStripHeight = Self.defaultRevealStripHeight
                hasAdjustedRevealStrip = false
                AccessibilityAnnouncements.post(String(localized: "This Space was reset to the system menu bar behavior."))
            } else {
                failure = "This Space's overrides could not be cleared."
            }
        }
    }
}

// MARK: - AllSpacesSection

/// Overrides that are not scoped to a Space, they change the menu bar
/// everywhere at once.
private struct AllSpacesSection: View {
    @State private var isHiddenEverywhere = false
    @State private var usesFullScreenAppearance = false
    @State private var failure: LocalizedStringKey?

    private var presentation: any MenuBarPresentationControlling {
        MenuBarPresentationProvider.current
    }

    var body: some View {
        ThawSection {
            Text("All Spaces")
        } content: {
            Toggle("Use the full-screen menu bar appearance everywhere", isOn: fullScreenAppearanceBinding)
                .annotation("Gives ordinary desktop Spaces the menu bar appearance macOS normally reserves for full-screen apps.")

            Toggle("Hide the menu bar in every Space", isOn: hiddenEverywhereBinding)
                .annotation(
                    "Hides the system menu bar in every context, full screen included.",
                    more: "Prefer the per-Space control above when only one Space needs it."
                )
        } footer: {
            if let failure {
                SettingsWarningPill(
                    title: "macOS didn't apply that change. Try again.",
                    message: failure,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
    }

    private var hiddenEverywhereBinding: Binding<Bool> {
        Binding {
            isHiddenEverywhere
        } set: { newValue in
            isHiddenEverywhere = newValue
            failure = nil
            Task {
                let succeeded = await presentation.setSystemMenuBarHidden(newValue)
                if !succeeded {
                    isHiddenEverywhere = !newValue
                    failure = "The menu bar could not be hidden across all Spaces."
                }
            }
        }
    }

    private var fullScreenAppearanceBinding: Binding<Bool> {
        Binding {
            usesFullScreenAppearance
        } set: { newValue in
            usesFullScreenAppearance = newValue
            failure = nil
            Task {
                let succeeded = await presentation.setFullScreenAppearanceOnUserSpace(newValue)
                if !succeeded {
                    usesFullScreenAppearance = !newValue
                    failure = "The full-screen menu bar appearance could not be applied."
                }
            }
        }
    }
}

// MARK: - SessionScopeNotice

/// The one thing a user must understand before touching this pane: none of it
/// survives a quit. Stated as its own row rather than buried in a caption,
/// because the alternative is someone hiding their menu bar, relaunching, and
/// filing a bug about settings that "don't save".
private struct SessionScopeNotice: View {
    var body: some View {
        // Footer-only section: the one placement where a pill renders without
        // the grouped form's section card around it (see TheLabSettingsPane).
        ThawSection {
            EmptyView()
        } footer: {
            SettingsWarningPill(
                title: "These controls last for this session",
                message: "macOS gives \(Constants.displayName) this state for as long as it is running. Everything on this page reverts when \(Constants.displayName) quits, and none of it is saved to your settings or profiles.",
                systemImage: "info.circle.fill",
                tint: .blue
            )
        }
    }
}

// MARK: - UnsupportedSection

/// Shown in place of the controls when the platform has no menu bar agent.
///
/// Not a disabled copy of the real pane: greyed-out switches invite a hunt
/// for a permission or setting that does not exist on this system.
///
/// Drawn as ThawEmptyState because this is the whole pane: prose alone looks
/// like content failed to load, while the centered symbol says "there is
/// nothing here" before the text is read.
private struct UnsupportedSection: View {
    var body: some View {
        ThawSection {
            ThawEmptyState(
                systemImage: "menubar.rectangle",
                title: "Per-Space menu bar control is not available",
                caption: "These controls need macOS 27 or later. \(Constants.displayName)'s other menu bar features work as usual."
            )
            .frame(minHeight: 140)
        }
    }
}
