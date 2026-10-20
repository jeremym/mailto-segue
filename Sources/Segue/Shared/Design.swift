import AppKit

/// Type and color tokens. Everything is large by default: the chooser is
/// used for a second at a time, and it has to be readable at a glance.
enum Design {
    static let cornerRadius: CGFloat = 18
    static let tileCornerRadius: CGFloat = 14

    static func font(_ size: CGFloat, weight: NSFont.Weight = .regular, scale: Double = 1) -> NSFont {
        .systemFont(ofSize: size * scale, weight: weight)
    }

    static func monoFont(_ size: CGFloat, scale: Double = 1) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size * scale, weight: .semibold)
    }

    @MainActor
    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    @MainActor
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func color(hex: String?) -> NSColor? {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
