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

    func applicationWillFinishLaunching(_ notification: Notification) {
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
        if pendingWork == 0 {
            showPlaceholder()
        }
        // Off the hot path: make sure LaunchServices knows where we live.
        DispatchQueue.global(qos: .utility).async { DefaultHandler.registerSelf() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !config.general.stayRunning
    }

    // MARK: - Incoming events

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        pendingWork += 1
        let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? ""
        let source = SourceAppResolver.resolve(event: event)
        let forced = NSEvent.modifierFlags.contains(config.chooser.forceModifier.eventFlag)

        if MailtoParser.isMailto(urlString) {
            let request = MailtoParser.parse(urlString, options: .init(plusAsSpace: config.general.plusAsSpace))
            let context = RouteContext(kind: .mailto, request: request, source: source, forceChooser: forced)
            route(context)
        } else if urlString.lowercased().hasPrefix("x-segue:") {
            NSLog("Segue: x-segue:// commands arrive in M11 (%@)", urlString)
            finishWork()
        } else {
            NSLog("Segue: ignoring URL %@", urlString)
            finishWork()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingWork += 1
        for url in urls {
            NSLog("Segue: .eml files open in M8 (%@)", url.path)
        }
        finishWork()
    }

    // MARK: - Routing

    private func route(_ context: RouteContext) {
        let router = Router(config: config, supportDirectory: options.supportDirectory)
        switch router.decide(context) {
        case .launch(let destination, let reason):
            NSLog("Segue: %@ → %@ (%@)", context.request.primaryRecipient, destination.name, reason)
            launch(destination, for: context)
        case .chooser(let reason):
            // M4 builds the chooser. Until then, the first destination stands in.
            if let first = config.activeDestinations.first {
                NSLog("Segue: chooser wanted (%@); M3 uses %@", reason, first.name)
                launch(first, for: context)
            } else {
                launch(Router.mailAppFallback, for: context)
            }
        }
    }

    private func launch(_ destination: Destination, for context: RouteContext) {
        launcher.launch(destination, for: context.request) { [weak self] result in
            switch result {
            case .success(let plan):
                if let note = plan.note { NSLog("Segue: %@", note) }
            case .failure(let error):
                NSLog("Segue: could not open %@: %@", destination.name, error.localizedDescription)
            }
            self?.finishWork()
        }
    }

    /// One unit of work is done. Quit unless a window keeps us alive or the
    /// user opted into staying resident.
    private func finishWork() {
        pendingWork = max(0, pendingWork - 1)
        if let marker = options.startupMarker {
            StartupMarker.write(to: marker)
            return
        }
        guard pendingWork == 0, placeholderWindow == nil, !config.general.stayRunning else { return }
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
