//
//  SystemLaunchAgentIndex.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Maps executables registered by system LaunchAgents to the launchd label
/// that owns them.
///
/// A LaunchAgent-owned item can be launch-constrained to launchd as its
/// only parent; launching its bundle ourselves gets SIGKILLed at exec. Those
/// items must restart through launchd, which needs their label.
///
/// Labels can't be derived from bundle IDs or plist names (Dock's agent is
/// `com.apple.Dock.agent`), so the index keys on the executable path.
nonisolated struct SystemLaunchAgentIndex: Sendable {
    /// The directories macOS ships its per-user LaunchAgents in.
    static let systemDirectories = [
        URL(fileURLWithPath: "/System/Library/LaunchAgents", isDirectory: true),
    ]

    /// Built once per process; the sealed system volume only changes across
    /// an OS update, which restarts us anyway.
    static let system = SystemLaunchAgentIndex(directories: systemDirectories)

    /// Launchd labels keyed by the normalized path of the executable they
    /// launch.
    private let labelsByExecutablePath: [String: String]

    /// Skips unreadable directories and plists, and plists missing a label or
    /// program, so one malformed agent can't cost the wave every other item.
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
                // Some agents share one binary. Keep the lowest label so the
                // result doesn't depend on directory order.
                if let existing = labels[key], existing <= label {
                    continue
                }
                labels[key] = label
            }
        }

        labelsByExecutablePath = labels
    }

    /// The launchd label for the executable at `url`, or `nil` when no indexed
    /// agent owns it.
    func label(forExecutableAt url: URL) -> String? {
        labelsByExecutablePath[Self.normalized(url.path)]
    }

    /// The executable a LaunchAgent launches. `Program` wins when present;
    /// otherwise launchd treats `ProgramArguments[0]` as the path.
    private static func programPath(from plist: [String: Any]) -> String? {
        if let program = plist["Program"] as? String {
            return program
        }
        return (plist["ProgramArguments"] as? [String])?.first
    }

    /// Resolves symlinks so either spelling compares equal. Must be applied
    /// to both sides: an agent may declare a symlink while the process
    /// reports the target, or the reverse.
    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
