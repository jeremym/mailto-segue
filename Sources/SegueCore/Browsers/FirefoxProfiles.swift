import Foundation

/// Reads Firefox's `profiles.ini`.
public struct FirefoxProfile: Equatable, Sendable, Codable {
    /// The `-P` value.
    public var name: String
    public var path: String
    public var isDefault: Bool

    public init(name: String, path: String, isDefault: Bool = false) {
        self.name = name
        self.path = path
        self.isDefault = isDefault
    }
}

public enum FirefoxProfiles {
    public static func supportFolder(forBundleID bundleID: String) -> String? {
        switch bundleID {
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly": return "Firefox"
        case "app.zen-browser.zen": return "zen"
        default: return nil
        }
    }

    public static func profiles(forBundleID bundleID: String, applicationSupport: URL? = nil) -> [FirefoxProfile] {
        guard let folder = supportFolder(forBundleID: bundleID) else { return [] }
        let base = applicationSupport
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent(folder).appendingPathComponent("profiles.ini")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(profilesIni: text)
    }

    /// `[ProfileN]` sections with `Name=`, `Path=`, `Default=1`. An `[InstallXXX]`
    /// section's `Default=<path>` marks the profile the current install uses,
    /// which wins over the legacy `Default=1` flag.
    public static func parse(profilesIni text: String) -> [FirefoxProfile] {
        var sections: [(String, [String: String])] = []
        var current: (String, [String: String])? = nil
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                if let c = current { sections.append(c) }
                current = (String(line.dropFirst().dropLast()), [:])
            } else if let eq = line.firstIndex(of: "="), current != nil {
                current!.1[String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        if let c = current { sections.append(c) }

        let installDefault = sections.first { $0.0.hasPrefix("Install") }?.1["Default"]
        var out: [FirefoxProfile] = []
        for (name, kv) in sections where name.hasPrefix("Profile") {
            guard let profileName = kv["Name"], let path = kv["Path"] else { continue }
            let isDefault = installDefault.map { $0 == path } ?? (kv["Default"] == "1")
            out.append(FirefoxProfile(name: profileName, path: path, isDefault: isDefault))
        }
        return out.sorted { a, b in a.isDefault && !b.isDefault }
    }
}
