import AppKit
import SegueCore

/// Zero-config first run: build sensible destinations from what's installed.
/// Mail apps, Gmail for every Google account signed into a Chromium profile
/// (or one plain Gmail in the default browser), and a Copy button.
@MainActor
enum Discovery {
    static func proposeDestinations() -> [Destination] {
        var out: [Destination] = []
        var usedIDs = Set<String>()
        func add(_ d: Destination) {
            var d = d
            var id = d.id
            var n = 2
            while usedIDs.contains(id) { id = "\(d.id)-\(n)"; n += 1 }
            d.id = id
            usedIDs.insert(id)
            out.append(d)
        }

        let browsers = installedBrowsers()
        let defaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }

        // Gmail per signed-in Chromium profile.
        var gmailCount = 0
        for browser in browsers where BrowserLauncher.family(of: browser.bundleID) == .chromium {
            let profiles = ChromiumProfiles.profiles(forBundleID: browser.bundleID)
            for p in profiles {
                guard let email = p.userName else { continue }
                var d = Destination(id: "gmail-" + slug(email), name: "Gmail — \(email)", type: .webmail)
                d.provider = .gmail
                d.account = WebmailAccount(email: email)
                d.browser = BrowserTarget(bundleID: browser.bundleID, profile: p.directory, profileName: p.name)
                d.sendsAs = [email]
                if browsers.filter({ BrowserLauncher.family(of: $0.bundleID) == .chromium }).count > 1 {
                    d.name += " (\(browser.name))"
                }
                add(d)
                gmailCount += 1
            }
        }
        if gmailCount == 0 {
            var d = Destination(id: "gmail", name: "Gmail", type: .webmail)
            d.provider = .gmail
            d.browser = BrowserTarget(bundleID: defaultBrowser)
            add(d)
        }

        // Desktop mail apps, Mail.app first.
        for app in installedMailApps().prefix(4) {
            var d = Destination(id: slug(app.name), name: app.name, type: .app)
            d.bundleID = app.bundleID
            add(d)
        }

        var copy = Destination(id: "copy", name: "Copy address", type: .clipboard)
        copy.copy = .addresses
        add(copy)

        // Keys: 1–9, then letters (skipping x, which cancels).
        let keys = Array("123456789abdefghijklmnopqrstuvwyz").map(String.init)
        for i in out.indices where i < keys.count { out[i].key = keys[i] }
        return out
    }

    struct InstalledApp { var bundleID: String; var name: String; var url: URL }

    static func installedMailApps() -> [InstalledApp] {
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "mailto:")!)
        var apps = urls.compactMap(app(at:)).filter {
            $0.bundleID != Bundle.main.bundleIdentifier && BrowserLauncher.family(of: $0.bundleID) == .other
                && !$0.bundleID.hasPrefix("com.apple.") || $0.bundleID == "com.apple.mail"
        }
        apps.sort { a, b in
            if a.bundleID == "com.apple.mail" { return true }
            if b.bundleID == "com.apple.mail" { return false }
            return a.name < b.name
        }
        return apps
    }

    static func installedBrowsers() -> [InstalledApp] {
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        return urls.compactMap(app(at:)).filter { BrowserLauncher.family(of: $0.bundleID) != .other }
            .sorted { $0.name < $1.name }
    }

    private static func app(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(bundleID: id, name: name, url: url)
    }

    static func slug(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber { out.append(ch) } else if !out.hasSuffix("-") { out.append("-") }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
