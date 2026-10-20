import AppKit
import Observation
import SegueCore

/// The main window's state: the config (saved on every change, debounced),
/// history, and the hooks back into the app for actions that open things.
@MainActor
@Observable
final class AppModel {
    var config: Config {
        didSet { scheduleSave() }
    }
    let store: ConfigStore
    let supportDirectory: URL
    let history: HistoryStore
    var historyItems: [HistoryItem] = []
    var configError: String?
    var statusMessage: String?
    var isMailtoDefault = false
    var isEmlDefault = false

    // Hooks set by the AppDelegate.
    var onSendAgain: ((HistoryItem, Destination?) -> Void)?
    var onOpenEml: ((URL) -> Void)?
    var onTestDestination: ((Destination) -> Void)?
    var onStayRunningChanged: ((Bool) -> Void)?
    var onTryIt: (() -> Void)?
    /// Asks the window to switch sections (set by MainView).
    var requestSection: ((MainSection) -> Void)?

    @ObservationIgnored private var saveTimer: Timer?
    @ObservationIgnored private(set) var installedBrowsers: [Discovery.InstalledApp] = []
    @ObservationIgnored private(set) var installedMailApps: [Discovery.InstalledApp] = []

    init(store: ConfigStore, config: Config, supportDirectory: URL) {
        self.store = store
        self.config = config
        self.supportDirectory = supportDirectory
        self.history = HistoryStore(supportDirectory: supportDirectory)
        self.configError = store.lastError
        refresh()
    }

