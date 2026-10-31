//
//  AboutSupport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.
//

import AppKit
import Observation
import SwiftUI

// MARK: - AboutStrings

/// The text of the About page, apart from its updates card.
public nonisolated struct AboutStrings: Sendable {
    public var tagline: LocalizedStringResource
    /// What VoiceOver reads for the version line.
    public var versionLabel: @Sendable (_ version: String, _ build: String, _ commit: String) -> LocalizedStringResource
    public var copied: LocalizedStringResource
    public var copyHelp: LocalizedStringResource
    public var copyLabel: LocalizedStringResource
    public var whatsNew: LocalizedStringResource
    public var reportBug: LocalizedStringResource
    public var more: LocalizedStringResource
    public var sourceCode: LocalizedStringResource
    public var credits: LocalizedStringResource
    public var support: LocalizedStringResource

    public init(
        tagline: LocalizedStringResource,
        versionLabel: @escaping @Sendable (_ version: String, _ build: String, _ commit: String) -> LocalizedStringResource,
        copied: LocalizedStringResource,
        copyHelp: LocalizedStringResource,
        copyLabel: LocalizedStringResource,
        whatsNew: LocalizedStringResource,
        reportBug: LocalizedStringResource,
        more: LocalizedStringResource,
        sourceCode: LocalizedStringResource,
        credits: LocalizedStringResource,
        support: LocalizedStringResource
    ) {
        self.tagline = tagline
        self.versionLabel = versionLabel
        self.copied = copied
        self.copyHelp = copyHelp
        self.copyLabel = copyLabel
        self.whatsNew = whatsNew
        self.reportBug = reportBug
        self.more = more
        self.sourceCode = sourceCode
        self.credits = credits
        self.support = support
    }
}

/// The text of the About page's updates card.
public nonisolated struct AboutUpdateStrings: Sendable {
    public var updateChannel: LocalizedStringResource
    public var automaticUpdates: LocalizedStringResource
    public var checkNow: LocalizedStringResource
    public var notChecked: LocalizedStringResource
    public var lastChecked: @Sendable (_ formattedDate: String) -> LocalizedStringResource
    public var channelName: @Sendable (UpdateChannel) -> LocalizedStringResource
    /// A choice's full name, which is its pill's help.
    public var automaticUpdatesName: @Sendable (AutomaticUpdates) -> LocalizedStringResource
    /// The name in a pill, where the full one doesn't fit.
    public var automaticUpdatesShortName: @Sendable (AutomaticUpdates) -> LocalizedStringResource

    public init(
        updateChannel: LocalizedStringResource,
        automaticUpdates: LocalizedStringResource,
        checkNow: LocalizedStringResource,
        notChecked: LocalizedStringResource,
        lastChecked: @escaping @Sendable (_ formattedDate: String) -> LocalizedStringResource,
        channelName: @escaping @Sendable (UpdateChannel) -> LocalizedStringResource,
        automaticUpdatesName: @escaping @Sendable (AutomaticUpdates) -> LocalizedStringResource,
        automaticUpdatesShortName: @escaping @Sendable (AutomaticUpdates) -> LocalizedStringResource
    ) {
        self.updateChannel = updateChannel
        self.automaticUpdates = automaticUpdates
        self.checkNow = checkNow
        self.notChecked = notChecked
        self.lastChecked = lastChecked
        self.channelName = channelName
        self.automaticUpdatesName = automaticUpdatesName
        self.automaticUpdatesShortName = automaticUpdatesShortName
    }

    /// When updates were last checked, or plainly that they have not been.
    func footnote(lastCheck date: Date?) -> LocalizedStringResource {
        guard let date else {
            return notChecked
        }
        return lastChecked(date.formatted(date: .abbreviated, time: .shortened))
    }
}

// MARK: - AboutContent

/// Which build this is.
public nonisolated struct AboutVersionDetails: Sendable {
    public var version: String
    public var build: String
    public var commit: String
    /// What the copy button copies: the full block a bug report asks for.
    public var report: String

    public init(
        version: String,
        build: String,
        commit: String,
        report: String
    ) {
        self.version = version
        self.build = build
        self.commit = commit
        self.report = report
    }

    var line: String {
        "\(version) (\(build)) · \(commit)"
    }
}

/// The page's web links. A link without a URL does not show.
public nonisolated struct AboutLinks: Sendable {
    public var sourceCode: URL?
    public var reportBug: URL?
    public var support: URL?

    public init(
        sourceCode: URL?,
        reportBug: URL?,
        support: URL?
    ) {
        self.sourceCode = sourceCode
        self.reportBug = reportBug
        self.support = support
    }
}

/// One entry in the menu behind the page's actions button.
public struct AboutMenuItem {
    public enum Action {
        /// Opens through the environment's openURL, as the page's other links do.
        case open(URL)
        case perform(@MainActor () -> Void)
    }

    public var title: LocalizedStringResource
    public var systemImage: String
    public var action: Action

    public init(
        _ title: LocalizedStringResource,
        systemImage: String,
        url: URL
    ) {
        self.title = title
        self.systemImage = systemImage
        action = .open(url)
    }

    public init(
        _ title: LocalizedStringResource,
        systemImage: String,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.action = .perform(action)
    }
}

// MARK: - AboutUpdateControls

/// What the updates card reads and changes, so the page needs no updater of its own.
/// Observable, so the card follows the updater while it is on screen.
@MainActor
public protocol AboutUpdatesModel: AutomaticUpdateSwitches, Observable {
    var updateChannel: UpdateChannel { get set }
    var canCheckNow: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()
}

/// The updates card: an updater, the channels on offer, and the card's text.
public struct AboutUpdateControls {
    let model: any AboutUpdatesModel
    let channels: [UpdateChannel]
    let strings: AboutUpdateStrings

    public init(
        model: any AboutUpdatesModel,
        channels: [UpdateChannel],
        strings: AboutUpdateStrings
    ) {
        self.model = model
        self.channels = channels
        self.strings = strings
    }

    @MainActor
    var channel: Binding<UpdateChannel> {
        let model = model
        return Binding {
            model.updateChannel
        } set: {
            model.updateChannel = $0
        }
    }

    @MainActor
    var automaticUpdates: Binding<AutomaticUpdates> {
        let model = model
        return Binding {
            model.automaticUpdates
        } set: {
            model.automaticUpdates = $0
        }
    }
}
