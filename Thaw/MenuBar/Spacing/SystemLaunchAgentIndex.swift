//
//  SystemLaunchAgentIndex.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Maps executables registered by system LaunchAgents to the launchd label
/// that owns them.
///
/// The spacing relaunch wave has to bring every menu bar item back after
/// rewriting `NSStatusItemSpacing`. For an ordinary app that means quit and
/// launch the bundle, but a LaunchAgent-owned item can carry a launch
/// constraint permitting launchd as its only launching parent - launching
/// its bundle ourselves gets the new process SIGKILLed at exec
/// (`CODESIGNING`, "Launch Constraint Violation"). Those items have to be
/// restarted through launchd instead, which needs their label. (#720)
///
/// The label is read from the agent's property list and cannot be derived
/// from the bundle identifier or the plist file name: Dock's agent is
/// `com.apple.Dock.agent`, not `com.apple.dock`; Time Machine's is
/// `com.apple.TMHelperAgent`, not `com.apple.timemachine.HelperAgent`; the
/// screen sharing menu extra ships as `com.apple.SSMenuAgent` but is
/// launched by `com.apple.screensharing.menuextra`. Indexing on the
/// executable path is the only mapping that holds for all of them.
nonisolated struct SystemLaunchAgentIndex: Sendable {
    /// The directories macOS ships its per-user LaunchAgents in.
    static let systemDirectories = [
        URL(fileURLWithPath: "/System/Library/LaunchAgents", isDirectory: true),
    ]

    /// The index over ``systemDirectories``.
    ///
    /// Built once per process. The agent definitions it reads are part of
    /// the sealed system volume and only change across an OS update, which
    /// restarts us anyway.
    static let system = SystemLaunchAgentIndex(directories: systemDirectories)

    /// Launchd labels keyed by the normalized path of the executable they
    /// launch.
    private let labelsByExecutablePath: [String: String]

    /// Creates an index over the LaunchAgent property lists in the given
    /// directories. Unreadable directories, unreadable plists, and plists
    /// without both a label and a program are skipped: one malformed agent
    /// must not cost the wave every other item.
    init(directories: [URL]) {
        var labels: [String: String] = [:]

        for directory in directories {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )) ?? []

            for url in contents where url.pathExtension == "plist" {
                guard
                    let data = try? Data(contentsOf: url),
                    let plist = try? PropertyListSerialization.propertyList(
                        from: data,
                        options: [],
                        format: nil
                    ) as? [String: Any],
                    let label = plist["Label"] as? String,
                    let program = Self.programPath(from: plist)
                else {
                    continue
                }

                let key = Self.normalized(program)
                // A handful of agents share one binary (SetupAssistant is
                // launched by four labels, NetAuthAgent by two). Keep the
                // lowest label so the wave restarts the same service every
                // time instead of depending on directory order. None of the
                // shared binaries is a menu bar item today.
                if let existing = labels[key], existing <= label {
                    continue
                }
                labels[key] = label
            }
        }

        labelsByExecutablePath = labels
    }

    /// The launchd label that launches the executable at `url`, or `nil`
    /// when no indexed agent owns it and the item should be relaunched the
    /// ordinary way.
    func label(forExecutableAt url: URL) -> String? {
        if let label = labelsByExecutablePath[Self.normalized(url.path)] {
            return label
        }
        // Second chance through the filesystem, in case the running
        // process reports its executable by a differently linked path than
        // the one the agent declares.
        return labelsByExecutablePath[url.resolvingSymlinksInPath().standardizedFileURL.path]
    }

    /// The executable a LaunchAgent launches. `Program` wins when present;
    /// otherwise launchd treats `ProgramArguments[0]` as the path.
    private static func programPath(from plist: [String: Any]) -> String? {
        if let program = plist["Program"] as? String {
            return program
        }
        return (plist["ProgramArguments"] as? [String])?.first
    }

    /// Lexical normalization only - no filesystem access, so the index
    /// costs one read per plist and nothing else.
    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
