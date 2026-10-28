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
/// quiet footer; Floe and the community links sit in the actions' menu.
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
        // The sidebar's material, so About reads as one surface with it, or black on a
        // black window. Other panes keep the window background for their forms.
        .background {
            SettingsPaneBackdrop(material: .sidebar)
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

    /// One line, monospaced so it can be selected and pasted. The copy button beside
    /// it copies the full block a bug report asks for.
    private var details: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Label a container, not the selectable text: labeling the AppKit text view
            // directly recurses until the stack overflows under VoiceOver.
            Text(verbatim: "\(Constants.versionString) (\(Constants.buildString)) · \(Constants.commitString)")
                .font(.callout)
                .monospaced()
                .foregroundStyle(ThawInk.supporting)
                .textSelection(.enabled)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Version \(Constants.versionString), build \(Constants.buildString), commit \(Constants.commitString)")
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

    // MARK: Actions

    private var actions: some View {
        ThawActionGroup {
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
            // The anchor only places the menu, so it stays out of the accessibility
            // tree, where it could stand in for the labeled button.
            .background { MoreMenuAnchorView(anchor: menuAnchor).accessibilityHidden(true) }
        }
        .buttonStyle(.thawGrouped)
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

            Text(Constants.copyrightString)
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
        menu.addItem(item(String(localized: "Show Welcome Screens Again"), "hand.wave") { appState.replayOnboarding() })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Join the Discord"), "bubble.left.and.bubble.right") { openURL(Constants.discordURL) })
        menu.addItem(item(String(localized: "Help Translate"), "globe") { openURL(Constants.translateURL) })
        menu.addItem(.separator())
        menu.addItem(item("Floe", "snowflake") { openURL(Constants.floeURL) })
        guard let anchor = menuAnchor.view else { return }
        // The anchor's own coordinate system is not flipped, so minY is its
        // bottom edge and the menu opens just below the button.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    // MARK: Updates

    /// The choices are pills, short enough to sit beside their labels.
    /// Automatic updates is the same choice the Privacy pane lists with the network calls.
    private var updates: some View {
        VStack(spacing: 0) {
            updateRow("Update channel") {
                ThawPillPicker("Update channel", selection: $updatesManager.updateChannel, values: UpdateChannel.selectable, title: \.localized)
            }
            Divider()
            updateRow("Automatic updates") {
                ThawPillPicker(
                    "Automatic updates",
                    selection: $updatesManager.automaticUpdates,
                    options: AutomaticUpdates.allCases.map { ThawPillPicker.Option($0, title: $0.shortLocalized, help: $0.localized) }
                )
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