    func refresh() {
        historyItems = history.items()
        isMailtoDefault = DefaultHandler.isSegueDefaultForMailto()
        isEmlDefault = DefaultHandler.isSegueDefaultForEml()
        installedBrowsers = Discovery.installedBrowsers()
        installedMailApps = Discovery.installedMailApps()
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.saveNow() }
        }
    }

    func saveNow() {
        saveTimer?.invalidate()
        do {
            try store.save(config)
            configError = store.lastError
        } catch {
            configError = error.localizedDescription
        }
    }

    // MARK: - Destinations

    func addDestination(type: Destination.Kind) -> Destination {
        var d = Destination(id: uniqueID(base: type.rawValue), name: defaultName(for: type), type: type)
        switch type {
        case .webmail:
            d.provider = .gmail
            d.browser = BrowserTarget(bundleID: nil)
        case .app:
            d.bundleID = installedMailApps.first?.bundleID ?? "com.apple.mail"
        case .clipboard:
            d.copy = .addresses
        case .template:
            d.template = "https://mail.google.com/mail/?extsrc=mailto&url={mailto}"
            d.browser = BrowserTarget(bundleID: nil)
        case .browserHandler:
            d.browser = BrowserTarget(bundleID: installedBrowsers.first?.bundleID)
        }
        d.key = nextFreeKey()
        config.destinations.append(d)
        return d
    }

    func removeDestination(id: String) {
        config.destinations.removeAll { $0.id == id }
        config.rules.removeAll { $0.then == id }
        if case .destination(let f) = config.fallback, f == id { config.fallback = .chooser }
        TileImageCache.clear(supportDirectory: supportDirectory)
    }

    func uniqueID(base: String) -> String {
        let slug = Discovery.slug(base).isEmpty ? "destination" : Discovery.slug(base)
        var id = slug
        var n = 2
        while config.destinations.contains(where: { $0.id == id }) { id = "\(slug)-\(n)"; n += 1 }
        return id
    }

    private func defaultName(for type: Destination.Kind) -> String {
        switch type {
        case .webmail: return "Gmail"
        case .app: return installedMailApps.first?.name ?? "Mail"
        case .clipboard: return "Copy address"
        case .template: return "Custom URL"
        case .browserHandler: return "Browser's own handler"
        }
    }

    func nextFreeKey() -> String? {
        let used = Set(config.destinations.compactMap { $0.key?.lowercased() })
        return Array("123456789abdefghijklmnopqrstuvwyz").map(String.init).first { !used.contains($0) }
    }

    func profiles(forBrowser bundleID: String?) -> [(directory: String, name: String)] {
        guard let bundleID else { return [] }
        switch BrowserLauncher.family(of: bundleID) {
        case .chromium:
            return ChromiumProfiles.profiles(forBundleID: bundleID).map { p in
                (p.directory, p.userName.map { "\(p.name) · \($0)" } ?? p.name)
            }
        case .firefox: return FirefoxProfiles.profiles(forBundleID: bundleID).map { ($0.name, $0.name) }
        default: return []
        }
    }

    /// Google accounts signed into the chosen browser profile (or all of its
    /// profiles when none is chosen), for the Gmail account menu.
    func signedInAccounts(browserBundleID: String?, profile: String?) -> [String] {
        guard let id = browserBundleID, BrowserLauncher.family(of: id) == .chromium else { return [] }
        let profiles = ChromiumProfiles.profiles(forBundleID: id)
        let chosen = (profile ?? "").isEmpty ? profiles : profiles.filter { $0.directory == profile }
        var seen = Set<String>()
        return chosen.compactMap { $0.userName }.filter { seen.insert($0).inserted }
    }

    /// "Gmail — me@work.com", "Mail", "Copy address": the name a destination
    /// gets until the user types their own.
    func autoName(for d: Destination) -> String {
        switch d.type {
        case .webmail:
            let service = d.provider?.displayName ?? "Webmail"
            if let e = d.account?.email, !e.isEmpty { return "\(service) — \(e)" }
            if let i = d.account?.index { return "\(service) — account \(i + 1)" }
            return service
        case .app:
            return installedMailApps.first { $0.bundleID == d.bundleID }?.name ?? (d.bundleID ?? "Mail app")
        case .clipboard: return "Copy address"
        case .template: return "Custom URL"
        case .browserHandler:
            if let id = d.browser?.bundleID, let app = installedBrowsers.first(where: { $0.bundleID == id }) { return "\(app.name)'s own handler" }
            return "Browser's own handler"
        }
    }

    /// Running apps with a bundle ID, for the "App the link came from" picker.
    func runningApps() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    /// Copies a picture into `images/` and returns the relative path.
    func importImage(from url: URL) -> String? {
        let dir = supportDirectory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return nil }
        TileImageCache.clear(supportDirectory: supportDirectory)
        return "images/" + url.lastPathComponent
    }

    // MARK: - Rules

    func addRule() {
        let then = config.destinations.first?.id
        config.rules.append(Rule(name: "New rule", when: [Condition(field: "to.domain", op: .domainIs, value: "example.com")], then: then))
    }

    func makeRule(from item: HistoryItem) {
        guard let d = config.destination(id: item.destinationID) else { return }
        var when: [Condition] = []
        var names: [String] = []
        if let s = item.source, !s.guessed { when.append(Condition(field: "sourceApp", op: .is, value: s.bundleID)); names.append(s.name) }
        if let first = item.to.first, let addr = EmailAddress(parsing: first), !addr.domain.isEmpty {
            when.append(Condition(field: "to.domain", op: .domainIs, value: addr.domain)); names.append(addr.domain)
        }
        guard !when.isEmpty else { return }
        config.rules.append(Rule(name: "\(names.joined(separator: " + ")) → \(d.name)", match: .all, when: when, then: d.id))
        statusMessage = "Rule added."
    }

    // MARK: - History

    func clearHistory() {
        history.clear()
        historyItems = []
    }

    func historyUsage() -> String {
        let u = history.usage()
        return "\(u.items) items · \(ByteCountFormatter.string(fromByteCount: Int64(u.bytes), countStyle: .file))"
    }

    // MARK: - Defaults

    func makeDefaultForMailto() {
        DefaultHandler.setMailtoHandler(to: Bundle.main.bundleURL) { [weak self] ok in
            self?.isMailtoDefault = ok
            self?.statusMessage = ok ? "Mailto Segue is now the default email app." : "Not changed. (Did you click Keep?)"
        }
    }

    func restoreMailForMailto() {
        DefaultHandler.setMailtoHandler(to: DefaultHandler.mailAppURL) { [weak self] ok in
            self?.isMailtoDefault = !ok && DefaultHandler.isSegueDefaultForMailto()
            self?.statusMessage = ok ? "Mail is the default email app again." : "Not changed."
        }
    }

    func makeDefaultForEml() {
        DefaultHandler.setEmlHandler(to: Bundle.main.bundleURL) { [weak self] ok in
            self?.isEmlDefault = ok
            self?.statusMessage = ok ? "Mailto Segue now opens .eml files." : "Not changed."
        }
    }

    func restoreMailForEml() {
        DefaultHandler.setEmlHandler(to: DefaultHandler.mailAppURL) { [weak self] ok in
            self?.isEmlDefault = !ok && DefaultHandler.isSegueDefaultForEml()
            self?.statusMessage = ok ? "Mail opens .eml files again." : "Not changed."
        }
    }

    func doctor() -> [Doctor.Line] {
        Doctor.run(config: config, store: store, supportDirectory: supportDirectory)
    }
}

