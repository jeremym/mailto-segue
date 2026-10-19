import AppKit
import SegueCore

/// Performs a destination for a request. The one place that actually opens
/// things. Every path ends in `completion`, so the app knows when to quit.
@MainActor
final class Launcher {
    struct Plan: Codable, Equatable, Sendable {
        var destinationID: String
        var kind: String
        var url: String?
        var appBundleID: String?
        var arguments: [String]?
        var clipboard: String?
        var note: String?
    }

    let supportDirectory: URL
    /// When set, nothing is opened: the plan is written to this file instead.
    var dryRunFile: URL?

    init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
    }

    func launch(_ destination: Destination, for request: ComposeRequest,
                completion: @escaping @MainActor (Result<Plan, Error>) -> Void) {
        do {
            var plan = Plan(destinationID: destination.id, kind: destination.type.rawValue)
            let guardFile = LoopGuard(directory: supportDirectory)
            switch destination.type {
            case .webmail:
                guard let provider = destination.provider else { throw LaunchError.noComposeURL("?") }
                let built: WebmailURLBuilder.Built
                do {
                    built = try WebmailURLBuilder.build(request, provider: provider, account: destination.account)
                } catch {
                    throw LaunchError.noComposeURL(provider.displayName)
                }
                if let overflow = built.overflowBody {
                    plan.clipboard = overflow
                    plan.note = "Quoted text copied. Paste it in."
                }
                plan.url = built.url.absoluteString
                fill(&plan, browser: destination.browser, url: built.url)
                try perform(plan, openURL: built.url, browser: destination.browser, completion: completion)

            case .template:
                let expanded = Template.expand(destination.template ?? "", with: request)
                guard let url = URL(string: expanded) else { throw LaunchError.badTemplate(expanded) }
                plan.url = url.absoluteString
                fill(&plan, browser: destination.browser, url: url)
                try perform(plan, openURL: url, browser: destination.browser, completion: completion)

            case .browserHandler:
                guard let url = URL(string: request.mailtoString) else { throw LaunchError.badTemplate(request.mailtoString) }
                plan.url = url.absoluteString
                fill(&plan, browser: destination.browser, url: url)
                guardFile.remember(mailto: request.mailtoString, destinationID: destination.id,
                                   targetBundleID: destination.browser?.bundleID)
                try perform(plan, openURL: url, browser: destination.browser, completion: completion)

            case .app:
                let bundleID = destination.bundleID ?? ""
                guard bundleID != Bundle.main.bundleIdentifier else { throw LaunchError.wouldLoop(bundleID) }
                guard let url = URL(string: request.mailtoString) else { throw LaunchError.badTemplate(request.mailtoString) }
                plan.url = url.absoluteString
                plan.appBundleID = bundleID
                guardFile.remember(mailto: request.mailtoString, destinationID: destination.id, targetBundleID: bundleID)
                if dryRun(plan) { completion(.success(plan)); return }
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                    throw LaunchError.appNotFound(bundleID)
                }
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                let finalPlan = plan
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                    DispatchQueue.main.async { completion(error.map { .failure($0) } ?? .success(finalPlan)) }
                }

            case .clipboard:
                let text = ClipboardText.text(for: request, mode: destination.copy ?? .addresses)
                plan.clipboard = text
                plan.note = "Copied."
                if dryRun(plan) { completion(.success(plan)); return }
                copyToPasteboard(text)
                completion(.success(plan))
            }
        } catch {
            completion(.failure(error))
        }
    }

    /// Opens a plain URL in a browser target (used for "Find in Gmail").
    func open(url: URL, browser: BrowserTarget?, destinationID: String,
              completion: @escaping @MainActor (Result<Plan, Error>) -> Void) {
        var plan = Plan(destinationID: destinationID, kind: "url")
        plan.url = url.absoluteString
        fill(&plan, browser: browser, url: url)
        do { try perform(plan, openURL: url, browser: browser, completion: completion) } catch { completion(.failure(error)) }
    }

    // MARK: - Helpers

    private func fill(_ plan: inout Plan, browser: BrowserTarget?, url: URL) {
        plan.appBundleID = browser?.isSystemDefault == false ? browser?.bundleID : nil
        plan.arguments = browser.flatMap { BrowserLauncher.arguments(for: $0, url: url) }
    }

    private func perform(_ plan: Plan, openURL url: URL, browser: BrowserTarget?,
                         completion: @escaping @MainActor (Result<Plan, Error>) -> Void) throws {
        if dryRun(plan) { completion(.success(plan)); return }
        if let text = plan.clipboard { copyToPasteboard(text) }
        BrowserLauncher.open(url, in: browser) { error in
            completion(error.map { .failure($0) } ?? .success(plan))
        }
    }

    private func dryRun(_ plan: Plan) -> Bool {
        guard let file = dryRunFile else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(plan).write(to: file, options: .atomic)
        return true
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
