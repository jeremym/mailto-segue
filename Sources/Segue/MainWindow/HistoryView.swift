import SwiftUI
import SegueCore

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var selectedID: String?

    private var filtered: [HistoryItem] {
        guard !query.isEmpty else { return model.historyItems }
        let q = query.lowercased()
        return model.historyItems.filter {
            $0.subject.lowercased().contains(q) || $0.to.joined().lowercased().contains(q)
                || ($0.source?.name.lowercased().contains(q) ?? false) || $0.destinationName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !model.isMailtoDefault {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Mailto Segue isn't your email app right now, so links go elsewhere.").font(.title3)
                    Spacer()
                    Button("Fix") { model.makeDefaultForMailto() }.controlSize(.large)
                }
                .padding(12)
                .background(.orange.opacity(0.12))
            }
            historySplit.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var historySplit: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Search address, subject or app", text: $query)
                    .textFieldStyle(.roundedBorder).font(.title3).padding(10)
                if model.historyItems.isEmpty {
                    ContentUnavailableView("Nothing routed yet", systemImage: "clock",
                                           description: Text("Every mailto: link and .eml reply Mailto Segue hands off shows up here."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered, selection: $selectedID) { item in
                        HStack(spacing: 10) {
                            Image(nsImage: sourceIcon(item)).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.primaryRecipient.isEmpty ? "(no recipient)" : item.primaryRecipient).font(.headline).lineLimit(1)
                                Text(item.subject.isEmpty ? "(no subject)" : item.subject).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.destinationName).font(.subheadline)
                                Text(item.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(item.id)
                    }
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

            if let item = filtered.first(where: { $0.id == selectedID }) {
                HistoryDetail(model: model, item: item)
                    .frame(minWidth: 300, idealWidth: 360)
            } else {
                Text("Select an item").font(.title3).foregroundStyle(.secondary).frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func sourceIcon(_ item: HistoryItem) -> NSImage {
        if item.emlPath != nil { return NSWorkspace.shared.icon(for: .emailMessage) }
        if let id = item.source?.bundleID, let icon = TileImages.appIcon(bundleID: id) { return icon }
        return NSWorkspace.shared.icon(for: .url)
    }
}

struct HistoryDetail: View {
    @Bindable var model: AppModel
    let item: HistoryItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.subject.isEmpty ? "(no subject)" : item.subject).font(.title2.bold())
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("To", item.to.joined(separator: ", "))
                    if !item.cc.isEmpty { row("Cc", item.cc.joined(separator: ", ")) }
                    if !item.bcc.isEmpty { row("Bcc", item.bcc.joined(separator: ", ")) }
                    row("When", item.date.formatted(date: .abbreviated, time: .shortened))
                    row("Kind", item.kind.label)
                    if let s = item.source { row("From app", s.name + (s.guessed ? " (guessed)" : "")) }
                    row("Went to", item.destinationName)
                    if !item.attachments.isEmpty { row("Attachments", item.attachments.joined(separator: ", ")) }
                }
                .font(.title3)
                GroupBox("Why it went there") {
                    Text(item.explanation.text).font(.title3).frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                if item.hasBody, let body = model.history.body(for: item) {
                    GroupBox("Body") {
                        Text(body).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Button("Send again") { model.onSendAgain?(item, model.config.destination(id: item.destinationID)) }
                    Button("Send elsewhere…") { model.onSendAgain?(item, nil) }
                    Button("Make a rule from this") { model.makeRule(from: item) }
                    if let path = item.emlPath {
                        Button("Open .eml") { model.onOpenEml?(URL(fileURLWithPath: path)) }
                            .disabled(!FileManager.default.fileExists(atPath: path))
                    }
                    Button("Delete", role: .destructive) { model.history.remove(id: item.id); model.refresh() }
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .padding(16)
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Mailto Segue").font(.largeTitle.bold())
            Text("Version \(SegueVersion.string)").font(.title3).foregroundStyle(.secondary)
            Text("Every mailto: link, exactly where you want it.").font(.title3)
            Text("Mailto Segue is a marshaller, not a mail client. It never composes, edits or sends mail.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Divider().frame(width: 300)
            VStack(spacing: 6) {
                Link("Made by Overtone Foundry", destination: URL(string: "https://overtonefoundry.com")!)
                Link("Source on GitHub (MIT)", destination: URL(string: "https://github.com/jeremym/mailto-segue")!)
                Text("Service logos: Simple Icons v\(ServiceIcons.version) (CC0). Logos are trademarks of their owners.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            .font(.title3)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
