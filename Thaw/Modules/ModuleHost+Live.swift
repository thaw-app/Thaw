//
//  ModuleHost+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Security
import ThawModuleKit

extension ModuleHost {
    /// How Thaw launches a module: in the background, with the host's bundle
    /// ID, and with its window open when the user asked for it.
    static func launchConfiguration(showWindow: Bool) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = showWindow
        configuration.addsToRecentItems = false
        if showWindow {
            configuration.arguments = [ModuleLaunchEnvironment.showWindowArgument]
        }
        if let host = Bundle.main.bundleIdentifier {
            configuration.environment = [ModuleLaunchEnvironment.hostBundleIdentifierKey: host]
        }
        return configuration
    }
}

extension ModuleHost {
    /// The visible .app bundles in each folder, in folder order. A folder that doesn't exist adds none.
    static nonisolated func appBundles(in directories: [URL]) -> [URL] {
        directories.flatMap { directory in
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []
            return contents.filter { $0.pathExtension == "app" }
        }
    }
}

extension ModuleHost.Environment {
    /// The real system: the Modules folders on disk, code signatures and NSWorkspace.
    static func live(
        directories: [URL] = [ModuleHost.modulesDirectory(), ModuleHost.bundledModulesDirectory()]
    ) -> Self {
        Self(
            listBundles: { ModuleHost.appBundles(in: directories) },
            readInfo: { Bundle(url: $0)?.infoDictionary },
            teamID: validTeamID(ofAppAt:),
            ownTeamID: { SettingsURIHandler.teamIdentifier(ofAppAt: Bundle.main.bundleURL, logName: "this app") },
            launch: { url, showWindow in
                try await NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: ModuleHost.launchConfiguration(showWindow: showWindow)
                ).processIdentifier
            },
            terminate: { pid in NSRunningApplication(processIdentifier: pid)?.terminate() },
            isRunning: { pid in NSRunningApplication(processIdentifier: pid)?.isTerminated == false },
            now: { .now },
            wait: { seconds in try? await Task.sleep(for: .seconds(seconds)) },
            loadEnabled: { Defaults.stringArray(forKey: .enabledModules).map(Set.init) },
            saveEnabled: { Defaults.set($0.sorted(), forKey: .enabledModules) },
            enabledByDefault: { identifier in
                ModuleDefaults.startsEnabled(identifier, priorWork: ModuleDefaults.priorWorkInThawSettings(profileFiles: thawProfileFiles))
            }
        )
    }

    /// Every saved profile in Thaw's profiles folder, read as raw JSON.
    private static func thawProfileFiles() -> [Data] {
        let folder = URL.applicationSupportDirectory.appending(path: "Thaw/Profiles", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "profiles.json" }
            .compactMap { try? Data(contentsOf: $0) }
    }

    /// The team ID of a module, read only after its whole signature checks out
    /// and an Apple-issued certificate vouches for that team. Any signer can
    /// write a team into a signature, so the team string alone proves nothing.
    private static func validTeamID(ofAppAt url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil) == errSecSuccess,
              let team = SettingsURIHandler.teamIdentifier(ofAppAt: url, logName: url.lastPathComponent),
              SettingsURISender.isAnchored(staticCode, toTeam: team)
        else {
            return nil
        }
        return team
    }
}
