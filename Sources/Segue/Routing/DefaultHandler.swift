import AppKit
import CoreServices
import UniformTypeIdentifiers

/// Which app owns `mailto:` and `.eml`, and how to change it. Since macOS
/// 26.4 every change shows a system "Use / Keep" prompt, and "Keep" silently
/// does nothing, so callers must re-check afterwards.
enum DefaultHandler {
    static let mailAppURL = URL(fileURLWithPath: "/System/Applications/Mail.app")

    @MainActor
    static func currentMailtoHandler() -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "mailto:")!)
    }

    @MainActor
    static func isSegueDefaultForMailto() -> Bool {
        guard let url = currentMailtoHandler() else { return false }
        return Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    @MainActor
    static func currentEmlHandler() -> URL? {
        guard let type = UTType("com.apple.mail.email") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    @MainActor
    static func isSegueDefaultForEml() -> Bool {
        guard let url = currentEmlHandler() else { return false }
        return Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Makes `appURL` the mailto handler. The completion runs on the main
    /// queue with the *verified* result, because the user may have chosen Keep.
    @MainActor
    static func setMailtoHandler(to appURL: URL, completion: @escaping @MainActor (Bool) -> Void) {
        registerSelf()
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "mailto") { _ in
            DispatchQueue.main.async {
                let now = currentMailtoHandler()
                completion(now?.standardizedFileURL == appURL.standardizedFileURL)
            }
        }
    }

    @MainActor
    static func setEmlHandler(to appURL: URL, completion: @escaping @MainActor (Bool) -> Void) {
        guard let type = UTType("com.apple.mail.email") else { completion(false); return }
        registerSelf()
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { _ in
            DispatchQueue.main.async {
                completion(currentEmlHandler()?.standardizedFileURL == appURL.standardizedFileURL)
            }
        }
    }

    /// Tells LaunchServices about this bundle. Needed after `brew upgrade`
    /// moves the app, and harmless otherwise. Cheap; call it off the hot path.
    static func registerSelf() {
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    }
}
