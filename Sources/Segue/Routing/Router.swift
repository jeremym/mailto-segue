import AppKit
import SegueCore

/// Decides where a request goes. M3: the fallback destination, or Mail.app
/// when nothing is configured. M4 adds the chooser, M6 the rules.
@MainActor
final class Router {
    enum Decision: Equatable {
        case launch(Destination, reason: String)
        case chooser(reason: String)
    }

    let config: Config
    let supportDirectory: URL

    init(config: Config, supportDirectory: URL) {
        self.config = config
        self.supportDirectory = supportDirectory
    }

    func decide(_ context: RouteContext) -> Decision {
        let active = config.activeDestinations
        if active.isEmpty {
            return .launch(Router.mailAppFallback, reason: "No destinations are set up, so Mail.app gets it.")
        }
        if let bounce = LoopGuard(directory: supportDirectory)
            .bounce(for: context.request.mailtoString, sourceBundleID: context.source?.bundleID) {
            return .chooser(reason: "\(bounce.targetBundleID ?? bounce.destinationID) sent the link back.")
        }
        if context.forceChooser {
            return .chooser(reason: "Modifier held.")
        }
        switch config.fallback {
        case .destination(let id):
            if let d = config.destination(id: id) {
                return .launch(d, reason: "Fallback destination.")
            }
            return .chooser(reason: "Fallback destination '\(id)' is missing.")
        case .chooser:
            if active.count == 1 {
                return .launch(active[0], reason: "The only destination.")
            }
            return .chooser(reason: "No rule matched.")
        }
    }

    /// Where links go when the config is empty: the system Mail app.
    static let mailAppFallback: Destination = {
        var d = Destination(id: "builtin-mail", name: "Mail", type: .app)
        d.bundleID = "com.apple.mail"
        return d
    }()
}
