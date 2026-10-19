import AppKit
import SegueCore

/// `segue doctor` and Settings → "Check setup": what's registered, what's
/// installed, what each destination would do.
@MainActor
enum Doctor {
    struct Line { var ok: Bool; var text: String }

    static func run(config: Config, store: ConfigStore, supportDirectory: URL) -> [Line] {
        var lines: [Line] = []
        let bundle = Bundle.main.bundleURL
        lines.append(Line(ok: true, text: "Segue \(SegueVersion.string) at \(bundle.path)"))
        if let err = store.lastError {
            lines.append(Line(ok: false, text: "config.json: \(err)"))
        } else {
            lines.append(Line(ok: true, text: "config.json: \(config.destinations.count) destinations, \(config.rules.count) rules" + (store.exists ? "" : " (not written yet)")))
        }
        let mailto = DefaultHandler.currentMailtoHandler()
        lines.append(Line(ok: DefaultHandler.isSegueDefaultForMailto(),
                          text: "mailto: default is " + (mailto.map { $0.deletingPathExtension().lastPathComponent } ?? "nothing")))
        let eml = DefaultHandler.currentEmlHandler()
        lines.append(Line(ok: true, text: ".eml default is " + (eml.map { $0.deletingPathExtension().lastPathComponent } ?? "nothing")))

        let sample = ComposeRequest(to: [EmailAddress(address: "test@example.com")], subject: "Segue doctor", body: "Hello")
        for d in config.destinations {
            let problems = d.validate()
            if !problems.isEmpty {
                lines.append(Line(ok: false, text: "\(d.name): " + problems.joined(separator: "; ")))
                continue
            }
            switch d.type {
            case .app:
                let present = NSWorkspace.shared.urlForApplication(withBundleIdentifier: d.bundleID ?? "") != nil
                lines.append(Line(ok: present, text: "\(d.name): app \(d.bundleID ?? "?")" + (present ? "" : " is not installed")))
            case .webmail:
                var ok = true
                var text = "\(d.name): \(d.provider?.displayName ?? "?")"
                if let p = d.provider {
                    do { _ = try WebmailURLBuilder.build(sample, provider: p, account: d.account) } catch { ok = false; text += " (no compose URL)" }
                }
                text += browserCheck(d.browser, ok: &ok)
                lines.append(Line(ok: ok, text: text))
            case .template:
                let expanded = Template.expand(d.template ?? "", with: sample)
                var ok = URL(string: expanded) != nil
                var text = "\(d.name): template" + (ok ? "" : " does not make a valid URL")
                text += browserCheck(d.browser, ok: &ok)
                lines.append(Line(ok: ok, text: text))
            case .browserHandler:
                var ok = true
                var text = "\(d.name): browser handler"
                text += browserCheck(d.browser, ok: &ok)
                lines.append(Line(ok: ok, text: text))
            case .clipboard:
                lines.append(Line(ok: true, text: "\(d.name): clipboard (\(d.copy?.rawValue ?? "addresses"))"))
            }
        }
        let learned = LearnedChoices(directory: supportDirectory).load()
        lines.append(Line(ok: true, text: "learned defaults: \(learned.byApp.count) apps, \(learned.byDomain.count) domains"))
        lines.append(Line(ok: true, text: "log: \(supportDirectory.appendingPathComponent("segue.log").path)"))
        return lines
    }

    private static func browserCheck(_ target: BrowserTarget?, ok: inout Bool) -> String {
        guard let target, !target.isSystemDefault, let id = target.bundleID else { return " in the default browser" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            ok = false
            return " in \(id), which is not installed"
        }
        var text = " in \(url.deletingPathExtension().lastPathComponent)"
        if let profile = target.profile, !profile.isEmpty {
            switch BrowserLauncher.family(of: id) {
            case .chromium:
                let known = ChromiumProfiles.profiles(forBundleID: id)
                if known.isEmpty { text += ", profile \(profile) (could not read the profile list)" }
                else if known.contains(where: { $0.directory == profile }) { text += ", profile \(target.profileName ?? profile)" }
                else { ok = false; text += ", profile \(profile) which does not exist (have: \(known.map(\.directory).joined(separator: ", ")))" }
            case .firefox:
                let known = FirefoxProfiles.profiles(forBundleID: id)
                if known.contains(where: { $0.name == profile }) { text += ", profile \(profile)" }
                else { ok = false; text += ", profile \(profile) which does not exist (have: \(known.map(\.name).joined(separator: ", ")))" }
            default:
                text += " (profiles are not supported for this browser)"
            }
        }
        if let c = target.container, !c.isEmpty { text += ", container \(c) (needs the “Open external links in a container” extension)" }
        if let m = target.windowMode, m != .tab { text += ", \(m.rawValue) window" }
        return text
    }
}