// Editing helpers for optional fields.
extension Destination {
    var sendsAsText: String {
        get { (sendsAs ?? []).joined(separator: ", ") }
        set { let list = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }; sendsAs = list.isEmpty ? nil : list }
    }
    var keyText: String {
        get { key ?? "" }
        set { key = newValue.isEmpty ? nil : String(newValue.suffix(1)).lowercased() }
    }
    var bundleIDText: String { get { bundleID ?? "" } set { bundleID = newValue.isEmpty ? nil : newValue } }
    var templateText: String { get { template ?? "" } set { template = newValue.isEmpty ? nil : newValue } }
    var colorText: String { get { color ?? "" } set { color = newValue.isEmpty ? nil : newValue } }
    var imageText: String { get { image ?? "" } set { image = newValue.isEmpty ? nil : newValue } }
    var isPinned: Bool { get { pinned ?? false } set { pinned = newValue ? true : nil } }
    var isEnabled: Bool { get { enabled ?? true } set { enabled = newValue ? nil : false } }
    var providerValue: WebmailProvider { get { provider ?? .gmail } set { provider = newValue } }
    var copyValue: CopyMode { get { copy ?? .addresses } set { copy = newValue } }
    var accountEmail: String {
        get { account?.email ?? "" }
        set { var a = account ?? WebmailAccount(); a.email = newValue.isEmpty ? nil : newValue; account = (a.email == nil && a.index == nil) ? nil : a }
    }
    var accountIndexText: String {
        get { account?.index.map(String.init) ?? "" }
        set { var a = account ?? WebmailAccount(); a.index = Int(newValue); account = (a.email == nil && a.index == nil) ? nil : a }
    }
    var browserBundleID: String {
        get { browser?.bundleID ?? "default" }
        set { var b = browser ?? BrowserTarget(); b.bundleID = newValue == "default" ? nil : newValue; if b.bundleID != browser?.bundleID { b.profile = nil; b.profileName = nil }; browser = b }
    }
    var browserProfile: String {
        get { browser?.profile ?? "" }
        set { var b = browser ?? BrowserTarget(); b.profile = newValue.isEmpty ? nil : newValue; browser = b }
    }
    var browserProfileName: String {
        get { browser?.profileName ?? "" }
        set { var b = browser ?? BrowserTarget(); b.profileName = newValue.isEmpty ? nil : newValue; browser = b }
    }
    var browserContainer: String {
        get { browser?.container ?? "" }
        set { var b = browser ?? BrowserTarget(); b.container = newValue.isEmpty ? nil : newValue; browser = b }
    }
    var browserWindowMode: BrowserTarget.WindowMode {
        get { browser?.windowMode ?? .tab }
        set { var b = browser ?? BrowserTarget(); b.windowMode = newValue == .tab ? nil : newValue; browser = b }
    }
}

extension Rule {
    var thenText: String { get { then ?? "" } set { then = newValue.isEmpty ? nil : newValue } }
}
