import Foundation

/// What the `clipboard` destination puts on the pasteboard.
public enum ClipboardText {
    public static func text(for request: ComposeRequest, mode: Destination.CopyMode) -> String {
        switch mode {
        case .addresses:
            return request.allRecipients.map(\.address).joined(separator: ", ")
        case .mailto:
            return request.mailtoString
        case .all:
            var lines: [String] = []
            if !request.to.isEmpty { lines.append("To: " + request.to.map(\.description).joined(separator: ", ")) }
            if !request.cc.isEmpty { lines.append("Cc: " + request.cc.map(\.description).joined(separator: ", ")) }
            if !request.bcc.isEmpty { lines.append("Bcc: " + request.bcc.map(\.description).joined(separator: ", ")) }
            if let s = request.subject, !s.isEmpty { lines.append("Subject: " + s) }
            if let b = request.body, !b.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines.append(b)
            }
            return lines.joined(separator: "\n")
        }
    }
}
