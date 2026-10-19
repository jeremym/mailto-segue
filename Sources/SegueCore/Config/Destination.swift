import Foundation

public struct Destination: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case webmail, app, clipboard, template, browserHandler
    }

    public var id: String
    public var name: String
    /// A single character the chooser binds to this destination (1–9, a–z).
    public var key: String?
    public var type: Kind

    // webmail
    public var provider: WebmailProvider?
    public var account: WebmailAccount?
    /// webmail, template and browserHandler: which browser (and profile) opens the URL.
    public var browser: BrowserTarget?

    // app
    public var bundleID: String?

    // clipboard
    public var copy: CopyMode?

    // template
    public var template: String?

    // common
    /// Addresses this destination sends as. Enables "reply from the account
    /// that received it" and lets Reply All drop my own addresses.
    public var sendsAs: [String]?
    /// Hex color (`#1A73E8`) for the tile.
    public var color: String?
    /// Path relative to the Segue support folder (`images/work.png`).
    public var image: String?
    public var pinned: Bool?
    public var enabled: Bool?

    public init(id: String, name: String, type: Kind, key: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.key = key
    }

    public enum CopyMode: String, Codable, CaseIterable, Sendable {
        /// Just the recipient addresses, comma-separated.
        case addresses
        /// The strictly encoded mailto: link.
        case mailto
        /// To/Cc/Bcc/Subject lines followed by the body.
        case all
    }

    /// The address shown under the tile, if any.
    public var primarySendsAs: String? { sendsAs?.first }

    public func validate() -> [String] {
        var issues: [String] = []
        if name.isEmpty { issues.append("empty name") }
        if let key, key.count != 1 { issues.append("key must be a single character") }
        switch type {
        case .webmail:
            if provider == nil { issues.append("webmail needs a provider") }
            if let provider, !provider.supportsDirectCompose {
                issues.append("\(provider.rawValue) has no compose URL; use a template destination")
            }
        case .app:
            if (bundleID ?? "").isEmpty { issues.append("app needs a bundleID") }
        case .clipboard:
            break
        case .template:
            if (template ?? "").isEmpty { issues.append("template needs a template URL") }
        case .browserHandler:
            if browser?.bundleID == nil { issues.append("browserHandler needs a browser") }
        }
        return issues
    }
}

public struct WebmailAccount: Codable, Equatable, Sendable {
    /// Gmail/Proton `u/N` slot.
    public var index: Int?
    /// Preferred: the account's address (Gmail `authuser=`).
    public var email: String?
    public init(index: Int? = nil, email: String? = nil) {
        self.index = index
        self.email = email
    }
}

public struct BrowserTarget: Codable, Equatable, Sendable {
    public enum WindowMode: String, Codable, CaseIterable, Sendable {
        case tab, window
        /// Chromium `--app=<url>`: a chromeless window with only the compose form.
        case app
    }

    /// Browser bundle ID. `nil` or "default" means the system default browser.
    public var bundleID: String?
    /// Chromium `--profile-directory` value or Firefox profile name.
    public var profile: String?
    /// What the user sees ("Your Chrome").
    public var profileName: String?
    /// Firefox Multi-Account Container (needs the "Open external links in a container" extension).
    public var container: String?
    public var windowMode: WindowMode?

    public init(bundleID: String? = nil, profile: String? = nil, profileName: String? = nil,
                container: String? = nil, windowMode: WindowMode? = nil) {
        self.bundleID = bundleID
        self.profile = profile
        self.profileName = profileName
        self.container = container
        self.windowMode = windowMode
    }

    public var isSystemDefault: Bool { bundleID == nil || bundleID == "default" }
}
