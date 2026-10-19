import Foundation

public enum WebmailProvider: String, Codable, CaseIterable, Sendable {
    case gmail, outlook, office365, yahoo, proton, fastmail, zoho, icloud, hey

    public var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .outlook: return "Outlook.com"
        case .office365: return "Microsoft 365"
        case .yahoo: return "Yahoo Mail"
        case .proton: return "Proton Mail"
        case .fastmail: return "Fastmail"
        case .zoho: return "Zoho Mail"
        case .icloud: return "iCloud Mail"
        case .hey: return "HEY"
        }
    }

    /// Whether Segue knows a compose URL. The others need a `template`.
    public var supportsDirectCompose: Bool {
        switch self {
        case .icloud, .hey: return false
        default: return true
        }
    }

    /// Whether the account can be chosen in the URL (Gmail `u/N` / `authuser`,
    /// Proton `u/N`). Others rely on one session per browser profile.
    public var supportsAccountSelection: Bool {
        switch self {
        case .gmail, .proton: return true
        default: return false
        }
    }

    /// Brand color used for the tile when there is no custom image.
    public var brandColorHex: String {
        switch self {
        case .gmail: return "#EA4335"
        case .outlook, .office365: return "#0078D4"
        case .yahoo: return "#6001D2"
        case .proton: return "#6D4AFF"
        case .fastmail: return "#0067B9"
        case .zoho: return "#E42527"
        case .icloud: return "#3693F3"
        case .hey: return "#5522FA"
        }
    }
}
