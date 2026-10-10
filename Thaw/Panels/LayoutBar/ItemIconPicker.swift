//
//  ItemIconPicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI
import UniformTypeIdentifiers

/// A window listing every small image an item's app ships, so the user picks
/// the one Thaw draws for the item when it has no capture. Works the same for
/// every app; an app that ships nothing still offers "Choose Image…".
@MainActor
enum ItemIconPicker {
    private static var window: NSWindow?

    static func present(for item: MenuBarItem, appState: AppState) {
        let bundleURL = item.sourcePID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleURL }
        let view = ItemIconPickerView(
            item: item,
            candidates: BundledStatusIcon.candidates(forBundleAt: bundleURL),
            onDone: { window?.close() }
        )
        .environment(appState)

        let panel = window ?? makeWindow()
        panel.title = String(localized: "Icon for \(MenuBarItemDisplayName.displayName(for: item))")
        panel.contentViewController = NSHostingController(rootView: view)
        panel.setContentSize(NSSize(width: 460, height: 420))
        panel.center()
        window = panel
        appState.activate(withPolicy: .regular)
        panel.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 280)
        return window
    }
}

private struct ItemIconPickerView: View {
    @Environment(AppState.self) private var appState
    let item: MenuBarItem
    let candidates: [BundledStatusIcon.Candidate]
    let onDone: () -> Void

    @State private var isImporting = false
    @State private var importError: LocalizedErrorWrapper?

    private let columns = [GridItem(.adaptive(minimum: 56, maximum: 72), spacing: ThawSpacing.base)]

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            Text("Shown when \(Constants.displayName) has no picture of the item, which is always the case for a Thaw Bar Only item.")
                .font(ThawType.detail)
                .foregroundStyle(ThawInk.supporting)
                .fixedSize(horizontal: false, vertical: true)

            if candidates.isEmpty {
                ThawEmptyState(
                    systemImage: "photo.on.rectangle",
                    title: "No icons found in this app",
                    caption: "Choose an image file instead."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: ThawSpacing.base) {
                        ForEach(candidates) { candidate in
                            Button {
                                choose(candidate.image)
                            } label: {
                                tile(candidate.image)
                            }
                            .buttonStyle(.plain)
                            .help(candidate.name)
                            .accessibilityLabel(candidate.name)
                        }
                    }
                    .padding(ThawSpacing.tight)
                }
            }

            HStack(spacing: ThawSpacing.base) {
                Button("Automatic") {
                    choose(nil)
                }
                .buttonStyle(.settingsGlass)
                .disabled(!MenuBarItemIconChoices.shared.hasChoice(for: item))
                .help("Use the app's own menu bar icon when Thaw finds one, and the app icon otherwise")
                Button("Choose Image…") {
                    isImporting = true
                }
                .buttonStyle(.settingsGlass)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ThawSpacing.gutter)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard let image = NSImage(contentsOf: url) else { return }
                image.size = Self.menuBarSize(for: image.size)
                choose(image)
            } catch {
                importError = LocalizedErrorWrapper(error)
            }
        }
        .errorAlert($importError)
    }

    private func tile(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
            .frame(width: 56, height: 44)
            .background(.quinary, in: RoundedRectangle(cornerRadius: ThawRadius.control / 2, style: .continuous))
            .contentShape(Rectangle())
    }

    private func choose(_ image: NSImage?) {
        MenuBarItemIconChoices.shared.setImage(image, for: item)
    }

    /// A picked file is drawn at menu bar height whatever its pixel size.
    private static func menuBarSize(for size: CGSize) -> CGSize {
        guard size.height > 0 else { return CGSize(width: 18, height: 18) }
        let height: CGFloat = 18
        return CGSize(width: size.width * height / size.height, height: height)
    }
}
