import AppKit
import SegueCore

/// Opens a URL in a browser, optionally in a specific profile, container or
/// window mode. Everything here mirrors what `open -na <Browser> --args …`
/// does, so there is no Automation permission involved.
enum BrowserLauncher {
    enum Family { case chromium, firefox, safari, other }

    static func family(of bundleID: String) -> Family {
        switch bundleID {
        case "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
             "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
             "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
             "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium",
             "company.thebrowser.Browser" /* Arc: no profile flag, but --app works */:
            return .chromium
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
             "app.zen-browser.zen", "org.torproject.torbrowser":
            return .firefox
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return .safari
        default:
            return .other
        }
    }

    /// The command-line arguments that pick the profile/container/window.
    /// The URL is always last. Empty when the browser needs no arguments, in
    /// which case the caller should pass the URL through NSWorkspace instead.
    static func arguments(for target: BrowserTarget, url: URL) -> [String]? {
        guard let bundleID = target.bundleID, !target.isSystemDefault else { return nil }
        switch family(of: bundleID) {
        case .chromium:
            var args: [String] = []
            if let profile = target.profile, !profile.isEmpty, bundleID != "company.thebrowser.Browser" {
                args.append("--profile-directory=\(profile)")
            }
            switch target.windowMode ?? .tab {
            case .tab: args.append(url.absoluteString)
            case .window: args += ["--new-window", url.absoluteString]
            case .app: args.append("--app=\(url.absoluteString)")
            }
            return args
        case .firefox:
            var args: [String] = []
            if let profile = target.profile, !profile.isEmpty { args += ["-P", profile] }
            var finalURL = url.absoluteString
            if let container = target.container, !container.isEmpty {
                finalURL = "ext+container:name=\(PercentEncoding.encode(container))&url=\(PercentEncoding.encode(finalURL))"
            }
            if (target.windowMode ?? .tab) != .tab { args.append("--new-window") }
            args.append(finalURL)
            return args
        case .safari, .other:
            return nil
        }
    }

    /// Opens `url` per `target`. Calls `completion` on the main queue.
    @MainActor
    static func open(_ url: URL, in target: BrowserTarget?, completion: @escaping @MainActor (Error?) -> Void) {
        let finish: @Sendable (Error?) -> Void = { error in DispatchQueue.main.async { completion(error) } }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        guard let target, !target.isSystemDefault, let bundleID = target.bundleID else {
            NSWorkspace.shared.open(url, configuration: config) { _, error in finish(error) }
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            finish(LaunchError.appNotFound(bundleID))
            return
        }
        if let args = arguments(for: target, url: url) {
            // A second instance hands the arguments to the running browser and exits,
            // exactly like `open -na`.
            config.createsNewApplicationInstance = true
            config.arguments = args
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in finish(error) }
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in finish(error) }
        }
    }
}

enum LaunchError: LocalizedError {
    case appNotFound(String)
    case noDestinations
    case wouldLoop(String)
    case noComposeURL(String)
    case badTemplate(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let id): return "App not installed: \(id)"
        case .noDestinations: return "No destinations are set up yet."
        case .wouldLoop(let id): return "\(id) would send the link straight back to Segue."
        case .noComposeURL(let p): return "\(p) has no compose URL. Use a template destination."
        case .badTemplate(let t): return "The template is not a valid URL: \(t)"
        }
    }
}
