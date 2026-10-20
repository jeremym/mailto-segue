import AppKit
import SegueCore

/// One big button: image, name, the address it sends as, and its key.
@MainActor
final class TileView: NSView {
    enum Style { case large, small, row }

    let destination: Destination
    let style: Style
    var onClick: (() -> Void)?

    var isHighlighted = false { didSet { needsDisplay = true } }
    var dimmed = false { didSet { alphaValue = dimmed ? 0.35 : 1 } }

    private let imageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let addressLabel = NSTextField(labelWithString: "")
    private let keyLabel = NSTextField(labelWithString: "")
    private let accent: NSColor

    init(destination: Destination, style: Style, scale: Double, supportDirectory: URL) {
        self.destination = destination
        self.style = style
        self.accent = Design.color(hex: destination.color) ?? .controlAccentColor
        super.init(frame: .zero)
        wantsLayer = true

        let imageSize: CGFloat = style == .large ? 64 : (style == .small ? 36 : 28)
        imageView.image = TileImageCache.image(for: destination, supportDirectory: supportDirectory, size: imageSize)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.stringValue = destination.name
        nameLabel.font = Design.font(style == .large ? 15 : 13, weight: .semibold, scale: scale)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.alignment = style == .row ? .left : .center
        addressLabel.stringValue = destination.primarySendsAs ?? ""
        addressLabel.font = Design.font(11, scale: scale)
        addressLabel.textColor = .secondaryLabelColor
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.alignment = style == .row ? .left : .center
        keyLabel.stringValue = destination.key ?? ""
        keyLabel.font = Design.monoFont(12, scale: scale)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.alignment = .center

        for v in [imageView, nameLabel, addressLabel, keyLabel] { addSubview(v) }

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        var label = destination.name
        if let a = destination.primarySendsAs { label += ", sends as \(a)" }
        if let k = destination.key { label += ", key \(k)" }
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let b = bounds
        let pad: CGFloat = 10
        switch style {
        case .large:
            let img = imageView.image?.size.width ?? 64
            imageView.frame = NSRect(x: (b.width - img) / 2, y: pad + 4, width: img, height: img)
            let nameH = nameLabel.font!.pointSize * 1.3
            nameLabel.frame = NSRect(x: pad, y: imageView.frame.maxY + 8, width: b.width - 2 * pad, height: nameH)
            addressLabel.frame = NSRect(x: pad, y: nameLabel.frame.maxY + 2, width: b.width - 2 * pad, height: addressLabel.font!.pointSize * 1.4)
            addressLabel.isHidden = addressLabel.stringValue.isEmpty
            keyLabel.frame = NSRect(x: b.width - 30, y: 6, width: 24, height: keyLabel.font!.pointSize * 1.4)
        case .small:
            let img = imageView.image?.size.width ?? 36
            imageView.frame = NSRect(x: (b.width - img) / 2, y: pad, width: img, height: img)
            nameLabel.frame = NSRect(x: 4, y: imageView.frame.maxY + 6, width: b.width - 8, height: nameLabel.font!.pointSize * 1.4)
            addressLabel.isHidden = true
            keyLabel.frame = NSRect(x: b.width - 24, y: 4, width: 20, height: keyLabel.font!.pointSize * 1.4)
        case .row:
            let img = imageView.image?.size.width ?? 28
            imageView.frame = NSRect(x: pad, y: (b.height - img) / 2, width: img, height: img)
            let keyW: CGFloat = 36
            let textX = imageView.frame.maxX + 10
            let textW = b.width - textX - keyW - pad
            let nameH = nameLabel.font!.pointSize * 1.4
            let addrH = addressLabel.stringValue.isEmpty ? 0 : addressLabel.font!.pointSize * 1.4
            let top = (b.height - nameH - addrH) / 2
            nameLabel.frame = NSRect(x: textX, y: top, width: textW, height: nameH)
            addressLabel.frame = NSRect(x: textX, y: top + nameH, width: textW, height: addrH)
            addressLabel.isHidden = addrH == 0
            keyLabel.frame = NSRect(x: b.width - keyW - pad + 6, y: (b.height - nameH) / 2, width: keyW, height: nameH)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: Design.tileCornerRadius, yRadius: Design.tileCornerRadius)
        let contrast = Design.increaseContrast
        if isHighlighted {
            accent.withAlphaComponent(contrast ? 0.35 : 0.18).setFill()
            path.fill()
            accent.setStroke()
            path.lineWidth = contrast ? 4 : 3
            path.stroke()
        } else {
            NSColor.labelColor.withAlphaComponent(contrast ? 0.12 : 0.06).setFill()
            path.fill()
            if contrast {
                NSColor.labelColor.withAlphaComponent(0.5).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
