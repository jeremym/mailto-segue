import AppKit
import SegueCore

/// Rendered tile images on disk, so a cold launch never asks LaunchServices
/// for app icons or rasterises anything. Keyed by the destination, the size,
/// the appearance and Segue's version. Cleared by Settings (M10) and on
/// upgrade (the version is in the key, so old entries just go stale).
@MainActor
enum TileImageCache {
    static func image(for destination: Destination, supportDirectory: URL, size: CGFloat) -> NSImage {
        let dir = supportDirectory.appendingPathComponent("cache/tiles", isDirectory: true)
        let file = dir.appendingPathComponent(key(destination, size: size) + ".png")
        if let cached = NSImage(contentsOf: file) {
            cached.size = NSSize(width: size, height: size)
            return cached
        }
        let image = TileImages.image(for: destination, supportDirectory: supportDirectory, size: size)
        store(image, size: size, at: file, in: dir)
        return image
    }

    static func clear(supportDirectory: URL) {
        try? FileManager.default.removeItem(at: supportDirectory.appendingPathComponent("cache/tiles", isDirectory: true))
    }

    private static func key(_ d: Destination, size: CGFloat) -> String {
        var parts = [d.id, d.type.rawValue, d.provider?.rawValue ?? "", d.bundleID ?? "", d.browser?.bundleID ?? "",
                     d.color ?? "", d.image ?? "", d.name, "\(Int(size))", SegueVersion.string,
                     NSApp.effectiveAppearance.name.rawValue, Design.increaseContrast ? "hc" : ""]
        if let rel = d.image, !rel.isEmpty {
            let url = rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : URL(fileURLWithPath: rel)
            let mod = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parts.append("\(mod)")
        }
        // FNV-1a, 64-bit: plenty for a cache key and avoids linking CryptoKit at launch.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in parts.joined(separator: "\u{1f}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private static func store(_ image: NSImage, size: CGFloat, at file: URL, in dir: URL) {
        // Render at 2x so Retina tiles stay crisp.
        let scale: CGFloat = 2
        let pixel = Int(size * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: file, options: .atomic)
    }
}
