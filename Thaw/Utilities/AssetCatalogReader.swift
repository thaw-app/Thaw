//
//  AssetCatalogReader.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// 1. Define the Manifest Structure
struct AppMapping: Codable {
    let defaultIcon: String
    let allowPersonalization: Bool?
    let hint: String?
    /// When true, the icon is treated as a template image and tinted
    /// white for the dark menu bar, even if macOS doesn't report it
    /// as a template at runtime (e.g. assets with `template=automatic`).
    let forceTemplate: Bool?
}

/// A namespace for reading compiled asset catalog (.car) files and bundle resources.
enum AssetCatalogReader {
    /// 2. Load the JSON Manifest into memory once
    static let manifest: [String: AppMapping] = {
        guard let url = Bundle.main.url(forResource: "AppIcons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: AppMapping].self, from: data)
        else {
            print("⚠️ Failed to load AppIcons.json manifest")
            return [:]
        }
        return decoded
    }()

    // MARK: - User Icon Overrides

    private static let overridesKey = "MenuBarItemIconOverrides"

    /// User-selected icon overrides, keyed by bundle identifier.
    /// Values are resource names within the app's bundle.
    static var overrides: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: overridesKey) }
    }

    /// Sets (or clears) a user icon override for the given bundle ID.
    static func setOverride(_ resourceName: String?, for bundleID: String) {
        var current = overrides
        current[bundleID] = resourceName
        overrides = current
    }

    /// Returns all loadable image resource names from the given bundle,
    /// suitable for display in an icon picker palette.
    static func discoverAllIcons(in bundleURL: URL) -> [(name: String, image: NSImage)] {
        guard let bundle = Bundle(url: bundleURL) else { return [] }

        var results = [(name: String, image: NSImage)]()
        var seen = Set<String>()

        func tryAdd(_ name: String) {
            guard !seen.contains(name) else { return }
            if let img = bundle.image(forResource: name) {
                seen.insert(name)
                results.append((name, img))
            }
        }

        // Probe manifest name for this bundle.
        if let bundleID = bundle.bundleIdentifier, let mapping = manifest[bundleID] {
            tryAdd(mapping.defaultIcon)
        }

        // Scan the asset catalog for all image assets.
        let carURL = bundle.resourceURL?.appendingPathComponent("Assets.car")
        if let carURL, FileManager.default.fileExists(atPath: carURL.path),
           let allNames = extractAssetNames(from: carURL)
        {
            for name in allNames.sorted() {
                tryAdd(name)
            }
        }

        // Also scan loose image resources in the bundle.
        if let resourceURL = bundle.resourceURL,
           let contents = try? FileManager.default.contentsOfDirectory(
               at: resourceURL,
               includingPropertiesForKeys: nil
           )
        {
            for url in contents {
                let ext = url.pathExtension.lowercased()
                guard ["png", "tiff", "pdf", "icns"].contains(ext) else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                tryAdd(name)
            }
        }

        return results
    }

    /// Extracts unique asset names from a compiled .car file using assetutil.
    private static func extractAssetNames(from carURL: URL) -> Set<String>? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--sdk", "macosx", "assetutil", "--info", carURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }

        var names = Set<String>()
        for entry in json {
            if let name = entry["Name"] as? String, !name.isEmpty,
               !name.hasPrefix("ZZZZ"), !name.hasPrefix("AppIcon")
            {
                names.insert(name)
            }
        }
        return names
    }

    // MARK: - Public API

    static func findBestIcon(in bundleURL: URL, hint _: String?) -> (name: String, image: NSImage)? {
        guard let bundle = Bundle(url: bundleURL),
              let bundleID = bundle.bundleIdentifier
        else {
            return generateFallbackIcon(for: bundleURL)
        }

        // TIER 0: User-selected override.
        if let overrideName = overrides[bundleID],
           let result = resolveIcon(overrideName, bundle: bundle, forceTemplate: false)
        {
            return result
        }

        // TIER 1: The Known-App Manifest (Instant & 100% Accurate)
        if let mapping = manifest[bundleID] {
            if let result = resolveIcon(mapping.defaultIcon, bundle: bundle, forceTemplate: mapping.forceTemplate == true) {
                return result
            }
        }

        // TIER 2: The App Icon Fallback
        return generateFallbackIcon(for: bundleURL)
    }

    // MARK: - Icon Resolution

    /// Resolves an icon name to an NSImage. Supports prefixes:
    /// - `"sf:symbol.name"` — loads an SF Symbol
    /// - `"mono:resourceName"` — loads from bundle, rendered as white filled silhouette
    /// - `"resourceName"` — loads from the app bundle
    private static func resolveIcon(_ name: String, bundle: Bundle, forceTemplate: Bool) -> (name: String, image: NSImage)? {
        let isMono = name.hasPrefix("mono:")
        let resolvedName = isMono ? String(name.dropFirst(5)) : name

        if resolvedName.hasPrefix("sf:") {
            let symbolName = String(resolvedName.dropFirst(3))
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            else {
                return nil
            }
            image.isTemplate = true
            return (name, image)
        }

        guard let image = bundle.image(forResource: resolvedName) else {
            return nil
        }

        if isMono {
            // Don't set isTemplate — we want the original pixel data preserved.
            // The mono: flag is handled by renderNSImage which applies the
            // white tint after drawing the full-color image.
        } else if forceTemplate
            || resolvedName.lowercased().contains("template")
            || image.isTemplate
        {
            image.isTemplate = true
        }
        return (name, image)
    }

    // MARK: - Fallback Generator

    /// Generates a fallback icon using the app's main icon, scaled down.
    static func generateFallbackIcon(for bundleURL: URL) -> (name: String, image: NSImage)? {
        // 1. Get the official App Icon from macOS
        let appIcon = NSWorkspace.shared.icon(forFile: bundleURL.path)

        // 2. Resize it cleanly for the menu bar
        let targetSize = NSSize(width: 32, height: 32)
        let scaledImage = NSImage(size: targetSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            appIcon.draw(
                in: rect,
                from: NSRect(origin: .zero, size: appIcon.size),
                operation: .sourceOver,
                fraction: 1.0
            )
            return true
        }

        // 3. CRITICAL: Do NOT set isTemplate = true.
        // If we do, macOS will use the solid squarcle alpha channel and draw a solid block.
        scaledImage.isTemplate = false

        let appName = bundleURL.deletingPathExtension().lastPathComponent
        return ("Fallback App Icon: \(appName)", scaledImage)
    }

    /// Safely scales an NSImage up or down while preserving its Template (Dark Mode) status.
    static func resize(image: NSImage, to targetSize: NSSize) -> NSImage {
        let scaledImage = NSImage(size: targetSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(
                in: rect,
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: 1.0
            )
            return true
        }

        // CRITICAL: If the original was a template (changes color in Dark Mode),
        // the new resized version MUST also be a template!
        scaledImage.isTemplate = image.isTemplate

        return scaledImage
    }
}
