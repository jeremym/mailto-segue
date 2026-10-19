import AppKit
import SegueCore

/// The content of the chooser: a header with the recipient and subject, the
/// tiles in one of three layouts, a filter line when typing, and a footer of
/// key hints. Pure layout; the panel owns the keyboard.
@MainActor
final class ChooserView: NSView {
    struct Metrics {
        var columns: Int
        var tileSize: NSSize
        var gap: CGFloat
        var style: TileView.Style
    }

    let context: RouteContext
    let scale: Double
    private(set) var layoutKind: ChooserSettings.Layout
    private let supportDirectory: URL
    private let allDestinations: [Destination]

    private(set) var visible: [Destination] = []
    private(set) var tiles: [TileView] = []
    private(set) var highlightedIndex = 0
    var filter = "" { didSet { applyFilter() } }

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let sourceChip = NSTextField(labelWithString: "")
    private let filterLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(labelWithString: "")
    private let tilesContainer = FlippedView()
    private var chips: [ChipView] = []
    private(set) var rememberApp = false
    private(set) var rememberDomain = false
    private(set) var rememberSender = false

    var onPick: ((Destination) -> Void)?

    init(context: RouteContext, destinations: [Destination], layout: ChooserSettings.Layout,
         scale: Double, supportDirectory: URL) {
        self.context = context
        self.allDestinations = destinations
        self.layoutKind = layout
        self.scale = scale
        self.supportDirectory = supportDirectory
        super.init(frame: .zero)
        wantsLayer = true

        let r = context.request
        let who = r.to.isEmpty ? (r.cc.first?.description ?? "No recipient") : r.to.map(\.description).joined(separator: ", ")
        titleLabel.stringValue = context.kind == .mailto ? who : "\(context.kind.label): \(who)"
        titleLabel.font = Design.font(17, weight: .bold, scale: scale)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.stringValue = (r.subject ?? "").isEmpty ? "No subject" : r.subject!
        subtitleLabel.font = Design.font(13, scale: scale)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        if let s = context.source {
            sourceChip.stringValue = "from \(s.name)" + (s.guessed ? " (guessed)" : "")
            sourceChip.toolTip = s.guessed ? "Guessed from the frontmost app" : s.bundleID
        }
        sourceChip.font = Design.font(11, weight: .medium, scale: scale)
        sourceChip.textColor = .secondaryLabelColor
        sourceChip.alignment = .right
        filterLabel.font = Design.font(14, weight: .medium, scale: scale)
        filterLabel.textColor = .controlAccentColor
        footerLabel.font = Design.font(11, scale: scale)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.alignment = .center

        for v in [titleLabel, subtitleLabel, sourceChip, filterLabel, tilesContainer, footerLabel] { addSubview(v) }
        buildChips()
        rebuildTiles()
    }

    // MARK: - Remember chips (⇧A app · ⇧D domain · ⇧S sender)

    private func buildChips() {
        var specs: [(String, String)] = []
        if let s = context.source { specs.append(("⇧A", "Always for \(s.name)")) }
        if let d = context.request.to.first?.domain, !d.isEmpty { specs.append(("⇧D", "Always for \(d)")) }
        if let d = context.original?.from?.domain, !d.isEmpty { specs.append(("⇧S", "Always from \(d)")) }
        chips = specs.map { key, text in
            let chip = ChipView(key: key, text: text, scale: scale)
            chip.onToggle = { [weak self] in self?.toggleChip(key: key) }
            addSubview(chip)
            return chip
        }
    }

