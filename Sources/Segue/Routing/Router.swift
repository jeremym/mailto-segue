import AppKit
import SegueCore

/// Decides where a request goes. M3: the fallback destination, or Mail.app
/// when nothing is configured. M4 adds the chooser, M6 the rules.
@MainActor
final class Router {
    enum Decision: Equatable {
        case launch(Destination, explanation: Explanation)
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
            return .launch(Router.mailAppFallback, explanation: Explanation(text: "No destinations are set up, so Mail.app gets it"))
        }
        if let bounce = LoopGuard(directory: supportDirectory)
            .bounce(for: context.request.mailtoString, sourceBundleID: context.source?.bundleID) {
            return .chooser(reason: "\(bounce.targetBundleID ?? bounce.destinationID) sent the link back.")
        }
        if context.forceChooser {
            return .chooser(reason: "Modifier held.")
        }
        if config.general.rulesPaused {
            return .chooser(reason: "Rules are paused.")
        }
        if let match = RuleEngine.evaluate(context, config: config), let d = config.destination(id: match.destinationID) {
            return .launch(d, explanation: match.explanation)
        }
        switch config.fallback {
        case .destination(let id):
            if let d = config.destination(id: id) {
                return .launch(d, explanation: .fallback)
            }
            return .chooser(reason: "Fallback destination '\(id)' is missing.")
        case .chooser:
            if active.count == 1 {
                return .launch(active[0], explanation: .onlyDestination)
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
