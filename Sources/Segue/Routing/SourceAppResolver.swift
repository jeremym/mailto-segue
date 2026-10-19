import AppKit
import SegueCore

enum SourceAppResolver {
    /// Who sent the Apple Event. LaunchServices forwards cold-launch events
    /// itself, so when the sender isn't a real app we fall back to the
    /// frontmost app and say so.
    @MainActor
    static func resolve(event: NSAppleEventDescriptor?) -> SourceApp? {
        if let pid = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
           pid > 0, let app = NSRunningApplication(processIdentifier: pid),
           let bundleID = app.bundleIdentifier, !isSystemForwarder(bundleID) {
            return SourceApp(bundleID: bundleID, name: app.localizedName ?? bundleID, pid: pid, guessed: false)
        }
        return frontmost()
    }

    @MainActor
    static func frontmost() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return nil }
        return SourceApp(bundleID: bundleID, name: app.localizedName ?? bundleID, pid: app.processIdentifier, guessed: true)
    }

    private static func isSystemForwarder(_ bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier
            || bundleID.hasPrefix("com.apple.coreservices")
            || bundleID == "com.apple.launchservicesd"
            || bundleID == "com.apple.ServicesUIAgent"
    }
}