    func toggleChip(key: String) {
        switch key.uppercased() {
        case "⇧A", "A": rememberApp.toggle()
        case "⇧D", "D": rememberDomain.toggle()
        case "⇧S", "S": rememberSender.toggle()
        default: return
        }
        for chip in chips {
            switch chip.key {
            case "⇧A": chip.isOn = rememberApp
            case "⇧D": chip.isOn = rememberDomain
            case "⇧S": chip.isOn = rememberSender
            default: break
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: - Layout kinds

    func setLayout(_ kind: ChooserSettings.Layout) {
        guard kind != layoutKind else { return }
        layoutKind = kind
        rebuildTiles()
    }

    var metrics: Metrics {
        let s = CGFloat(scale)
        let hasAddresses = visible.contains { $0.primarySendsAs != nil }
        switch layoutKind {
        case .largeTiles:
            // pad + image + gap + name line + address line + pad, so the tile hugs its content.
            let h = 14 + 64 + 8 + 15 * s * 1.3 + (hasAddresses ? 2 + 11 * s * 1.4 : 0) + 14
            return Metrics(columns: min(3, max(1, visible.count)), tileSize: NSSize(width: 150 * s, height: h), gap: 10, style: .large)
        case .smallTiles:
            let h = 10 + 36 + 6 + 13 * s * 1.4 + 10
            return Metrics(columns: min(5, max(1, visible.count)), tileSize: NSSize(width: 100 * s, height: h), gap: 8, style: .small)
        case .compactList:
            let h = (hasAddresses ? 15 * s * 1.4 + 11 * s * 1.4 : 13 * s * 1.4) + 14
            return Metrics(columns: 1, tileSize: NSSize(width: 420 * s, height: h), gap: 4, style: .row)
        }
    }

    private func rebuildTiles() {
        tiles.forEach { $0.removeFromSuperview() }
        visible = allDestinations.filter(matchesFilter)
        tiles = visible.map { d in
            let t = TileView(destination: d, style: metrics.style, scale: scale, supportDirectory: supportDirectory)
            t.onClick = { [weak self] in self?.onPick?(d) }
            tilesContainer.addSubview(t)
            return t
        }
        highlightedIndex = min(highlightedIndex, max(0, tiles.count - 1))
        updateHighlight()
        filterLabel.stringValue = filter.isEmpty ? "" : "Filter: \(filter)"
        footerLabel.stringValue = footerText
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func applyFilter() {
        highlightedIndex = 0
        rebuildTiles()
    }

    private func matchesFilter(_ d: Destination) -> Bool {
        guard !filter.isEmpty else { return true }
        let f = filter.lowercased()
        return d.name.lowercased().contains(f)
            || (d.primarySendsAs ?? "").lowercased().contains(f)
            || (d.provider?.displayName.lowercased().contains(f) ?? false)
    }

    private var footerText: String {
        var parts = ["Enter picks the highlighted", "Esc cancels"]
        if layoutKind != .compactList { parts.append("type to filter") }
        parts.append("⌘1 ⌘2 ⌘3 change the layout")
        return parts.joined(separator: " · ")
    }

    // MARK: - Highlight and selection

    func highlight(_ index: Int) {
        guard !tiles.isEmpty else { return }
        highlightedIndex = (index + tiles.count) % tiles.count
        updateHighlight()
    }

    func highlight(destinationID: String) {
        if let i = visible.firstIndex(where: { $0.id == destinationID }) { highlight(i) }
    }

    func moveHighlight(dx: Int, dy: Int) {
        guard !tiles.isEmpty else { return }
        let cols = metrics.columns
        var next = highlightedIndex + dx + dy * cols
        if next < 0 { next = dx < 0 ? tiles.count - 1 : highlightedIndex }
        if next >= tiles.count { next = dx > 0 ? 0 : highlightedIndex }
        highlight(next)
    }

    var highlighted: Destination? { tiles.isEmpty ? nil : visible[highlightedIndex] }

    func destination(forKey key: String) -> Destination? {
        guard filter.isEmpty else { return nil }
        return visible.first { $0.key?.lowercased() == key.lowercased() }
    }

    private func updateHighlight() {
        for (i, t) in tiles.enumerated() { t.isHighlighted = i == highlightedIndex }
    }

    // MARK: - Geometry

    private var headerHeight: CGFloat {
        titleLabel.font!.pointSize * 1.5 + subtitleLabel.font!.pointSize * 1.5 + 6
    }

    private var filterHeight: CGFloat { filter.isEmpty ? 0 : filterLabel.font!.pointSize * 1.8 }

    private var chipsHeight: CGFloat { chips.isEmpty ? 0 : 11 * CGFloat(scale) * 1.4 + 12 + 8 }

    private var tilesSize: NSSize {
        let m = metrics
        let count = max(1, tiles.count)
        let rows = Int(ceil(Double(count) / Double(m.columns)))
        let width = CGFloat(m.columns) * m.tileSize.width + CGFloat(m.columns - 1) * m.gap
        let height = CGFloat(rows) * m.tileSize.height + CGFloat(rows - 1) * m.gap
        return NSSize(width: max(width, 360 * CGFloat(scale)), height: tiles.isEmpty ? 60 : height)
    }

    override var intrinsicContentSize: NSSize {
        let pad: CGFloat = 20
        let t = tilesSize
        let footer = footerLabel.font!.pointSize * 1.6
        return NSSize(width: t.width + 2 * pad,
                      height: pad + headerHeight + 10 + filterHeight + t.height + 12 + chipsHeight + footer + pad - 6)
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 20
        let w = bounds.width - 2 * pad
        var y = pad
        let chipW: CGFloat = sourceChip.stringValue.isEmpty ? 0 : min(280, w * 0.5)
        titleLabel.frame = NSRect(x: pad, y: y, width: w - chipW - 8, height: titleLabel.font!.pointSize * 1.5)
        sourceChip.frame = NSRect(x: bounds.width - pad - chipW, y: y + 2, width: chipW, height: sourceChip.font!.pointSize * 1.5)
        y += titleLabel.frame.height + 2
        subtitleLabel.frame = NSRect(x: pad, y: y, width: w, height: subtitleLabel.font!.pointSize * 1.5)
        y += subtitleLabel.frame.height + 10
        if !filter.isEmpty {
            filterLabel.frame = NSRect(x: pad, y: y, width: w, height: filterHeight)
            y += filterHeight
        } else {
            filterLabel.frame = .zero
        }
        let t = tilesSize
        tilesContainer.frame = NSRect(x: pad + (w - t.width) / 2, y: y, width: t.width, height: t.height)
        let m = metrics
        for (i, tile) in tiles.enumerated() {
            let col = i % m.columns
            let row = i / m.columns
            tile.frame = NSRect(x: CGFloat(col) * (m.tileSize.width + m.gap),
                                y: CGFloat(row) * (m.tileSize.height + m.gap),
                                width: m.tileSize.width, height: m.tileSize.height)
        }
        y += t.height + 12
        if !chips.isEmpty {
            var x = pad
            let h = chipsHeight - 8
            for chip in chips {
                let cw = chip.preferredWidth
                chip.frame = NSRect(x: x, y: y, width: cw, height: h)
                x += cw + 8
            }
            y += chipsHeight
        }
        footerLabel.frame = NSRect(x: pad, y: y, width: w, height: footerLabel.font!.pointSize * 1.6)
    }

    override func draw(_ dirtyRect: NSRect) {
        if tiles.isEmpty {
            let msg = NSAttributedString(string: filter.isEmpty ? "No destinations." : "Nothing matches “\(filter)”.", attributes: [
                .font: Design.font(14, scale: scale), .foregroundColor: NSColor.secondaryLabelColor,
            ])
            let s = msg.size()
            msg.draw(at: NSPoint(x: tilesContainer.frame.midX - s.width / 2, y: tilesContainer.frame.midY - s.height / 2))
        }
    }
}

extension RouteContext.Kind {
    var label: String {
        switch self {
        case .mailto: return "Email"
        case .reply: return "Reply"
        case .replyAll: return "Reply all"
        case .forward: return "Forward"
        case .cli: return "Email"
        }
    }
}

/// A container whose origin is top-left, like the chooser view itself.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A toggle pill: "⇧A  Always for Slack". Click or press the key.
@MainActor
final class ChipView: NSView {
    let key: String
    private let label = NSTextField(labelWithString: "")
    var onToggle: (() -> Void)?
    var isOn = false { didSet { needsDisplay = true; label.textColor = isOn ? .white : .secondaryLabelColor } }

    init(key: String, text: String, scale: Double) {
        self.key = key
        super.init(frame: .zero)
        label.stringValue = "\(key)  \(text)"
        label.font = Design.font(11, weight: .medium, scale: scale)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(text)
    }

    required init?(coder: NSCoder) { fatalError() }

    var preferredWidth: CGFloat { min(label.cell!.cellSize.width + 24, 260) }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 12, dy: 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        if isOn {
            NSColor.controlAccentColor.setFill()
            path.fill()
        } else {
            NSColor.labelColor.withAlphaComponent(Design.increaseContrast ? 0.14 : 0.07).setFill()
            path.fill()
            if Design.increaseContrast {
                NSColor.labelColor.withAlphaComponent(0.5).setStroke()
                path.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) { onToggle?() }
    override func accessibilityValue() -> Any? { isOn }
    override func accessibilityPerformPress() -> Bool { onToggle?(); return true }
}
