import AppKit
import SegueCore

struct ChooserResult {
    var destination: Destination
    var rememberApp = false
    var rememberDomain = false
    var rememberSender = false
    var layoutChangedTo: ChooserSettings.Layout?
}

/// A floating, borderless panel that owns the keyboard while it is up.
/// Click a tile, press its key, Enter for the highlighted one, Esc / click
/// outside to cancel. Closes the moment a choice is made.
@MainActor
final class ChooserPanel: NSPanel {
    private let chooserView: ChooserView
    private let effect = NSVisualEffectView()
    private var completion: ((ChooserResult?) -> Void)?
    private var finished = false
    private var layoutChange: ChooserSettings.Layout?
    private var observers: [Any] = []

    static func present(context: RouteContext, destinations: [Destination], settings: ChooserSettings,
                        supportDirectory: URL, highlightID: String? = nil,
                        completion: @escaping (ChooserResult?) -> Void) -> ChooserPanel {
        let panel = ChooserPanel(context: context, destinations: destinations, settings: settings,
                                 supportDirectory: supportDirectory)
        Timing.mark("panelBuilt")
        panel.completion = completion
        if let highlightID { panel.chooserView.highlight(destinationID: highlightID) }
        panel.show(position: settings.position)
        return panel
    }

    private init(context: RouteContext, destinations: [Destination], settings: ChooserSettings, supportDirectory: URL) {
        chooserView = ChooserView(context: context, destinations: destinations, layout: settings.layout,
                                  scale: settings.textScale, supportDirectory: supportDirectory)
        Timing.mark("viewBuilt")
        super.init(contentRect: NSRect(origin: .zero, size: chooserView.intrinsicContentSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        animationBehavior = .none

        let opaque = Design.increaseContrast
        effect.material = opaque ? .windowBackground : .popover
        effect.blendingMode = opaque ? .withinWindow : .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Design.cornerRadius
        effect.layer?.masksToBounds = true
        if Design.increaseContrast {
            effect.layer?.borderWidth = 2
            effect.layer?.borderColor = NSColor.labelColor.cgColor
        }
        chooserView.frame = NSRect(origin: .zero, size: chooserView.intrinsicContentSize)
        chooserView.autoresizingMask = [.width, .height]
        effect.addSubview(chooserView)
        contentView = effect

        chooserView.onPick = { [weak self] d in self?.finish(with: d) }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: self, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancelIfIdle() }
        })
    }

    /// Renders the panel's content to a PNG (for `--snapshot`, used by agents
    /// that can't take screenshots). Returns false if nothing could be written.
    @discardableResult
    func snapshot(to file: URL) -> Bool {
        chooserView.layoutSubtreeIfNeeded()
        guard let rep = effect.bitmapImageRepForCachingDisplay(in: effect.bounds) else { return false }
        effect.cacheDisplay(in: effect.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: file, options: .atomic)) != nil
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Showing

    private func show(position: ChooserSettings.Position) {
        resizeToFit()
        place(position)
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    private func resizeToFit() {
        let size = chooserView.intrinsicContentSize
        let origin = frame.origin
        setFrame(NSRect(origin: origin, size: size), display: true)
        chooserView.frame = NSRect(origin: .zero, size: size)
        chooserView.needsLayout = true
    }

    private func place(_ position: ChooserSettings.Position) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var origin: NSPoint
        switch position {
        case .center:
            origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2 + visible.height * 0.08)
        case .mouse:
            origin = NSPoint(x: mouse.x - frame.width / 2, y: mouse.y - frame.height + 40)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        setFrameOrigin(origin)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "1": changeLayout(.largeTiles); return
            case "2": changeLayout(.smallTiles); return
            case "3": changeLayout(.compactList); return
            case "w", ".": cancel(); return
            default: break
            }
        }
        switch event.keyCode {
        case 53: // Esc
            if chooserView.filter.isEmpty { cancel() } else { chooserView.filter = "" ; resizeAndKeepPlace() }
            return
        case 36, 76: // Return, Enter
            if let d = chooserView.highlighted { finish(with: d) }
            return
        case 123: chooserView.moveHighlight(dx: -1, dy: 0); return
        case 124: chooserView.moveHighlight(dx: 1, dy: 0); return
        case 126: chooserView.moveHighlight(dx: 0, dy: -1); return
        case 125: chooserView.moveHighlight(dx: 0, dy: 1); return
        case 48: // Tab
            chooserView.moveHighlight(dx: flags.contains(.shift) ? -1 : 1, dy: 0); return
        case 51: // Delete
            if !chooserView.filter.isEmpty { chooserView.filter.removeLast(); resizeAndKeepPlace() }
            return
        default: break
        }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1, !flags.contains(.command), !flags.contains(.control) else {
            super.keyDown(with: event)
            return
        }
        if flags.contains(.shift), ["a", "d", "s"].contains(chars.lowercased()) {
            chooserView.toggleChip(key: chars)
            return
        }
        if let d = chooserView.destination(forKey: chars) {
            finish(with: d)
        } else if chars == "x" && chooserView.filter.isEmpty {
            cancel()
        } else if let scalar = chars.unicodeScalars.first,
                  CharacterSet.alphanumerics.contains(scalar) || chars == " " || chars == "@" || chars == "." {
            chooserView.filter += chars
            resizeAndKeepPlace()
        }
    }

    private func changeLayout(_ kind: ChooserSettings.Layout) {
        layoutChange = kind
        chooserView.setLayout(kind)
        resizeAndKeepPlace()
    }

    private func resizeAndKeepPlace() {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        resizeToFit()
        setFrameOrigin(NSPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2))
        place(.center == .center ? .center : .mouse) // re-clamp to the screen
        setFrameOrigin(NSPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2))
        clampToScreen()
    }

    private func clampToScreen() {
        guard let screen = screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        var o = frame.origin
        o.x = min(max(o.x, v.minX + 8), v.maxX - frame.width - 8)
        o.y = min(max(o.y, v.minY + 8), v.maxY - frame.height - 8)
        setFrameOrigin(o)
    }

    // MARK: - Finishing

    private func finish(with destination: Destination) {
        guard !finished else { return }
        finished = true
        orderOut(nil)
        let result = ChooserResult(destination: destination, rememberApp: chooserView.rememberApp,
                                   rememberDomain: chooserView.rememberDomain, rememberSender: chooserView.rememberSender,
                                   layoutChangedTo: layoutChange)
        completion?(result)
        completion = nil
    }

    private func cancel() {
        guard !finished else { return }
        finished = true
        orderOut(nil)
        completion?(nil)
        completion = nil
    }

    private func cancelIfIdle() {
        // Lost key status without choosing: the user clicked elsewhere.
        if !finished && isVisible { cancel() }
    }
}
