import SwiftUI

/// A small "?" that opens a two-sentence explanation. Every field that
/// could puzzle a normal person gets one.
struct HelpButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.title3).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Help")
        .accessibilityHint(text)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text).font(.title3).padding(16).frame(width: 340, alignment: .leading)
        }
    }
}

/// A form row: a real label on the left (with optional help), the control on
/// the right. Labels never hide inside the field.
struct FieldRow<Content: View>: View {
    let label: String
    var help: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 6) {
                Text(label).font(.title3)
                if let help { HelpButton(text: help) }
            }
            .frame(width: 210, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

/// A boxed text field with an example as its placeholder.
struct BoxedField: View {
    @Binding var text: String
    var example: String
    var monospaced = false

    var body: some View {
        TextField("", text: $text, prompt: Text(example).foregroundStyle(.tertiary))
            .textFieldStyle(.roundedBorder)
            .font(monospaced ? .system(.title3, design: .monospaced) : .title3)
            .controlSize(.large)
    }
}

enum Help {
    static let buttonName = "What you see on the big button. Anything you like: “Gmail — work”, “Mom's account”."
    static let shortcut = "One key that picks this button while the chooser is open. Numbers and letters work; x closes the chooser."
    static let sendsAs = "The address this destination sends from. Mailto Segue uses it to pick the right account when you reply to a message, and to leave you out of Reply All. Several addresses: separate them with commas."
    static let gmailAccount = "The Google account to open, if several are signed in to this browser profile. Leave it empty for the browser's current account."
    static let accountIndex = "Gmail's account number from the address bar: mail.google.com/mail/u/1/ is number 1. Only needed if the address above doesn't open the right account."
    static let service = "Which webmail gets the draft. Each service has its own compose link; iCloud and HEY don't have one, so they need a custom URL."
    static let browser = "Which browser opens the link. “System default” follows whatever you've set in macOS."
    static let profile = "Browser profiles keep separate sign-ins, bookmarks and history. Pick the one that is signed in to this account."
    static let container = "Firefox Multi-Account Containers keep sign-ins apart inside one profile. Needs the “Open external links in a container” extension."
    static let openIn = "“Its own window” shows just the compose form with no tabs or toolbar, like a small mail app."
    static let mailApp = "A desktop mail app installed on this Mac. The link is handed to it exactly as it arrived."
    static let copy = "Nothing opens. The addresses (or the whole link, or everything) go to the clipboard and a short “Copied.” message appears."
    static let template = "A URL with placeholders: {to} {cc} {bcc} {subject} {body} {mailto} {domain}. Each is filled in and encoded for you."
    static let browserHandler = "Hands the mailto: link to the browser itself, so whatever it has registered as its email handler (Gmail, Fastmail…) takes over. No URL knowledge needed."
    static let pinned = "Pinned buttons always come first in the chooser."
    static let picture = "Any PNG, JPEG or HEIC. It replaces the service logo on the button."
    static let colour = "The button's colour, so accounts are easy to tell apart at a glance."
    static let ruleField = "What to look at. “Recipient's domain” is the part after the @ of the address you're writing to."
    static let ruleThen = "Where a matching link goes, without showing the chooser. Hold ⌥ while clicking a link to see the chooser anyway."
    static let ruleMatch = "“All” means every condition must be true. “Any” means one is enough."
    static let fallback = "What happens when no rule matches: show the chooser, or always use one destination."
}
