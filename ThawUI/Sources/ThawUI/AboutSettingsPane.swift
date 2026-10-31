//
//  AboutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.
//

import AppKit
import Observation
import SwiftUI

// MARK: - AboutSettingsPane

/// The About page: identity and build, an updates card, news and help actions, and a footer of
/// project links and copyright. Secondary destinations sit in the actions' menu.
public struct AboutSettingsPane: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let appName: String
    private let version: AboutVersionDetails
    private let links: AboutLinks
    private let moreMenu: [[AboutMenuItem]]
    private let updates: AboutUpdateControls?
    private let copyright: Text
    private let strings: AboutStrings
    private let showWhatsNew: @MainActor () -> Void
    private let showCredits: @MainActor () -> Void

    private static let iconSize: CGFloat = 96

    /// Half the icon, so the name beside it does not outweigh it.
    private static let nameSize: CGFloat = 48

    @State private var applicationIcon = AboutSettingsPane.currentApplicationIcon()
    @State private var didCopy = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var menuAnchor = MoreMenuAnchor()

    /// The more menu holds the actions, in groups split by separators; with no items its button doesn't show.
    /// A build that cannot update passes nil for the updates card.
    public init(
        appName: String,
        version: AboutVersionDetails,
        links: AboutLinks,
        moreMenu: [[AboutMenuItem]] = [],
        updates: AboutUpdateControls? = nil,
        copyright: Text,
        strings: AboutStrings,
        showWhatsNew: @escaping @MainActor () -> Void,
        showCredits: @escaping @MainActor () -> Void
    ) {
        self.appName = appName
        self.version = version
        self.links = links
        self.moreMenu = moreMenu
        self.updates = updates
        self.copyright = copyright
        self.strings = strings
        self.showWhatsNew = showWhatsNew
        self.showCredits = showCredits
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: ThawSpacing.section) {
                identity
                if let updates {
                    updatesCard(updates)
                }
                actions
                footer
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, ThawSpacing.section)
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
        VStack(spacing: ThawSpacing.gutter) {
            VStack(spacing: ThawSpacing.base) {
                HStack(spacing: ThawSpacing.inset) {
                    Text(verbatim: appName)
                        .font(.system(size: Self.nameSize, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Image(nsImage: applicationIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.iconSize, height: Self.iconSize)
                        .accessibilityHidden(true)
                }
                Text(strings.tagline)
                    .font(ThawType.detail)
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
        HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.row) {
            // Label a container: labeling the selectable AppKit text view directly recurses until the
            // stack overflows under VoiceOver.
            Text(verbatim: version.line)
                .font(ThawType.detail)
                .monospaced()
                .foregroundStyle(ThawInk.supporting)
                .textSelection(.enabled)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(strings.versionLabel(version.version, version.build, version.commit)))
            Button {
                copyVersionInfo()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .buttonStyle(.settingsGlass)
            .controlSize(.small)
            .help(Text(didCopy ? strings.copied : strings.copyHelp))
            .accessibilityLabel(Text(didCopy ? strings.copied : strings.copyLabel))
        }
    }

    // MARK: Actions

    private var actions: some View {
        ThawActionGroup {
            Button(strings.whatsNew) {
                showWhatsNew()
            }
            if let url = links.reportBug {
                Button(strings.reportBug) {
                    openURL(url)
                }
            }
            if moreMenu.contains(where: { !$0.isEmpty }) {
                // A plain button that pops the menu, so it takes the same style,
                // size and corner as its neighbours; a SwiftUI Menu does not.
                Button {
                    showMoreMenu()
                } label: {
                    // Inside a Text the symbol takes a line of text's height, so
                    // the button matches its neighbours instead of sitting short.
                    Text(Image(systemName: "ellipsis"))
                }
                .help(Text(strings.more))
                .accessibilityLabel(Text(strings.more))
                // The anchor only places the menu, so it stays out of the accessibility
                // tree, where it could stand in for the labeled button.
                .background { MoreMenuAnchorView(anchor: menuAnchor).accessibilityHidden(true) }
            }
        }
        .buttonStyle(.thawGrouped)
    }

    private var footer: some View {
        VStack(spacing: ThawSpacing.inset) {
            HStack(spacing: ThawSpacing.inset) {
                if let url = links.sourceCode {
                    Link(destination: url) {
                        Text(strings.sourceCode).underline()
                    }
                    footerSeparator
                }
                Button {
                    showCredits()
                } label: {
                    Text(strings.credits).underline()
                }
                if let url = links.support {
                    footerSeparator
                    Link(destination: url) {
                        Text(strings.support).underline()
                    }
                }
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)

            copyright
        }
        .font(ThawType.footnote)
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
        let openURL = openURL
        let menu = AboutMoreMenu.make(groups: moreMenu) { openURL($0) }
        guard let anchor = menuAnchor.view else { return }
        // The anchor's own coordinate system is not flipped, so minY is its
        // bottom edge and the menu opens just below the button.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    // MARK: Updates

    /// The choices are pills, short enough to sit beside their labels.
    private func updatesCard(_ updates: AboutUpdateControls) -> some View {
        let strings = updates.strings
        return VStack(spacing: 0) {
            updateRow(strings.updateChannel) {
                ThawPillPicker(strings.updateChannel, selection: updates.channel, values: updates.channels, title: strings.channelName)
            }
            Divider()
            updateRow(strings.automaticUpdates) {
                ThawPillPicker(
                    strings.automaticUpdates,
                    selection: updates.automaticUpdates,
                    options: AutomaticUpdates.allCases.map {
                        ThawPillPicker.Option($0, title: strings.automaticUpdatesShortName($0), help: strings.automaticUpdatesName($0))
                    }
                )
            }
            Divider()
            updateRow(strings.footnote(lastCheck: updates.model.lastUpdateCheckDate), isSecondary: true) {
                Button(strings.checkNow) {
                    updates.model.checkForUpdates()
                }
                .buttonStyle(.settingsGlass)
                .disabled(!updates.model.canCheckNow)
            }
        }
        .font(ThawType.detail)
        .background(.quinary, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
    }

    private func updateRow(
        _ label: LocalizedStringResource,
        isSecondary: Bool = false,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(isSecondary ? AnyShapeStyle(ThawInk.supporting) : AnyShapeStyle(.primary))
            Spacer(minLength: ThawSpacing.inset)
            control()
                .labelsHidden()
                .fixedSize()
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.base)
    }

    // MARK: Helpers

    public static func currentApplicationIcon() -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        return (icon.copy() as? NSImage) ?? icon
    }

    private func copyVersionInfo() {
        Self.copy(version.report, to: .general)

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

    static func copy(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - AboutMoreMenu

/// Builds the AppKit menu behind the actions button.
@MainActor
enum AboutMoreMenu {
    /// Empty groups leave no separator behind.
    static func make(groups: [[AboutMenuItem]], openURL: @escaping @MainActor (URL) -> Void) -> NSMenu {
        let menu = NSMenu()
        for (index, group) in groups.filter({ !$0.isEmpty }).enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            for item in group {
                let entry = ClosureMenuItem(title: String(localized: item.title)) {
                    switch item.action {
                    case let .open(url): openURL(url)
                    case let .perform(action): action()
                    }
                }
                entry.image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil)
                menu.addItem(entry)
            }
        }
        return menu
    }
}

/// A reference box for the AppKit view behind the actions button, so the representable
/// doesn't write SwiftUI state during a view update.
@MainActor
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
