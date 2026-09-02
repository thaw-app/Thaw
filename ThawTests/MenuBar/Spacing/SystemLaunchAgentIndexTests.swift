//
//  SystemLaunchAgentIndexTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the launchd label lookup added for #720.
///
/// Spotlight is a LaunchAgent whose binary carries a launch constraint
/// permitting launchd as the only launching parent. Terminating it and
/// launching the bundle ourselves gets the new process SIGKILLed at exec
/// (`CODESIGNING` / Launch Constraint Violation), so the spacing relaunch
/// wave has to restart those items through launchd instead - which means
/// resolving the right label first.
@Suite("System launch agent index")
struct SystemLaunchAgentIndexTests {
    /// Writes `agents` as property lists into a fresh temporary directory
    /// and hands it to `body`, cleaning up afterwards.
    private func withAgentDirectory(
        _ agents: [String: [String: Any]],
        _ body: (URL) throws -> Void
    ) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for (name, contents) in agents {
            let data = try PropertyListSerialization.data(
                fromPropertyList: contents,
                format: .xml,
                options: 0
            )
            try data.write(to: tmp.appendingPathComponent(name))
        }
        try body(tmp)
    }

    /// The common shape: the launched binary is `ProgramArguments[0]`.
    @Test("Resolves a label from ProgramArguments")
    func resolvesLabelFromProgramArguments() throws {
        try withAgentDirectory([
            "com.apple.Spotlight.plist": [
                "Label": "com.apple.Spotlight",
                "ProgramArguments": ["/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight"],
            ],
        ]) { directory in
            let index = SystemLaunchAgentIndex(directories: [directory])
            #expect(
                index.label(forExecutableAt: URL(
                    fileURLWithPath: "/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight"
                )) == "com.apple.Spotlight"
            )
        }
    }

    /// The other shape: a bare `Program` key with no argument vector.
    @Test("Resolves a label from Program")
    func resolvesLabelFromProgram() throws {
        try withAgentDirectory([
            "com.example.agent.plist": [
                "Label": "com.example.agent",
                "Program": "/System/Library/CoreServices/Example.app/Contents/MacOS/Example",
            ],
        ]) { directory in
            let index = SystemLaunchAgentIndex(directories: [directory])
            #expect(
                index.label(forExecutableAt: URL(
                    fileURLWithPath: "/System/Library/CoreServices/Example.app/Contents/MacOS/Example"
                )) == "com.example.agent"
            )
        }
    }

    /// The regression this type exists to prevent. Deriving the label from
    /// the bundle identifier or the plist file name looks like it works
    /// (`com.apple.Dock.plist` is right there) but produces
    /// `com.apple.dock`, which launchd rejects with "Could not find
    /// service". The real label is `com.apple.Dock.agent`, and it is only
    /// readable from inside the plist. Time Machine
    /// (`com.apple.timemachine.HelperAgent` -> `com.apple.TMHelperAgent`)
    /// and screen sharing (`com.apple.SSMenuAgent` ->
    /// `com.apple.screensharing.menuextra`) diverge even further.
    @Test("The label comes from the plist, not the file name or bundle ID")
    func labelIsNotDerivedFromFileName() throws {
        try withAgentDirectory([
            "com.apple.Dock.plist": [
                "Label": "com.apple.Dock.agent",
                "ProgramArguments": ["/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"],
            ],
        ]) { directory in
            let index = SystemLaunchAgentIndex(directories: [directory])
            let label = index.label(forExecutableAt: URL(
                fileURLWithPath: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"
            ))
            #expect(label == "com.apple.Dock.agent")
            #expect(label != "com.apple.dock")
        }
    }

    /// Anything not registered by an agent keeps the ordinary
    /// terminate-and-open relaunch path, so it must resolve to nil.
    @Test("Unregistered executables resolve to nil")
    func unregisteredExecutableResolvesToNil() throws {
        try withAgentDirectory([
            "com.apple.Spotlight.plist": [
                "Label": "com.apple.Spotlight",
                "ProgramArguments": ["/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight"],
            ],
        ]) { directory in
            let index = SystemLaunchAgentIndex(directories: [directory])
            #expect(
                index.label(forExecutableAt: URL(
                    fileURLWithPath: "/Applications/Thaw.app/Contents/MacOS/Thaw"
                )) == nil
            )
        }
    }

    /// A malformed or incomplete agent must not take the whole index down
    /// with it: the wave still has to relaunch everything else.
    @Test("Malformed and incomplete agents are skipped")
    func malformedAgentsAreSkipped() throws {
        try withAgentDirectory([
            "no-label.plist": [
                "ProgramArguments": ["/System/Library/CoreServices/NoLabel.app/Contents/MacOS/NoLabel"],
            ],
            "no-program.plist": [
                "Label": "com.example.noProgram",
            ],
            "com.apple.Spotlight.plist": [
                "Label": "com.apple.Spotlight",
                "ProgramArguments": ["/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight"],
            ],
        ]) { directory in
            // A file that is not a property list at all.
            try Data("not a plist".utf8).write(to: directory.appendingPathComponent("garbage.plist"))
            // A file that is a plist but not one we index.
            try Data("ignore me".utf8).write(to: directory.appendingPathComponent("README.txt"))

            let index = SystemLaunchAgentIndex(directories: [directory])
            #expect(
                index.label(forExecutableAt: URL(
                    fileURLWithPath: "/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight"
                )) == "com.apple.Spotlight"
            )
            #expect(
                index.label(forExecutableAt: URL(
                    fileURLWithPath: "/System/Library/CoreServices/NoLabel.app/Contents/MacOS/NoLabel"
                )) == nil
            )
        }
    }

    /// Several stock agents share one binary - SetupAssistant is launched
    /// by four labels, NetAuthAgent by two - so the executable is not a
    /// unique key. Directory order must not decide which label the wave
    /// kickstarts.
    @Test("A shared executable resolves to the same label every time")
    func sharedExecutableResolvesDeterministically() throws {
        let executable = "/System/Library/CoreServices/Setup Assistant.app/Contents/MacOS/Setup Assistant"
        let agents = ["com.apple.mbuseragent", "com.apple.mbfloagent", "com.apple.mbproximityhelper"]
        try withAgentDirectory(
            Dictionary(uniqueKeysWithValues: agents.map { label in
                ("\(label).plist", ["Label": label, "ProgramArguments": [executable]] as [String: Any])
            })
        ) { directory in
            let resolved = (0 ..< 4).map { _ in
                SystemLaunchAgentIndex(directories: [directory])
                    .label(forExecutableAt: URL(fileURLWithPath: executable))
            }
            // The lowest label wins, so the answer does not depend on which
            // order the directory happens to enumerate in.
            #expect(resolved.allSatisfy { $0 == "com.apple.mbfloagent" })
        }
    }

    /// Neither spelling of the path is under our control: the agent may
    /// declare a symlink while `NSRunningApplication.executableURL` reports
    /// the target, or the reverse. Both sides are canonicalized, so either
    /// direction resolves. Normalizing only the lookup side left this case
    /// falling through to the bundle-launch path the type exists to avoid.
    @Test("A symlinked program path resolves when looked up by its target")
    func symlinkedProgramPathResolvesFromTarget() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // The real binary, and a symlink pointing at it.
        let target = tmp.appendingPathComponent("Real")
        try Data("binary".utf8).write(to: target)
        let symlink = tmp.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        // The agent declares the symlink.
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": "com.example.symlinked",
                "ProgramArguments": [symlink.path],
            ] as [String: Any],
            format: .xml,
            options: 0
        )
        try plist.write(to: tmp.appendingPathComponent("com.example.symlinked.plist"))

        let index = SystemLaunchAgentIndex(directories: [tmp])
        // Looked up by the target, which is what the process would report.
        #expect(index.label(forExecutableAt: target) == "com.example.symlinked")
        // And still by the symlink itself.
        #expect(index.label(forExecutableAt: symlink) == "com.example.symlinked")
    }

    /// A missing directory is normal on a stripped-down system and must
    /// not trap.
    @Test("A missing directory yields an empty index")
    func missingDirectoryYieldsEmptyIndex() {
        let index = SystemLaunchAgentIndex(directories: [
            URL(fileURLWithPath: "/does/not/exist", isDirectory: true),
        ])
        #expect(
            index.label(forExecutableAt: URL(
                fileURLWithPath: "/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight"
            )) == nil
        )
    }
}
