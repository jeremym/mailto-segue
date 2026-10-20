import WebKit

/// A WKWebView that can only show what it is given: JavaScript off, every
/// network load blocked by a content rule list, no plugins. Tracking pixels
/// never fire. WebKit is linked lazily through this file only, so the chooser
/// path never pays for it.
@MainActor
final class SafeHTMLView: WKWebView {
    private static let blockEverything = """
    [{ "trigger": { "url-filter": ".*" }, "action": { "type": "block" } }]
    """

    static func make() -> SafeHTMLView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.isFraudulentWebsiteWarningEnabled = false
        config.websiteDataStore = .nonPersistent()
        let view = SafeHTMLView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.installRules()
        return view
    }

    private var rulesInstalled = false
    private var pending: String?

    private func installRules() {
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "segue-block-all",
                                                                encodedContentRuleList: SafeHTMLView.blockEverything) { [weak self] list, _ in
            Task { @MainActor in
                guard let self else { return }
                if let list { self.configuration.userContentController.add(list) }
                self.rulesInstalled = true
                if let html = self.pending { self.pending = nil; self.show(html: html) }
            }
        }
    }

    /// Shows HTML once the block list is in place. `cid:` images are not
    /// resolved (they would need inline data URLs; M12 can add that).
    func show(html: String) {
        guard rulesInstalled else { pending = html; return }
        let wrapped = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>
          :root { color-scheme: light dark; }
          body { font: -apple-system-body; font-size: 17px; line-height: 1.45; margin: 16px; color: CanvasText; background: transparent; word-wrap: break-word; }
          img { max-width: 100%; height: auto; }
          blockquote { border-left: 3px solid gray; margin-left: 0; padding-left: 12px; color: GrayText; }
          a { color: LinkText; }
        </style></head><body>\(html)</body></html>
        """
        loadHTMLString(wrapped, baseURL: nil)
    }
}
