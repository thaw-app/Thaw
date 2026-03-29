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

    // MARK: - Public API

    static func findBestIcon(in bundleURL: URL, hint _: String?) -> (name: String, image: NSImage)? {
        guard let bundle = Bundle(url: bundleURL),
              let bundleID = bundle.bundleIdentifier
        else {
            return generateFallbackIcon(for: bundleURL)
        }

        // TIER 1: The Known-App Manifest (Instant & 100% Accurate)
        if let mapping = manifest[bundleID] {
            // macOS natively extracts it from the Assets.car or Resources folder
            if let exactImage = bundle.image(forResource: mapping.defaultIcon) {
                // Ensure it respects Dark Mode if it's a template
                if mapping.defaultIcon.lowercased().contains("template") || exactImage.isTemplate {
                    exactImage.isTemplate = true
                }

                // 🚀 NEW: Scale the native icon up so it doesn't look tiny!
                let largerSize = NSSize(width: 24, height: 24) // Change to 32x32 if needed
                let embiggenedImage = resize(image: exactImage, to: largerSize)

                return (mapping.defaultIcon, embiggenedImage)
            }
        }

        // TIER 2: The App Icon Fallback
        // If the app isn't in the JSON (like Cursor or cmux), we immediately
        // generate a clean, scaled-down version of its main app icon.
        return generateFallbackIcon(for: bundleURL)
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
