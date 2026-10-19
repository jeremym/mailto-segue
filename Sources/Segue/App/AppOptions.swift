import Foundation
import SegueCore

/// Command-line flags, used by scripts and tests. Real users never pass any.
struct AppOptions {
    /// `--support-dir <path>`: where config.json lives (default: Application Support/Segue).
    var supportDirectory: URL
    /// `--dry-run <file>`: route, write the plan there, open nothing.
    var dryRunFile: URL?
    /// `--startup-marker <file>`: see StartupMarker.
    var startupMarker: URL?

    static func parse(_ args: [String] = CommandLine.arguments) -> AppOptions {
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let support = value(after: "--support-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? ConfigStore.defaultDirectory()
        return AppOptions(
            supportDirectory: support,
            dryRunFile: value(after: "--dry-run").map { URL(fileURLWithPath: $0) },
            startupMarker: value(after: "--startup-marker").map { URL(fileURLWithPath: $0) }
        )
    }
}
