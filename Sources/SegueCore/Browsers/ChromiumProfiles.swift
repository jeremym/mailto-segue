import Foundation

/// Reads a Chromium-family browser's `Local State` file to list its profiles
/// and which Google account each one is signed into.
public struct ChromiumProfile: Equatable, Sendable, Codable {
    /// The `--profile-directory` value, e.g. `Default` or `Profile 1`.
    public var directory: String
    /// What the browser shows, e.g. "Your Chrome" or "Work".
    public var name: String
    /// The signed-in Google account, if any.
    public var userName: String?

    public init(directory: String, name: String, userName: String? = nil) {
        self.directory = directory
        self.name = name
        self.userName = userName
    }
}

public enum ChromiumProfiles {
    /// Support folder (under `~/Library/Application Support`) per browser.
    public static func supportFolder(forBundleID bundleID: String) -> String? {
        switch bundleID {
        case "com.google.Chrome": return "Google/Chrome"
        case "com.google.Chrome.beta": return "Google/Chrome Beta"
        case "com.google.Chrome.canary": return "Google/Chrome Canary"
        case "com.brave.Browser": return "BraveSoftware/Brave-Browser"
        case "com.brave.Browser.beta": return "BraveSoftware/Brave-Browser-Beta"
        case "com.brave.Browser.nightly": return "BraveSoftware/Brave-Browser-Nightly"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "com.microsoft.edgemac.Beta": return "Microsoft Edge Beta"
        case "com.vivaldi.Vivaldi": return "Vivaldi"
        case "org.chromium.Chromium": return "Chromium"
        case "com.operasoftware.Opera": return "com.operasoftware.Opera"
        default: return nil
        }
    }

    public static func localStateURL(forBundleID bundleID: String,
                                     applicationSupport: URL? = nil) -> URL? {
        guard let folder = supportFolder(forBundleID: bundleID) else { return nil }
        let base = applicationSupport
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(folder).appendingPathComponent("Local State")
    }

    /// Profiles for an installed browser, or `[]` if it has no Local State.
    public static func profiles(forBundleID bundleID: String, applicationSupport: URL? = nil) -> [ChromiumProfile] {
        guard let url = localStateURL(forBundleID: bundleID, applicationSupport: applicationSupport),
              let data = try? Data(contentsOf: url) else { return [] }
        return parse(localState: data)
    }

    /// `profile.info_cache` maps a directory to `{ name, user_name, … }`.
    /// Sorted so `Default` comes first, then `Profile N` by number.
    public static func parse(localState data: Data) -> [ChromiumProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        var out: [ChromiumProfile] = []
        for (dir, value) in cache {
            guard let info = value as? [String: Any] else { continue }
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? dir
            let user = (info["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            out.append(ChromiumProfile(directory: dir, name: name, userName: user))
        }
        return out.sorted { a, b in
            if a.directory == "Default" { return true }
            if b.directory == "Default" { return false }
            let na = Int(a.directory.replacingOccurrences(of: "Profile ", with: "")) ?? Int.max
            let nb = Int(b.directory.replacingOccurrences(of: "Profile ", with: "")) ?? Int.max
            return na == nb ? a.directory < b.directory : na < nb
        }
    }
}
