import SwiftUI
import UniformTypeIdentifiers
import SegueCore

struct DestinationsView: View {
    @Bindable var model: AppModel
    @State private var selectedID: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(model.config.destinations) { d in
                        HStack(spacing: 10) {
                            Image(nsImage: TileImages.image(for: d, supportDirectory: model.supportDirectory, size: 32))
                                .resizable().frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.name).font(.headline)
                                Text(subtitle(d)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if d.isPinned { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                            if let k = d.key { Text(k).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                        }
                        .opacity(d.isEnabled ? 1 : 0.5)
                        .padding(.vertical, 3)
                        .tag(d.id)
                    }
                    .onMove { from, to in model.config.destinations.move(fromOffsets: from, toOffset: to) }
                }
                HStack {
                    Menu("Add") {
                        ForEach(Destination.Kind.allCases, id: \.self) { kind in
                            Button(kindTitle(kind)) { selectedID = model.addDestination(type: kind).id }
                        }
                    }
                    .fixedSize()
                    Button("Remove", role: .destructive) {
                        if let id = selectedID { model.removeDestination(id: id); selectedID = nil }
                    }
                    .disabled(selectedID == nil)
                    Spacer()
                    Text("Drag to reorder").font(.caption).foregroundStyle(.secondary)
                }
                .controlSize(.large)
                .padding(10)
            }
            .frame(minWidth: 320)

