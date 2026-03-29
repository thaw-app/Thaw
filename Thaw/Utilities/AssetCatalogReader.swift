//
//  AssetCatalogReader.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
import Cocoa
import ImageIO
import os

/// A namespace for reading compiled asset catalog (.car) files and bundle resources.
enum AssetCatalogReader {
    // MARK: - Symbol Mapping

    private static let sfSymbolMap: [String: String] = [
        "clock": "clock", "sound": "speaker.wave.2", "volume": "speaker.wave.2",
        "wi-fi": "wifi", "wifi": "wifi", "control center": "slider.horizontal.3",
        "battery": "battery.100", "bluetooth": "bluetooth", "display": "display",
        "brightness": "sun.max", "focus": "moon", "screen mirroring": "airplayvideo",
        "now playing": "music.note", "siri": "mic", "time machine": "clock.arrow.circlepath",
        "vpn": "network", "stage manager": "square.3.layers.3d", "keyboard": "keyboard",
        "input": "keyboard", "spotlight": "magnifyingglass", "airdrop": "airdrop",
        "user": "person.crop.circle", "account": "person.crop.circle",
    ]

    // MARK: - Pre-compiled Regex Patterns
    private static let strongRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern:
                    "(tray|menubar|menu[-_]?bar|statusbar|status[-_]?bar|statusitem|status[-_]?item)",
                options: .caseInsensitive
            )
        } catch {
            fatalError("Failed to compile strongRegex pattern: \(error.localizedDescription)")
        }
    }()

    private static let weakRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern:
                    "(status|indicator|badge|notification|systray|toolbar[-_]?icon|mono|template)",
                options: .caseInsensitive
            )
        } catch {
            fatalError("Failed to compile weakRegex pattern: \(error.localizedDescription)")
        }
    }()

    private static let sizePenaltyRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: "(512|1024)",
                options: []
            )
        } catch {
            fatalError("Failed to compile sizePenaltyRegex pattern: \(error.localizedDescription)")
        }
    }()

    // MARK: - Scoring
    private static func bestScoringImage(
        from images: [CatalogImage],
        hintLowercased: String?,
        threshold: Int
    ) -> CatalogImage? {
        var bestImage: CatalogImage?
        var bestScore = threshold

        for image in images {
            let score = image.score(hintLowercased: hintLowercased)
            guard score >= threshold else { continue }
            if bestImage == nil || score > bestScore {
                bestImage = image
                bestScore = score
            }
        }

        return bestImage
    }

    struct CatalogImage {
        let name: String
        let size: CGSize
        let isTemplate: Bool
        let imageLoader: () -> NSImage?

        func score(hintLowercased: String?) -> Int {
            var s = 0
            let range = NSRange(name.startIndex..., in: name)

            // 1. Regex Keyword Matches (Single pass per category)
            let strongMatches = AssetCatalogReader.strongRegex.numberOfMatches(
                in: name, range: range
            )
            s += strongMatches * 20

            let weakMatches = AssetCatalogReader.weakRegex.numberOfMatches(in: name, range: range)
            s += weakMatches * 5

            // 2. Hint Match
            let lowerName = name.lowercased()
            if let hint = hintLowercased, hint.count > 2, lowerName.contains(hint) { s += 8 }

            // 3. Template Heuristics
            if isTemplate { s += 10 }
            if lowerName.contains("template") { s += 6 }  // Kept as simple contains, highly optimized

            // 4. Size Heuristics
            if size.height > 0 {
                if size.height >= 14 && size.height <= 24 {
                    s += 10
                    if size.height >= 16 && size.height <= 22 { s += 5 }
                }
                if size.height > 32 || size.width > 64 { s -= 20 }
            }

            // 5. String penalties & bonuses
            if lowerName.contains("16") || lowerName.contains("18") || lowerName.contains("22") {
                s += 3
            }

            if AssetCatalogReader.sizePenaltyRegex.firstMatch(in: name, range: range) != nil {
                s -= 10
            }

            if name.hasSuffix(".pdf") { s += 3 }
            if lowerName.contains("@2x") { s += 3 }
            if lowerName.contains("@3x") { s -= 1 }

            if lowerName.contains("dark") { s -= 2 }
            if lowerName.contains("light") { s -= 1 }

            return s
        }
    }

    // MARK: - Cache
    private struct CacheEntry {
        let modificationDate: Date
        let images: [CatalogImage]
    }

    private enum CacheType { case catalog, resource }

    private static let lock = OSAllocatedUnfairLock<
        (
            catalogCache: [URL: CacheEntry],
            resourceCache: [URL: CacheEntry],
            negativeCache: Set<URL>
        )
    >(initialState: (catalogCache: [:], resourceCache: [:], negativeCache: []))

    private static func cachedImages(for url: URL, modificationDate: Date, type: CacheType)
        -> [CatalogImage]?
    {
        lock.withLock { state in
            if state.negativeCache.contains(url) { return [] }
            let cache = (type == .catalog) ? state.catalogCache : state.resourceCache
            guard let entry = cache[url], entry.modificationDate == modificationDate else {
                return nil
            }
            return entry.images
        }
    }

    private static func cacheImages(
        _ images: [CatalogImage], for url: URL, modificationDate: Date, type: CacheType
    ) {
        lock.withLock { state in
            if images.isEmpty {
                state.negativeCache.insert(url)
            } else if type == .catalog {
                state.catalogCache[url] = CacheEntry(modificationDate: modificationDate, images: images)
            } else {
                state.resourceCache[url] = CacheEntry(modificationDate: modificationDate, images: images)
            }
        }
    }

    // MARK: - Public API
    static func findBestIcon(in bundleURL: URL, hint: String?) -> (name: String, image: NSImage)? {
        let threshold = 30
        let hintLowercased = hint?.lowercased()

        // 1. Asset Catalog (O(N) Max Finding)
        let catalogImages = templateImages(fromBundle: bundleURL)
        if let best = bestScoringImage(
            from: catalogImages,
            hintLowercased: hintLowercased,
            threshold: threshold
        ), let img = best.imageLoader() {
            return (best.name, img)
        }

        // 2. Resources
        let resources = resourceImages(fromBundle: bundleURL)
        if let best = bestScoringImage(
            from: resources,
            hintLowercased: hintLowercased,
            threshold: threshold
        ), let img = best.imageLoader() {
            return (best.name, img)
        }

        // 3. Fallback: app icon silhouette
        if let fallbackIcon = generateFallbackIcon(for: bundleURL) {
            return fallbackIcon
        }

        // 4. SF Symbol Fallback (Absolute Last Resort)
        if let hintLowercased = hintLowercased, let symbol = sfSymbolFallback(for: hintLowercased) {
            return ("SF Symbol: \(hint ?? "")", symbol)
        }

        return nil
    }

    static func templateImages(fromBundle bundleURL: URL) -> [CatalogImage] {
        let carURL = bundleURL.appendingPathComponent("Contents/Resources/Assets.car")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: carURL.path),
            let modDate = attrs[.modificationDate] as? Date
        else { return [] }

        if let cached = cachedImages(for: carURL, modificationDate: modDate, type: .catalog) {
            return cached
        }

        let images = readTemplateImages(bundleURL: bundleURL, carURL: carURL)
        cacheImages(images, for: carURL, modificationDate: modDate, type: .catalog)
        return images
    }

    static func resourceImages(fromBundle bundleURL: URL) -> [CatalogImage] {
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resourcesURL.path),
            let modDate = attrs[.modificationDate] as? Date
        else { return [] }

        if let cached = cachedImages(for: resourcesURL, modificationDate: modDate, type: .resource)
        {
            return cached
        }

        guard
            let contents = try? FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil)
        else { return [] }

        let imageExts: Set<String> = ["png", "pdf", "tiff", "icns"]
        var images = [CatalogImage]()

        for url in contents {
            let ext = url.pathExtension.lowercased()
            guard imageExts.contains(ext) else { continue }

            let name = url.lastPathComponent

            // Early out on obvious garbage to avoid even fetching sizes
            let lowerName = name.lowercased()
            if lowerName.contains("appicon") { continue }

            let isTemplate = lowerName.contains("template")

            // Fast size extraction: reads file header instead of decoding pixels
            var size: CGSize = .zero
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
                let h = props[kCGImagePropertyPixelHeight] as? CGFloat
            {
                size = CGSize(width: w, height: h)
            }

            images.append(
                CatalogImage(
                    name: name,
                    size: size,
                    isTemplate: isTemplate,
                    imageLoader: {
                        let img = NSImage(contentsOf: url)
                        img?.isTemplate = isTemplate
                        return img
                    }
                )
            )
        }

        cacheImages(images, for: resourcesURL, modificationDate: modDate, type: .resource)
        return images
    }

    static func sfSymbolFallback(for hintLowercased: String) -> NSImage? {
        for (key, symbol) in sfSymbolMap where hintLowercased.contains(key) {
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                let configured = img.withSymbolConfiguration(config) ?? img
                configured.isTemplate = true
                return configured
            }
        }
        return nil
    }

    /// Generates a fallback icon using the app's main icon, scaled down.
    static func generateFallbackIcon(for bundleURL: URL) -> (name: String, image: NSImage)? {
        // 1. Get the official App Icon from macOS
        let appIcon = NSWorkspace.shared.icon(forFile: bundleURL.path)

        // 2. Resize it cleanly for the menu bar
        let targetSize = NSSize(width: 32, height: 32)
        let scaledImage = NSImage(size: targetSize)

        scaledImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        appIcon.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: appIcon.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        scaledImage.unlockFocus()

        // 3. CRITICAL: Do NOT set isTemplate = true.
        // If we do, macOS will use the solid squarcle alpha channel and draw a solid block.
        scaledImage.isTemplate = false

        let appName = bundleURL.deletingPathExtension().lastPathComponent
        return ("Fallback App Icon: \(appName)", scaledImage)
    }

    // MARK: - CoreUI Metadata + Bundle Loading
    private static func readTemplateImages(bundleURL: URL, carURL: URL) -> [CatalogImage] {
        guard FileManager.default.fileExists(atPath: carURL.path),
            let bundle = Bundle(url: bundleURL),
            let catalogClass = NSClassFromString("CUICatalog") as? NSObject.Type
        else { return [] }

        guard
            let alloc = catalogClass.perform(NSSelectorFromString("alloc"))?
                .takeUnretainedValue() as? NSObject
        else { return [] }
        let initSel = NSSelectorFromString("initWithURL:error:")
        guard alloc.responds(to: initSel) else { return [] }

        var error: NSError?
        let catalogResult = withUnsafeMutablePointer(to: &error) { errorPtr -> NSObject? in
            let impl = alloc.method(for: initSel)
            typealias InitMethod =
                @convention(c) (NSObject, Selector, URL, UnsafeMutablePointer<NSError?>) ->
                NSObject?
            let method = unsafeBitCast(impl, to: InitMethod.self)
            return method(alloc, initSel, carURL, errorPtr)
        }
        guard let catalog = catalogResult else { return [] }

        let imageNamesSel = NSSelectorFromString("allImageNames")
        guard catalog.responds(to: imageNamesSel),
            let namesResult = catalog.perform(imageNamesSel)?.takeUnretainedValue(),
            let imageNames = namesResult as? [String]
        else { return [] }

        var images = [CatalogImage]()

        for name in imageNames {
            // Early optimization: Skip app icons entirely before hitting CoreUI methods
            if name.lowercased().contains("appicon") { continue }

            if let catalogImage = loadImageMetadata(named: name, from: catalog, bundle: bundle) {
                images.append(catalogImage)
            }
        }

        return images
    }

    private static func loadImageMetadata(
        named name: String, from catalog: NSObject, bundle: Bundle
    ) -> CatalogImage? {
        let imageSel = NSSelectorFromString("imageWithName:scaleFactor:")
        guard catalog.responds(to: imageSel) else { return nil }

        let impl = catalog.method(for: imageSel)
        typealias ImageMethod = @convention(c) (NSObject, Selector, NSString, CGFloat) -> NSObject?
        let method = unsafeBitCast(impl, to: ImageMethod.self)

        guard
            let namedImage = method(catalog, imageSel, name as NSString, 2.0)
                ?? method(catalog, imageSel, name as NSString, 1.0)
        else {
            return nil
        }

        let templateMode =
            (namedImage.responds(to: NSSelectorFromString("templateRenderingMode"))
                ? namedImage.value(forKey: "templateRenderingMode") as? Int : 0) ?? 0

        let isTemplate: Bool
        if templateMode == 1 {
            isTemplate = true
        } else if templateMode == 0 && name.localizedCaseInsensitiveContains("Template") {
            isTemplate = true
        } else if templateMode == 2 {
            return nil  // Explicitly not a template, and we likely don't want it
        } else {
            isTemplate = false
        }

        guard let size = namedImage.value(forKey: "size") as? CGSize, size.width > 0,
            size.height > 0
        else {
            return nil
        }

        // Defer NSImage creation
        let loader: () -> NSImage? = {
            var nsImage = bundle.image(forResource: name)
            if nsImage == nil {
                let variants = [
                    name.replacingOccurrences(of: "-", with: "_"),
                    name.replacingOccurrences(of: "_", with: "-"),
                ]
                for variant in variants {
                    if let img = bundle.image(forResource: variant) {
                        nsImage = img
                        break
                    }
                }
            }
            nsImage?.isTemplate = isTemplate
            return nsImage
        }

        return CatalogImage(name: name, size: size, isTemplate: isTemplate, imageLoader: loader)
    }
}
