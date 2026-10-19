import AppKit
import SegueCore

/// Segue launches per event and quits after the hand-off. The delegate's job is
/// to receive the event (a mailto: URL or an .eml file), show the right surface
/// as fast as possible, and terminate once the work is done.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options = AppOptions.parse()
    private(set) lazy var configStore = ConfigStore(directory: options.supportDirectory)
    private(set) lazy var config: Config = configStore.load()
    private lazy var launcher: Launcher = {
        let l = Launcher(supportDirectory: options.supportDirectory)
        l.dryRunFile = options.dryRunFile
        return l
    }()

    /// Work that arrived during launch, so we don't show the placeholder.
    private var pendingWork = 0
    private var placeholderWindow: NSWindow?
    private var chooser: ChooserPanel?
    private var readers: [ReaderWindowController] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        Timing.mark("willFinishLaunching")
        Log.fileURL = options.supportDirectory.appendingPathComponent("segue.log")
        Log.write("launch \(SegueVersion.string) args=\(CommandLine.arguments.dropFirst().joined(separator: " "))")
        // Register before the launch events arrive. The system delivers a
        // kAEGetURL for a mailto: that caused a cold launch right after this.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("didFinishLaunching pendingWork=\(pendingWork)")
        if pendingWork == 0 {
            showPlaceholder()
        }
        // Off the hot path: make sure LaunchServices knows where we live.
        DispatchQueue.global(qos: .utility).async { DefaultHandler.registerSelf() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !config.general.stayRunning && pendingWork == 0
    }

    // MARK: - Incoming events

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        Timing.mark("event")
        pendingWork += 1
        let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? ""
        let source = SourceAppResolver.resolve(event: event)
        let forced = NSEvent.modifierFlags.contains(config.chooser.forceModifier.eventFlag)

        if MailtoParser.isMailto(urlString) {
            ensureConfigExists()
            let request = MailtoParser.parse(urlString, options: .init(plusAsSpace: config.general.plusAsSpace))
            let context = RouteContext(kind: .mailto, request: request, source: source, forceChooser: forced)
            route(context)
        } else if urlString.lowercased().hasPrefix("x-segue:") {
            Log.write(String(format: "x-segue:// commands arrive in M11 (%@)", urlString))
            finishWork()
        } else {
            Log.write(String(format: "ignoring URL %@", urlString))
            finishWork()
        }
    }

    /// AppKit can deliver the same document twice on a cold launch.
    private var recentlyOpened: [URL: Date] = [:]

    func application(_ application: NSApplication, open urls: [URL]) {
        Log.write("open files: \(urls.map(\.path))")
        for url in urls {
            if let t = recentlyOpened[url], Date().timeIntervalSince(t) < 2 { continue }
            recentlyOpened[url] = Date()
            let ext = url.pathExtension.lowercased()
            if ext == "eml" || ext == "emlx" {
                pendingWork += 1
                openMessage(at: url)
            } else {
                Log.write(String(format: "ignoring file %@", url.path))
            }
        }
    }

    // MARK: - .eml reader

    private func openMessage(at url: URL) {
        Timing.mark("emlOpen")
        ensureConfigExists()
        let message: EmailMessage
        do { message = try MIMEParser.parse(fileURL: url) } catch {
            Log.write(String(format: "cannot read %@: %@", url.path, error.localizedDescription))
            finishWork()
            return
        }
        let myAddresses = config.myAddresses
        var original = message.original
        original.deliveredTo = message.resolvedDeliveredTo(myAddresses: myAddresses)
        let source = SourceAppResolver.frontmost()

        // Rules only *suggest* for a file (opening one is deliberate), unless eml.autoRoute.
        let preview = RouteContext(kind: .reply, request: ReplyBuilder.build(.reply, from: message, myAddresses: myAddresses),
                                   source: source, original: original)
        let suggestion = RuleEngine.evaluate(preview, config: config)
        if config.eml.autoRoute, let s = suggestion, let d = config.destination(id: s.destinationID) {
            Log.write(String(format: ".eml auto-routed → %@ (%@)", d.name, s.explanation.text))
            route(message: message, kind: .reply, to: d, original: original, source: source)
            return
        }

        Log.write("parsed \(url.lastPathComponent): subject=\(message.subject) warnings=\(message.parseWarnings) suggestion=\(suggestion?.destinationID ?? "-")")
        let reader = ReaderWindowController.present(
            message: message, fileURL: url, config: config, supportDirectory: options.supportDirectory,
            suggestedID: suggestion?.destinationID,
            onChoice: { [weak self] choice in
                guard let self else { return }
                self.route(message: message, kind: choice.kind, to: choice.destination, original: original, source: source)
            },
            onClose: { [weak self] in
                guard let self else { return }
                self.readers.removeAll { $0.window == nil || !$0.window!.isVisible }
                self.finishWork()
            })
        readers.append(reader)
        Timing.mark("readerShown")
        Log.write("reader shown")
        if let file = options.snapshotFile {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak reader] in
                reader?.snapshot(to: file)
                NSApp.terminate(nil)
            }
        }
        if let marker = options.startupMarker { StartupMarker.write(to: marker) }
    }

    /// A "Reply with …" click. Gmail destinations that hold the message get
    /// the real thread (threaded reply, attachments intact); everything else
    /// gets a compose request with the original quoted.
    private func route(message: EmailMessage, kind: ReplyBuilder.Kind, to destination: Destination,
                       original: OriginalMessage, source: SourceApp?) {
        if destination.type == .webmail, destination.provider == .gmail, let messageID = message.messageID,
           holds(destination, deliveredTo: original.deliveredTo),
           let url = ComposeRequest.gmailThreadURL(messageID: messageID, account: destination.account ?? WebmailAccount(email: destination.primarySendsAs)) {
            Log.write(String(format: "opening the thread in %@", destination.name))
            launcher.open(url: url, browser: destination.browser, destinationID: destination.id) { [weak self] result in
                if case .failure(let error) = result { NSLog("Segue: could not open %@: %@", destination.name, error.localizedDescription) }
                self?.finishWork()
            }
            return
        }
        let request = ReplyBuilder.build(kind, from: message, myAddresses: config.myAddresses)
        let contextKind: RouteContext.Kind = kind == .reply ? .reply : (kind == .replyAll ? .replyAll : .forward)
        let context = RouteContext(kind: contextKind, request: request, source: source, original: original)
        launch(destination, for: context)
    }

    private func holds(_ destination: Destination, deliveredTo: String?) -> Bool {
        guard let received = deliveredTo?.lowercased() else { return false }
        let mine = (destination.sendsAs ?? []).map { $0.lowercased() }
        if mine.contains(received) { return true }
        return destination.account?.email?.lowercased() == received
    }

    // MARK: - Routing

    private func route(_ context: RouteContext) {
        let router = Router(config: config, supportDirectory: options.supportDirectory)
        switch router.decide(context) {
        case .launch(let destination, let explanation):
            Log.write(String(format: "%@ → %@ (%@)", context.request.primaryRecipient, destination.name, explanation.text))
            launch(destination, for: context)
        case .chooser(let reason):
            Log.write(String(format: "chooser (%@)", reason))
            showChooser(for: context)
        }
    }

    private func showChooser(for context: RouteContext) {
        Timing.mark("routed")
        let destinations = config.activeDestinations
        let learned = LearnedChoices(directory: options.supportDirectory)
        let highlight = config.chooser.learnDefault
            ? learned.suggestion(for: context, validIDs: Set(destinations.map(\.id))) : nil
        chooser = ChooserPanel.present(context: context, destinations: destinations, settings: config.chooser,
                                       supportDirectory: options.supportDirectory, highlightID: highlight) { [weak self] result in
            guard let self else { return }
            self.chooser = nil
            var configChanged = false
            if let layout = result?.layoutChangedTo {
                self.config.chooser.layout = layout
                configChanged = true
            }
            guard let result else {
                if configChanged { try? self.configStore.save(self.config) }
                // Cancelled: hand focus back to where the link came from.
                NSApp.hide(nil)
                self.finishWork()
                return
            }
            if self.config.chooser.learnDefault {
                learned.record(context, destinationID: result.destination.id)
            }
            if let rule = Rule.remembered(context: context, destination: result.destination,
                                          app: result.rememberApp, domain: result.rememberDomain, sender: result.rememberSender) {
                self.config.rules.append(rule)
                configChanged = true
                Log.write(String(format: "new rule “%@”", rule.name))
            }
            if configChanged { try? self.configStore.save(self.config) }
            self.launch(result.destination, for: context)
        }
        Timing.mark("chooserShown")
        if let file = options.snapshotFile {
            DispatchQueue.main.async { [weak self] in
                self?.chooser?.snapshot(to: file)
                NSApp.terminate(nil)
            }
            return
        }
        if let marker = options.startupMarker {
            // Cold-start measurement: the chooser is up, that's the number.
            StartupMarker.write(to: marker)
        }
    }

    /// First run: no config file at all. Build one from what's installed so
    /// the first chooser already has useful buttons.
    private func ensureConfigExists() {
        guard !configStore.exists else { return }
        var fresh = Config()
        fresh.destinations = Discovery.proposeDestinations()
        try? configStore.save(fresh)
        config = configStore.load()
        Log.write(String(format: "first run, proposed %d destinations", fresh.destinations.count))
    }

    private func launch(_ destination: Destination, for context: RouteContext) {
        launcher.launch(destination, for: context.request) { [weak self] result in
            switch result {
            case .success(let plan):
                if let note = plan.note { NSLog("Segue: %@", note) }
            case .failure(let error):
                Log.write(String(format: "could not open %@: %@", destination.name, error.localizedDescription))
            }
            self?.finishWork()
        }
    }

    /// One unit of work is done. Quit unless a window keeps us alive or the
    /// user opted into staying resident.
    private func finishWork() {
        pendingWork = max(0, pendingWork - 1)
        if let marker = options.startupMarker, chooser == nil {
            StartupMarker.write(to: marker)
            return
        }
        guard pendingWork == 0, placeholderWindow == nil, chooser == nil, readers.isEmpty, !config.general.stayRunning else { return }
        // Give the launched app's activation a moment to land, then go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Placeholder window (until M10's main window)

    private func showPlaceholder() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Segue"
        window.center()
        window.isReleasedWhenClosed = false

        let status = DefaultHandler.isSegueDefaultForMailto() ? "Segue is the default email app." : "Segue is not the default email app yet."
        let label = NSTextField(labelWithString: "Segue \(SegueVersion.string)\n\(status)")
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: window.contentView!.leadingAnchor, constant: 20),
        ])

        placeholderWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if let marker = options.startupMarker { StartupMarker.write(to: marker) }
    }
}

extension ChooserSettings.Modifier {
    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .option: return .option
        case .shift: return .shift
        case .control: return .control
        case .command: return .command
        }
    }
}
