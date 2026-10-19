import AppKit
import SegueCore

/// The picture on a tile, in the order the plan lists: a custom image, the
/// app's own icon, the service mark (M9) or a lettered circle, with the
/// browser's icon as a small badge for webmail.
@MainActor
enum TileImages {
    static func image(for destination: Destination, supportDirectory: URL, size: CGFloat) -> NSImage {
        if let custom = customImage(destination, supportDirectory: supportDirectory) {
            return fitted(custom, size: size)
        }
        switch destination.type {
        case .app:
            if let id = destination.bundleID, let icon = appIcon(bundleID: id) {
                return fitted(icon, size: size)
            }
            return symbol("envelope.fill", size: size, color: .systemGray)
        case .browserHandler, .template:
            if let id = destination.browser?.bundleID, !(destination.browser?.isSystemDefault ?? true),
               let icon = appIcon(bundleID: id) {
                return fitted(icon, size: size)
            }
            if let icon = defaultBrowserIcon() { return fitted(icon, size: size) }
            return symbol("globe", size: size, color: .systemBlue)
        case .clipboard:
            return symbol("doc.on.clipboard.fill", size: size, color: .systemGray)
        case .webmail:
            let color = Design.color(hex: destination.color) ?? Design.color(hex: destination.provider?.brandColorHex) ?? .systemBlue
            let letter = String((destination.provider?.displayName ?? destination.name).prefix(1)).uppercased()
            var base = letterCircle(letter, color: color, size: size)
            if let badge = browserBadge(destination.browser, size: size) {
                base = composite(base, badge: badge, size: size)
            }
            return base
        }
    }

    // MARK: - Sources

    private static func customImage(_ d: Destination, supportDirectory: URL) -> NSImage? {
        guard let rel = d.image, !rel.isEmpty else { return nil }
        let url = rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : supportDirectory.appendingPathComponent(rel)
        return NSImage(contentsOf: url)
    }

    static func appIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func defaultBrowserIcon() -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func browserBadge(_ target: BrowserTarget?, size: CGFloat) -> NSImage? {
        let icon: NSImage?
        if let id = target?.bundleID, !(target?.isSystemDefault ?? true) {
            icon = appIcon(bundleID: id)
        } else {
            icon = defaultBrowserIcon()
        }
        return icon.map { fitted($0, size: size * 0.45) }
    }

    // MARK: - Drawing

    static func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.6, weight: .medium)
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
            if let base {
                let tinted = base.tinted(color)
                let s = tinted.size
                tinted.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
            }
            return true
        }
    }

    static func letterCircle(_ letter: String, color: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size * 0.55, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let text = NSAttributedString(string: letter, attributes: attrs)
            let ts = text.size()
            text.draw(at: NSPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2 - size * 0.02))
            return true
        }
    }

    private static func composite(_ base: NSImage, badge: NSImage, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            base.draw(in: rect)
            let b = badge.size
            let origin = NSPoint(x: size - b.width + size * 0.06, y: -size * 0.06)
            badge.draw(in: NSRect(origin: origin, size: b))
            return true
        }
    }

    static func fitted(_ image: NSImage, size: CGFloat) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: size, height: size)
        return copy
    }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = copy() as! NSImage
        img.lockFocus()
        color.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
