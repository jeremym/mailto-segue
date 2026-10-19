import AppKit
import SegueCore

/// Segue launches per event and quits after the hand-off. The delegate's job is
/// to receive the event (a mailto: URL or an .eml file), show the right surface
/// as fast as possible, and terminate once the work is done.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        // No URL or file arrived during launch, so this is a plain "open the
        // app" launch. M0 shows a placeholder; later milestones show the main
        // window here.
        if pendingWork == 0 {
            showPlaceholder()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Events

    /// Counts work that arrived during launch so we don't show the placeholder.
    private var pendingWork = 0

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        pendingWork += 1
        let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? ""
        let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let sender = senderPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } ?? "unknown"
        NSLog("Segue: received %@ from %@ (M0: nothing is routed yet)", urlString, sender)
        quitSoon()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingWork += 1
        for url in urls {
            NSLog("Segue: asked to open %@ (M0: nothing is routed yet)", url.path)
        }
        quitSoon()
    }

    // MARK: - Placeholder window (M0)

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

        let label = NSTextField(labelWithString: "Segue \(SegueVersion.string)\nNothing to route yet.")
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
        ])

        placeholderWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        StartupMarker.writeIfRequested()
    }

    private func quitSoon() {
        // Give NSLog / any pending NSWorkspace calls a moment, then exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }
}
