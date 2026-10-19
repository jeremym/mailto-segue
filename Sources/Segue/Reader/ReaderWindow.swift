import AppKit
import SegueCore

/// The `.eml` reader: headers on top, the message in the middle, and the same
/// big destination buttons below as "Reply with …". Clicking one closes the
/// window at once. There is no text field anywhere; Segue never composes.
@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate {
    struct Choice {
        var kind: ReplyBuilder.Kind
        var destination: Destination
    }

    private let message: EmailMessage
    private let fileURL: URL
    private let config: Config
    private let supportDirectory: URL
    private let suggestedID: String?
    private var onChoice: ((Choice) -> Void)?
    private var onClose: (() -> Void)?

    private var kind: ReplyBuilder.Kind = .reply
    private let kindControl = NSSegmentedControl(labels: ["Reply", "Reply All", "Forward"], trackingMode: .selectOne, target: nil, action: nil)
    private var tiles: [TileView] = []
    private var highlighted = 0
    private var textScale: CGFloat
    private let textView = ReaderTextView()
    private var htmlView: SafeHTMLView?
    private var showingHTML = false
    private let bodyContainer = NSView()
    private let headerBox = NSStackView()
    private let tilesRow = FlippedView()
    private let hintLabel = NSTextField(labelWithString: "")
    private var headerLabels: [NSTextField] = []

    static func present(message: EmailMessage, fileURL: URL, config: Config, supportDirectory: URL,
                        suggestedID: String?, onChoice: @escaping (Choice) -> Void, onClose: @escaping () -> Void) -> ReaderWindowController {
        let c = ReaderWindowController(message: message, fileURL: fileURL, config: config, supportDirectory: supportDirectory, suggestedID: suggestedID)
        c.onChoice = onChoice
        c.onClose = onClose
        c.showWindow(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        c.window?.makeKeyAndOrderFront(nil)
        return c
    }

    private init(message: EmailMessage, fileURL: URL, config: Config, supportDirectory: URL, suggestedID: String?) {
        self.message = message
        self.fileURL = fileURL
        self.config = config
        self.supportDirectory = supportDirectory
        self.suggestedID = suggestedID
        self.textScale = CGFloat(config.chooser.textScale)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = message.subject.isEmpty ? fileURL.lastPathComponent : message.subject
        window.minSize = NSSize(width: 560, height: 480)
        window.center()
        window.setFrameAutosaveName("SegueReader")
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func build() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 12, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Headers
        headerBox.orientation = .vertical
        headerBox.alignment = .leading
        headerBox.spacing = 3
        func headerLine(_ label: String, _ value: String, bold: Bool = false) {
            guard !value.isEmpty else { return }
            let field = NSTextField(labelWithString: "")
            let attr = NSMutableAttributedString(string: label + "  ", attributes: [
                .font: Design.font(13, weight: .semibold, scale: textScale), .foregroundColor: NSColor.secondaryLabelColor])
            attr.append(NSAttributedString(string: value, attributes: [
                .font: Design.font(bold ? 17 : 13, weight: bold ? .bold : .regular, scale: textScale), .foregroundColor: NSColor.labelColor]))
            field.attributedStringValue = attr
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 2
            headerBox.addArrangedSubview(field)
            headerLabels.append(field)
        }
        headerLine("Subject", message.subject.isEmpty ? "(no subject)" : message.subject, bold: true)
        headerLine("From", message.from.map(\.description).joined(separator: ", "))
        headerLine("To", message.to.map(\.description).joined(separator: ", "))
        headerLine("Cc", message.cc.map(\.description).joined(separator: ", "))
        headerLine("Date", message.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? (message.dateText ?? ""))
        if !message.attachments.isEmpty {
            headerLine("Attachments", message.attachments.map { "\($0.filename) (\(ByteCountFormatter.string(fromByteCount: Int64($0.size), countStyle: .file)))" }.joined(separator: ", "))
        }
        root.addArrangedSubview(headerBox)
        headerBox.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true

        // Body: plain text by default; HTML on demand.
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.wantsLayer = true
        bodyContainer.layer?.cornerRadius = 10
        bodyContainer.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        root.addArrangedSubview(bodyContainer)
        bodyContainer.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true
        bodyContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        bodyContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.font = Design.font(15, scale: textScale)
        textView.textColor = .labelColor
        textView.string = message.bestText.isEmpty ? "(empty message)" : message.bestText
        scroll.documentView = textView
        bodyContainer.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])

        // Controls row: Reply / Reply All / Forward, Show HTML, Reveal attachments
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 12
        kindControl.selectedSegment = 0
        kindControl.target = self
        kindControl.action = #selector(kindChanged)
        kindControl.font = Design.font(13, scale: textScale)
        controls.addArrangedSubview(kindControl)
        if message.htmlBody != nil {
            let b = NSButton(title: "Show HTML", target: self, action: #selector(toggleHTML))
            b.bezelStyle = .rounded
            b.font = Design.font(13, scale: textScale)
            controls.addArrangedSubview(b)
        }
        if !message.attachments.isEmpty {
            let b = NSButton(title: "Reveal attachments", target: self, action: #selector(revealAttachments))
            b.bezelStyle = .rounded
            b.font = Design.font(13, scale: textScale)
            controls.addArrangedSubview(b)
        }
        if !message.parseWarnings.isEmpty {
            let b = NSButton(title: "Show raw source", target: self, action: #selector(showRaw))
            b.bezelStyle = .rounded
            controls.addArrangedSubview(b)
        }
        root.addArrangedSubview(controls)

        // Tiles: "Reply with …"
        let destinations = config.activeDestinations
        let small = destinations.count > 4
        for (i, d) in destinations.enumerated() {
            var shown = d
            if d.id == suggestedID { shown.name = d.name + " ★" }
            let tile = TileView(destination: shown, style: small ? .small : .large, scale: Double(textScale), supportDirectory: supportDirectory)
            tile.onClick = { [weak self] in self?.choose(i) }
            tilesRow.addSubview(tile)
            tiles.append(tile)
        }
        tilesRow.translatesAutoresizingMaskIntoConstraints = false
        let tileH: CGFloat = small ? (10 + 36 + 6 + 13 * textScale * 1.4 + 10) : (14 + 64 + 8 + 15 * textScale * 1.3 + 2 + 11 * textScale * 1.4 + 14)
        root.addArrangedSubview(tilesRow)
        tilesRow.heightAnchor.constraint(equalToConstant: tiles.isEmpty ? 40 : tileH).isActive = true
        tilesRow.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true
        if let s = suggestedID, let i = destinations.firstIndex(where: { $0.id == s }) { highlighted = i }
        updateHighlight()

        hintLabel.stringValue = destinations.isEmpty
            ? "No destinations yet. Add one in Segue's settings."
            : "★ = the account that received this · Enter picks the highlighted · R / A / F switch · ⌘+ ⌘− zoom · Esc closes"
        hintLabel.font = Design.font(11, scale: textScale)
        hintLabel.textColor = .tertiaryLabelColor
        root.addArrangedSubview(hintLabel)

        window?.contentView?.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: window?.contentView, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.layoutTiles() }
        }
        DispatchQueue.main.async { [weak self] in self?.layoutTiles() }
    }

    private func layoutTiles() {
        guard !tiles.isEmpty else { return }
        let w = tilesRow.bounds.width
        let gap: CGFloat = 8
        let count = CGFloat(tiles.count)
        let tileW = min(150 * textScale, (w - gap * (count - 1)) / count)
        for (i, t) in tiles.enumerated() {
            t.frame = NSRect(x: CGFloat(i) * (tileW + gap), y: 0, width: tileW, height: tilesRow.bounds.height)
        }
    }

    private func updateHighlight() {
        for (i, t) in tiles.enumerated() { t.isHighlighted = i == highlighted }
    }

    // MARK: - Actions

    @objc private func kindChanged() {
        kind = [.reply, .replyAll, .forward][max(0, kindControl.selectedSegment)]
    }

    @objc private func toggleHTML() {
        guard let html = message.htmlBody else { return }
        if showingHTML {
            htmlView?.removeFromSuperview()
            showingHTML = false
            return
        }
        let view = htmlView ?? SafeHTMLView.make()
        htmlView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])
        view.show(html: html)
        showingHTML = true
    }

    @objc private func revealAttachments() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Segue attachments/" + fileURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for a in message.attachments {
            let safe = a.filename.replacingOccurrences(of: "/", with: "-")
            let url = dir.appendingPathComponent(safe)
            if (try? a.data.write(to: url, options: .atomic)) != nil { urls.append(url) }
        }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    @objc private func showRaw() {
        if let data = try? Data(contentsOf: fileURL) {
            textView.string = String(decoding: data, as: UTF8.self)
            textView.font = .monospacedSystemFont(ofSize: 12 * textScale, weight: .regular)
        }
    }

    private func choose(_ index: Int) {
        guard index < tiles.count else { return }
        let destination = tiles[index].destination
        let choice = Choice(kind: kind, destination: destination)
        let handler = onChoice
        onChoice = nil
        onClose = nil
        close()
        handler?(choice)
    }

    func windowWillClose(_ notification: Notification) {
        let handler = onClose
        onClose = nil
        onChoice = nil
        handler?()
    }

    /// Renders the window content to a PNG (for `--snapshot`).
    @discardableResult
    func snapshot(to file: URL) -> Bool {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: file, options: .atomic)) != nil
    }

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "=", "+": zoom(by: 0.1); return
            case "-": zoom(by: -0.1); return
            default: break
            }
        }
        switch event.keyCode {
        case 53: close(); return
        case 36, 76: choose(highlighted); return
        case 123, 126: highlighted = (highlighted - 1 + max(1, tiles.count)) % max(1, tiles.count); updateHighlight(); return
        case 124, 125, 48: highlighted = (highlighted + 1) % max(1, tiles.count); updateHighlight(); return
        default: break
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !flags.contains(.command) else { super.keyDown(with: event); return }
        switch chars {
        case "r": kindControl.selectedSegment = 0; kindChanged()
        case "a": kindControl.selectedSegment = 1; kindChanged()
        case "f": kindControl.selectedSegment = 2; kindChanged()
        default:
            if let i = tiles.firstIndex(where: { $0.destination.key?.lowercased() == chars }) { choose(i) } else { super.keyDown(with: event) }
        }
    }

    private func zoom(by delta: CGFloat) {
        textScale = min(3, max(0.8, textScale + delta))
        textView.font = Design.font(15, scale: textScale)
        htmlView?.pageZoom = textScale / CGFloat(config.chooser.textScale)
    }
}

/// A read-only text view that lets the reader's shortcuts through instead of
/// swallowing (and beeping at) every key.
@MainActor
final class ReaderTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        if let controller = window?.windowController as? ReaderWindowController {
            controller.keyDown(with: event)
        } else {
            super.keyDown(with: event)
        }
    }
}
