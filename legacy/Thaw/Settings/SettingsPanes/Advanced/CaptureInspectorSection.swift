//
//  CaptureInspectorSection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Shows the untreated frame Thaw captures, so granting Screen Recording comes
/// with the ability to confirm the scope of what is observed.
///
/// Drives the app's own `ScreenCapture` primitives, so it shows exactly the
/// pipeline Thaw runs. Capture is manual, not on a timer, and nothing is
/// written to disk.
///
/// The copy must state the scope exactly: the band includes the frontmost
/// app's menus and the wallpaper behind the bar.
struct CaptureInspectorSection: View {
    @Environment(AppState.self) private var appState: AppState

    @State private var inspection: CGImage?
    @State private var inspectedFrame: CGRect?
    @State private var capturedAt: Date?
    @State private var isCapturing = false
    @State private var errorMessage: String?

    private var screens: [NSScreen] {
        NSScreen.screens
    }

    var body: some View {
        IceSection {
            Text("What \(Constants.displayName) Sees")
        } content: {
            scopeDescription
            controls
            if let inspection, let inspectedFrame {
                results(inspection, frame: inspectedFrame)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            Text("Nothing shown here is saved or sent anywhere; the capture exists only while this page is open.")
        }
    }

    private var scopeDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Thaw reads a band across the top of your display — the menu bar and its background. That band can contain the frontmost app's menus.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Item icons are cropped out of this band to draw the layout editor, the Bar, and Search.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack {
            Button {
                runInspection()
            } label: {
                if isCapturing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Capture One Frame")
                }
            }
            .disabled(isCapturing || !ScreenCapture.cachedCheckPermissions())

            if !ScreenCapture.cachedCheckPermissions() {
                Text("Screen Recording is off, so \(Constants.displayName) reads nothing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let capturedAt {
                Text(capturedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func results(_ image: CGImage, frame: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The untreated frame, letterboxed into the form.
            Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary)
                }

            Text("Frame bounds: x=\(Int(frame.origin.x)), y=\(Int(frame.origin.y)), \(Int(frame.width))×\(Int(frame.height)) pt")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Returns the menu bar band at the top of `displayBounds`.
    ///
    /// Both are in Core Graphics global coordinates (top-left origin), which
    /// ``ScreenCapture/captureScreenBelowWindow(excludingWindowID:screenBounds:displayID:)``
    /// passes to `SCStreamConfiguration.sourceRect`, so the band starts at
    /// `minY` and grows down.
    ///
    /// Don't build it from `NSScreen.frame`: its bottom-left origin makes the
    /// band land on the bottom of the display, at the right size, so nothing
    /// downstream notices.
    static func menuBarBand(inDisplayBounds displayBounds: CGRect, menuBarHeight: CGFloat) -> CGRect {
        CGRect(
            x: displayBounds.minX,
            y: displayBounds.minY,
            width: displayBounds.width,
            height: menuBarHeight
        )
    }

    /// Captures the menu bar band of the display that currently owns the menu
    /// bar, through the same capture entry point the item pipeline uses.
    private func runInspection() {
        guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            errorMessage = String(localized: "No display found.")
            return
        }

        let frame = Self.menuBarBand(
            inDisplayBounds: CGDisplayBounds(screen.displayID),
            menuBarHeight: screen.getMenuBarHeightEstimate()
        )

        isCapturing = true
        errorMessage = nil

        Task { @MainActor in
            defer { isCapturing = false }
            do {
                // An impossible window ID excludes nothing, so the whole band
                // is read as the item pipeline sees it before cropping.
                guard let image = try await ScreenCapture.captureScreenBelowWindow(
                    excludingWindowID: 0,
                    screenBounds: frame,
                    displayID: screen.displayID
                ) else {
                    errorMessage = String(localized: "The capture returned nothing for this display.")
                    return
                }
                inspection = image
                inspectedFrame = frame
                capturedAt = .now
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
