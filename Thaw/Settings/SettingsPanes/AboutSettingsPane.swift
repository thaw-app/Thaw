//
//  AboutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The About page: who Thaw is and which build this is, then one card for
/// updates, then news and help actions. Project links and copyright form a
/// quiet footer; badges and live repository statistics stay on the website.
struct AboutSettingsPane: View {
    @Bindable var updatesManager: UpdatesManager
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let iconSize: CGFloat = 96

    /// Half the icon, so the name beside it does not outweigh it.
    private static let nameSize: CGFloat = 48

    @State private var applicationIcon = AboutSettingsPane.currentApplicationIcon()
    @State private var didCopy = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var menuAnchor = MoreMenuAnchor()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                identity
                updates
                actions
                footer
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The sidebar's behind-window material, so About reads as one surface
        // with it. Other panes keep the window background for their forms.
        .background {
            BehindWindowMaterialBackground(material: .sidebar)
                .ignoresSafeArea()
        }
        .onChange(of: colorScheme, initial: true) {
            applicationIcon = Self.currentApplicationIcon()
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    // MARK: Identity

    private var identity: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Text(verbatim: "Thaw")
                        .font(.system(size: Self.nameSize, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Image(nsImage: applicationIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.iconSize, height: Self.iconSize)
                        .accessibilityHidden(true)
                }
                Text("The open source menu bar manager for macOS")
                    .font(.callout)
                    .foregroundStyle(ThawInk.supporting)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            details
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Details

    /// Labels right-aligned against a shared edge, values in monospace so a
    /// hash and a build number line up and can be selected and pasted.
    private var details: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                detailRow("Version", value: Constants.versionString, isPrimary: true)
                detailRow("Build", value: Constants.buildString)
                detailRow("Commit", value: Constants.commitString)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            // Beside what it copies.
            Button {
                copyVersionInfo()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .buttonStyle(.settingsGlass)
            .controlSize(.small)
            .help(didCopy ? "Copied" : "Copy the version, build and commit for a bug report")
            .accessibilityLabel(didCopy ? "Copied" : "Copy version information")
        }
    }

    private func detailRow(_ label: LocalizedStringKey, value: String, isPrimary: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(ThawInk.supporting)
                .gridColumnAlignment(.trailing)
            Text(verbatim: value)
                .monospaced()
                .fontWeight(isPrimary ? .medium : .regular)
                .foregroundStyle(isPrimary ? Color.primary : ThawInk.supporting)
                .textSelection(.enabled)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button("What’s New") {
                appState.openWindow(.whatsNew)
            }
            Button("Report a Bug") {
                openURL(Constants.issuesURL)
            }
            // A plain button that pops the menu, so it takes the same style,
            // size and corner as its neighbours; a SwiftUI Menu does not.
            Button {
                showMoreMenu()
            } label: {
                // Inside a Text the symbol takes a line of text's height, so
                // the button matches its neighbours instead of sitting short.
                Text(Image(systemName: "ellipsis"))
            }
            .help("More about \(Constants.displayName)")
            .accessibilityLabel("More about \(Constants.displayName)")
            .background { MoreMenuAnchorView(anchor: menuAnchor) }
        }
        .buttonStyle(.settingsGlass)
        .controlSize(.regular)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Link(destination: Constants.repositoryURL) {
                    Text("Source Code").underline()
                }
                footerSeparator
                Button {
                    appState.openWindow(.acknowledgements)
                } label: {
                    Text("Credits").underline()
                }
                footerSeparator
                Link(destination: Constants.donateURL) {
                    Text("Support Thaw").underline()
                }
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: ThawSpacing.tight) {
                Text(Constants.copyrightString)
                Text(verbatim: "© 2026 Thaw-app")
            }
        }
        .font(.footnote)
        .foregroundStyle(ThawInk.supporting)
        .multilineTextAlignment(.center)
    }

    private var footerSeparator: some View {
        Text(verbatim: "·")
            .accessibilityHidden(true)
    }

    /// Pops the secondary destinations under the actions button, for both
    /// clicks and keyboard activation.
    private func showMoreMenu() {
        let menu = NSMenu()
        func item(_ title: String, _ symbol: String, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
            let entry = ClosureMenuItem(title: title, handler: handler)
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return entry
        }
        let appState = appState
        let openURL = openURL
        menu.addItem(item(String(localized: "Frequent Issues"), "questionmark.circle") { openURL(Constants.frequentIssuesURL) })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Join the Discord"), "bubble.left.and.bubble.right") { openURL(Constants.discordURL) })
        menu.addItem(item(String(localized: "Help Translate"), "globe") { openURL(Constants.translateURL) })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Acknowledgements"), "text.book.closed") { appState.openWindow(.acknowledgements) })
        guard let anchor = menuAnchor.view else { return }
        // The anchor's own coordinate system is not flipped, so minY is its
        // bottom edge and the menu opens just below the button.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    // MARK: Updates

    /// Pickers are made borderless explicitly, since outside a Form they
    /// default to bordered. The two Sparkle switches are one picker:
    /// downloading implies checking.
    private var updates: some View {
        VStack(spacing: 0) {
            updateRow("Update channel") {
                Picker("Update channel", selection: $updatesManager.updateChannel) {
                    ForEach(UpdateChannel.selectable) { channel in
                        Text(channel.localized).tag(channel)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
            }
            Divider()
            updateRow("Automatic updates") {
                Picker("Automatic updates", selection: automaticUpdatesMode) {
                    Text("Off").tag(AutomaticUpdates.off)
                    Text("Check only").tag(AutomaticUpdates.check)
                    Text("Check and download").tag(AutomaticUpdates.download)
                }
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
            }
            Divider()
            updateRow(updateFootnote, isSecondary: true) {
                Button("Check Now") {
                    updatesManager.checkForUpdates()
                }
                .buttonStyle(.settingsGlass)
                .disabled(!updatesManager.canCheckForUpdates)
            }
        }
        .font(.callout)
        .background(.quinary, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
    }

    private func updateRow(
        _ label: LocalizedStringKey,
        isSecondary: Bool = false,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(isSecondary ? AnyShapeStyle(ThawInk.supporting) : AnyShapeStyle(.primary))
            Spacer(minLength: 12)
            control()
                .labelsHidden()
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// When updates were last checked, or plainly that they have not been.
    private var updateFootnote: LocalizedStringKey {
        guard let date = updatesManager.lastUpdateCheckDate else {
            return "Not checked yet"
        }
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return "Last checked \(formatted)"
    }

    private enum AutomaticUpdates: Hashable {
        case off, check, download
    }

    private var automaticUpdatesMode: Binding<AutomaticUpdates> {
        Binding {
            if !updatesManager.automaticallyChecksForUpdates {
                return .off
            }
            return updatesManager.automaticallyDownloadsUpdates ? .download : .check
        } set: { mode in
            updatesManager.automaticallyChecksForUpdates = mode != .off
            updatesManager.automaticallyDownloadsUpdates = mode == .download
        }
    }

    // MARK: Helpers

    private static func currentApplicationIcon() -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        return (icon.copy() as? NSImage) ?? icon
    }

    private func copyVersionInfo() {
        let text = Constants.buildDescription
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copyFeedbackTask?.cancel()
        didCopy = true
        copyFeedbackTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            didCopy = false
            copyFeedbackTask = nil
        }
    }
}

/// Holds the AppKit view behind the actions button so the menu can be
/// positioned against the button itself. A reference box keeps the
/// representable from writing SwiftUI state during a view update.
private final class MoreMenuAnchor {
    weak var view: NSView?
}

/// An empty view behind the actions button for NSMenu.popUp to position
/// against, including on keyboard activation.
private struct MoreMenuAnchorView: NSViewRepresentable {
    let anchor: MoreMenuAnchor

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        anchor.view = nsView
    }
}