            if let id = selectedID, let index = model.config.destinations.firstIndex(where: { $0.id == id }) {
                DestinationEditor(model: model, destination: $model.config.destinations[index])
                    .id(id)
                    .frame(minWidth: 380)
            } else {
                Text("Select a destination, or add one").font(.title3).foregroundStyle(.secondary)
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func subtitle(_ d: Destination) -> String {
        switch d.type {
        case .webmail:
            var s = d.provider?.displayName ?? "Webmail"
            if let e = d.account?.email { s += " · \(e)" } else if let i = d.account?.index { s += " · u/\(i)" }
            if let b = d.browser, !b.isSystemDefault, let id = b.bundleID {
                s += " · " + (NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id)
                if let p = b.profileName ?? b.profile { s += " (\(p))" }
            }
            return s
        case .app: return d.bundleID ?? "app"
        case .clipboard: return "Copy " + (d.copy ?? .addresses).rawValue
        case .template: return d.template ?? "template"
        case .browserHandler: return "Browser's own mail handler"
        }
    }

    func kindTitle(_ kind: Destination.Kind) -> String {
        switch kind {
        case .webmail: return "Webmail (Gmail, Outlook, Yahoo…)"
        case .app: return "Mail app"
        case .clipboard: return "Clipboard"
        case .template: return "Custom URL template"
        case .browserHandler: return "Browser's own mail handler"
        }
    }
}

struct DestinationEditor: View {
    @Bindable var model: AppModel
    @Binding var destination: Destination

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $destination.name)
                TextField("Key (one character)", text: $destination.keyText)
                TextField("Sends as (addresses, comma-separated)", text: $destination.sendsAsText)
                Toggle("Pinned (always first)", isOn: $destination.isPinned)
                Toggle("Enabled", isOn: $destination.isEnabled)
            }
            switch destination.type {
            case .webmail:
                Section("Webmail") {
                    Picker("Service", selection: $destination.providerValue) {
                        ForEach(WebmailProvider.allCases, id: \.self) { Text($0.displayName + ($0.supportsDirectCompose ? "" : " (needs a template)")).tag($0) }
                    }
                    if destination.providerValue.supportsAccountSelection {
                        TextField("Account email (Gmail authuser)", text: $destination.accountEmail)
                        TextField("or account index (u/N)", text: $destination.accountIndexText)
                    }
                }
                browserSection
            case .app:
                Section("Mail app") {
                    Picker("App", selection: $destination.bundleIDText) {
                        ForEach(model.installedMailApps, id: \.bundleID) { Text($0.name).tag($0.bundleID) }
                        if !model.installedMailApps.contains(where: { $0.bundleID == destination.bundleIDText }) {
                            Text(destination.bundleIDText.isEmpty ? "Choose…" : destination.bundleIDText).tag(destination.bundleIDText)
                        }
                    }
                    TextField("Bundle ID", text: $destination.bundleIDText)
                }
            case .clipboard:
                Section("Clipboard") {
                    Picker("Copy", selection: $destination.copyValue) {
                        Text("Addresses only").tag(Destination.CopyMode.addresses)
                        Text("The mailto: link").tag(Destination.CopyMode.mailto)
                        Text("Everything (To/Cc/Subject + body)").tag(Destination.CopyMode.all)
                    }
                }
            case .template:
                Section("Template") {
                    TextField("URL with {to} {cc} {bcc} {subject} {body} {mailto} {domain}", text: $destination.templateText, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                }
                browserSection
            case .browserHandler:
                browserSection
            }
            Section("Look") {
                HStack {
                    Image(nsImage: TileImages.image(for: destination, supportDirectory: model.supportDirectory, size: 64))
                        .resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading) {
                        Button("Choose picture…") { choosePicture() }
                        if destination.image != nil { Button("Remove picture") { destination.image = nil; TileImageCache.clear(supportDirectory: model.supportDirectory) } }
                    }
                }
                ColorPicker("Tile colour", selection: Binding(
                    get: { Color(nsColor: Design.color(hex: destination.color) ?? .controlAccentColor) },
                    set: { destination.colorText = hex($0); TileImageCache.clear(supportDirectory: model.supportDirectory) }))
                if destination.color != nil { Button("Use the default colour") { destination.color = nil; TileImageCache.clear(supportDirectory: model.supportDirectory) } }
            }
            Section {
                Button("Test this destination") { model.onTestDestination?(destination) }
                    .help("Opens a sample email addressed to test@example.com through this destination.")
                let problems = destination.validate()
                if !problems.isEmpty {
                    ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
        }
        .formStyle(.grouped)
        .font(.title3)
        .controlSize(.large)
    }

    @ViewBuilder private var browserSection: some View {
        Section("Browser") {
            Picker("Browser", selection: $destination.browserBundleID) {
                Text("System default").tag("default")
                ForEach(model.installedBrowsers, id: \.bundleID) { Text($0.name).tag($0.bundleID) }
            }
            let profiles = model.profiles(forBrowser: destination.browser?.bundleID)
            if !profiles.isEmpty {
                Picker("Profile", selection: $destination.browserProfile) {
                    Text("Last used").tag("")
                    ForEach(profiles, id: \.directory) { Text($0.name).tag($0.directory) }
                }
                .onChange(of: destination.browserProfile) { _, new in
                    destination.browserProfileName = profiles.first { $0.directory == new }?.name ?? ""
                    TileImageCache.clear(supportDirectory: model.supportDirectory)
                }
            }
            if let id = destination.browser?.bundleID, BrowserLauncher.family(of: id) == .firefox {
                TextField("Container (needs the “Open external links in a container” extension)", text: $destination.browserContainer)
            }
            if let id = destination.browser?.bundleID, BrowserLauncher.family(of: id) != .safari, destination.type != .browserHandler {
                Picker("Open in", selection: $destination.browserWindowMode) {
                    Text("A tab").tag(BrowserTarget.WindowMode.tab)
                    Text("A new window").tag(BrowserTarget.WindowMode.window)
                    if BrowserLauncher.family(of: id) == .chromium { Text("An app window (no toolbar)").tag(BrowserTarget.WindowMode.app) }
                }
            }
        }
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let rel = model.importImage(from: url) {
            destination.image = rel
        }
    }

    private func hex(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

struct RulesView: View {
    @Bindable var model: AppModel
    @State private var selected: Int?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(Array(model.config.rules.enumerated()), id: \.offset) { i, rule in
                        HStack {
                            Toggle("", isOn: Binding(get: { model.config.rules[i].enabled }, set: { model.config.rules[i].enabled = $0 })).labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.name).font(.headline)
                                Text(summary(rule)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(i)
                    }
                    .onMove { from, to in model.config.rules.move(fromOffsets: from, toOffset: to); selected = nil }
                }
                HStack {
                    Button("Add rule") { model.addRule(); selected = model.config.rules.count - 1 }
                    Button("Remove", role: .destructive) {
                        if let i = selected, i < model.config.rules.count { model.config.rules.remove(at: i); selected = nil }
                    }
                    .disabled(selected == nil)
                    Spacer()
                    Picker("If nothing matches", selection: Binding(
                        get: { if case .destination(let id) = model.config.fallback { return id } else { return "chooser" } },
                        set: { model.config.fallback = $0 == "chooser" ? .chooser : .destination($0) })) {
                        Text("Show the chooser").tag("chooser")
                        ForEach(model.config.destinations) { Text($0.name).tag($0.id) }
                    }
                    .fixedSize()
                }
                .controlSize(.large)
                .padding(10)
            }
            .frame(minWidth: 340)

            if let i = selected, i < model.config.rules.count {
                RuleEditor(model: model, rule: $model.config.rules[i]).id(i).frame(minWidth: 380)
            } else {
                Text("Rules run top to bottom. The first match wins.").font(.title3).foregroundStyle(.secondary)
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func summary(_ r: Rule) -> String {
        if let b = r.builtin { return "Built-in: \(Rule.Builtin(rawValue: b)?.defaultName ?? b)" }
        let conds = r.when.map(RuleEngine.describe).joined(separator: r.match == .all ? " AND " : " OR ")
        let dest = r.then.flatMap { model.config.destination(id: $0)?.name } ?? "(no destination)"
        return "\(conds) → \(dest)"
    }
}

struct RuleEditor: View {
    @Bindable var model: AppModel
    @Binding var rule: Rule

    var body: some View {
        Form {
            TextField("Name", text: $rule.name)
            Toggle("Enabled", isOn: $rule.enabled)
            if rule.builtin != nil {
                Text("This built-in rule routes a reply to the destination that sends as the address the message was delivered to. Set “Sends as” on your destinations for it to work.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Match", selection: $rule.match) {
                    Text("all conditions").tag(Rule.MatchMode.all)
                    Text("any condition").tag(Rule.MatchMode.any)
                }
                Section("When") {
                    ForEach(rule.when.indices, id: \.self) { i in
                        HStack {
                            Picker("", selection: $rule.when[i].field) {
                                ForEach(RouteContext.fields.filter { !$0.contains("<") }, id: \.self) { Text($0).tag($0) }
                                if !RouteContext.fields.contains(rule.when[i].field) { Text(rule.when[i].field).tag(rule.when[i].field) }
                            }
                            .labelsHidden().frame(width: 190)
                            Picker("", selection: $rule.when[i].op) {
                                ForEach(Condition.Op.allCases, id: \.self) { Text(opTitle($0)).tag($0) }
                            }
                            .labelsHidden().frame(width: 130)
                            TextField("value", text: $rule.when[i].value)
                            Button(role: .destructive) { rule.when.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Add condition") { rule.when.append(Condition(field: "to.domain", op: .domainIs, value: "")) }
                }
                Picker("Then open with", selection: $rule.thenText) {
                    Text("Choose…").tag("")
                    ForEach(model.config.destinations) { Text($0.name).tag($0.id) }
                }
            }
        }
        .formStyle(.grouped)
        .font(.title3)
        .controlSize(.large)
    }

    private func opTitle(_ op: Condition.Op) -> String {
        switch op {
        case .is: return "is"
        case .domainIs: return "is in domain"
        case .contains: return "contains"
        case .startsWith: return "starts with"
        case .matches: return "matches regex"
        }
    }
}
