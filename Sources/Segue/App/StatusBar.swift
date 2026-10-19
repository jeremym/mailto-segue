import AppKit
import SegueCore

/// The menu-bar item, present only in `stayRunning` mode: recent hand-offs,
/// Open Segue, Pause rules, a warning if the config is broken, Quit.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    weak var delegate: AppDelegate?

    init(delegate: AppDelegate) {
        self.delegate = delegate
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "envelope.arrow.triangle.branch", accessibilityDescription: "Segue")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        item.menu = menu
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let delegate else { return }
        let config = delegate.currentConfig

        let open = NSMenuItem(title: "Open Segue", action: #selector(openMain), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let recent = delegate.recentHistory(limit: 5)
        if recent.isEmpty {
            let none = NSMenuItem(title: "No recent hand-offs", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for h in recent {
                let title = "\(h.primaryRecipient.isEmpty ? "(no recipient)" : h.primaryRecipient) → \(h.destinationName)"
                let mi = NSMenuItem(title: title, action: #selector(openHistory), keyEquivalent: "")
                mi.target = self
                mi.toolTip = h.subject
                menu.addItem(mi)
            }
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause rules", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = config.general.rulesPaused ? .on : .off
        menu.addItem(pause)

        if !DefaultHandler.isSegueDefaultForMailto() {
            let def = NSMenuItem(title: "Make Segue the default email app…", action: #selector(makeDefault), keyEquivalent: "")
            def.target = self
            menu.addItem(def)
        }
        if let err = delegate.configErrorText {
            let warn = NSMenuItem(title: "⚠︎ config.json has a problem", action: #selector(openSettings), keyEquivalent: "")
            warn.target = self
            warn.toolTip = err
            menu.addItem(warn)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Segue", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openMain() { delegate?.showMainWindow() }
    @objc private func openHistory() { delegate?.showMainWindow(section: .history) }
    @objc private func openSettings() { delegate?.showMainWindow(section: .settings) }
    @objc private func togglePause() { delegate?.toggleRulesPaused() }
    @objc private func makeDefault() { delegate?.makeDefaultFromMenu() }
    @objc private func quit() { NSApp.terminate(nil) }
}
