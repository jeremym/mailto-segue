import SwiftUI
import UniformTypeIdentifiers
import SegueCore

struct DestinationsView: View {
    @Bindable var model: AppModel
    @State private var selectedID: String?

    init(model: AppModel, initialSelection: String? = nil) {
        self.model = model
        _selectedID = State(initialValue: initialSelection)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(model.config.destinations) { d in
                        HStack(spacing: 10) {
                            Image(nsImage: TileImages.image(for: d, supportDirectory: model.supportDirectory, size: 36))
                                .resizable().frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.name).font(.title3.weight(.semibold))
                                Text(subtitle(d)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if d.isPinned { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                            if let k = d.key { Text(k).font(.system(.title3, design: .monospaced)).foregroundStyle(.secondary) }
                        }
                        .opacity(d.isEnabled ? 1 : 0.5)
                        .padding(.vertical, 4)
                        .tag(d.id)
                    }
                    .onMove { from, to in model.config.destinations.move(fromOffsets: from, toOffset: to) }
                }
                HStack {
                    Menu("Add a button") {
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
                    Text("Drag to reorder").font(.callout).foregroundStyle(.secondary)
                }
                .controlSize(.large)
                .padding(10)
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)

            if let id = selectedID, let index = model.config.destinations.firstIndex(where: { $0.id == id }) {
                DestinationEditor(model: model, destination: $model.config.destinations[index])
                    .id(id)
                    .frame(minWidth: 440)
            } else {
                VStack(spacing: 10) {
                    Text("Each button is one place an email can go.").font(.title2)
                    Text("Select one on the left, or add a button.").font(.title3).foregroundStyle(.secondary)
                }
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func subtitle(_ d: Destination) -> String {
        switch d.type {
        case .webmail:
            var s = d.provider?.displayName ?? "Webmail"
            if let e = d.account?.email { s += " · \(e)" } else if let i = d.account?.index { s += " · account \(i + 1)" }
            if let b = d.browser, !b.isSystemDefault, let id = b.bundleID {
                s += " · " + (NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id)
                if let p = b.profileName ?? b.profile { s += " (\(p))" }
            } else {
                s += " · default browser"
            }
            return s
        case .app: return model.installedMailApps.first { $0.bundleID == d.bundleID }?.name ?? (d.bundleID ?? "app")
        case .clipboard:
            switch d.copy ?? .addresses {
            case .addresses: return "Copies the addresses"
            case .mailto: return "Copies the mailto: link"
            case .all: return "Copies everything"
            }
        case .template: return d.template ?? "custom URL"
        case .browserHandler: return "The browser's own email handler"
        }
    }

    func kindTitle(_ kind: Destination.Kind) -> String {
        switch kind {
        case .webmail: return "Webmail (Gmail, Outlook, Yahoo…)"
        case .app: return "A mail app on this Mac"
        case .clipboard: return "Copy to the clipboard"
        case .template: return "A custom URL"
        case .browserHandler: return "The browser's own email handler"
        }
    }
}

struct DestinationEditor: View {
    @Bindable var model: AppModel
    @Binding var destination: Destination
    @State private var lastAutoName = ""
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                group("The button") {
                    FieldRow(label: "Button name", help: Help.buttonName) {
                        BoxedField(text: $destination.name, example: "Gmail — work")
                    }
                    FieldRow(label: "Keyboard shortcut", help: Help.shortcut) {
                        BoxedField(text: $destination.keyText, example: "1").frame(width: 70)
                    }
                    FieldRow(label: "Pinned", help: Help.pinned) { Toggle("", isOn: $destination.isPinned).labelsHidden() }
                    FieldRow(label: "Enabled") { Toggle("", isOn: $destination.isEnabled).labelsHidden() }
                }
                group("Where the email goes") { whereSection }
                group("This account's address") {
                    FieldRow(label: "Sends from", help: Help.sendsAs) {
                        BoxedField(text: $destination.sendsAsText, example: "me@work.com")
                    }
                }
                group("Look") {
                    FieldRow(label: "Picture", help: Help.picture) {
                        HStack {
                            Button("Choose…") { choosePicture() }
                            if destination.image != nil {
                                Text(destination.imageText).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                Button("Remove") { destination.image = nil; refreshTiles() }
                            }
                        }
                    }
                    FieldRow(label: "Colour", help: Help.colour) {
                        HStack {
                            ColorPicker("", selection: Binding(
                                get: { Color(nsColor: Design.color(hex: destination.color) ?? .controlAccentColor) },
                                set: { destination.colorText = hex($0); refreshTiles() })).labelsHidden()
                            if destination.color != nil { Button("Use the default colour") { destination.color = nil; refreshTiles() } }
                        }
                    }
                }
                let problems = destination.validate()
                if !problems.isEmpty {
                    ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.title3).foregroundStyle(.orange) }
                }
                Button("Test this button") { model.onTestDestination?(destination) }
                    .help("Opens a sample email addressed to test@example.com through this button.")
                    .controlSize(.large)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.large)
        .onAppear { lastAutoName = model.autoName(for: destination) }
        .onChange(of: destination.accountEmail) { _, new in
            autoRename()
            if destination.sendsAsText.isEmpty, !new.isEmpty { destination.sendsAsText = new }
        }
        .onChange(of: destination.accountIndexText) { _, _ in autoRename() }
        .onChange(of: destination.providerValue) { _, _ in autoRename(); refreshTiles() }
        .onChange(of: destination.bundleIDText) { _, _ in autoRename(); refreshTiles() }
        .onChange(of: destination.browserBundleID) { _, _ in autoRename(); refreshTiles() }
    }

    private var preview: some View {
        HStack(spacing: 16) {
            Image(nsImage: TileImages.image(for: destination, supportDirectory: model.supportDirectory, size: 72))
                .resizable().frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name.isEmpty ? "Unnamed button" : destination.name).font(.title.bold())
                if let a = destination.primarySendsAs { Text(a).font(.title3).foregroundStyle(.secondary) }
                if let k = destination.key { Text("Press \(k)").font(.callout).foregroundStyle(.tertiary) }
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(.secondary).textCase(.uppercase)
            VStack(alignment: .leading, spacing: 2) { content() }
                .padding(12)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private var whereSection: some View {
        switch destination.type {
        case .webmail:
            FieldRow(label: "Service", help: Help.service) {
                Picker("", selection: $destination.providerValue) {
                    ForEach(WebmailProvider.allCases, id: \.self) {
                        Text($0.displayName + ($0.supportsDirectCompose ? "" : " (needs a custom URL)")).tag($0)
                    }
                }
                .labelsHidden().fixedSize()
            }
            browserRows
            if destination.providerValue.supportsAccountSelection {
                FieldRow(label: "\(destination.providerValue.displayName) account", help: Help.gmailAccount) {
                    HStack {
                        BoxedField(text: $destination.accountEmail, example: "me@work.com")
                        let accounts = model.signedInAccounts(browserBundleID: destination.browser?.bundleID, profile: destination.browser?.profile)
                        if !accounts.isEmpty {
                            Menu("Signed in") {
                                ForEach(accounts, id: \.self) { a in Button(a) { destination.accountEmail = a } }
                            }
                            .fixedSize()
                        }
                    }
                }
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    FieldRow(label: "Account number", help: Help.accountIndex) {
                        BoxedField(text: $destination.accountIndexText, example: "0").frame(width: 70)
                    }
                }
                .font(.title3)
            }
        case .app:
            FieldRow(label: "Mail app", help: Help.mailApp) {
                Picker("", selection: $destination.bundleIDText) {
                    ForEach(model.installedMailApps, id: \.bundleID) { app in
                        Label { Text(app.name) } icon: { Image(nsImage: TileImages.fitted(NSWorkspace.shared.icon(forFile: app.url.path), size: 18)) }.tag(app.bundleID)
                    }
                    if !model.installedMailApps.contains(where: { $0.bundleID == destination.bundleIDText }) {
                        Text(destination.bundleIDText.isEmpty ? "Choose…" : destination.bundleIDText).tag(destination.bundleIDText)
                    }
                }
                .labelsHidden().fixedSize()
            }
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                FieldRow(label: "App identifier") { BoxedField(text: $destination.bundleIDText, example: "com.apple.mail", monospaced: true) }
            }
            .font(.title3)
        case .clipboard:
            FieldRow(label: "What to copy", help: Help.copy) {
                Picker("", selection: $destination.copyValue) {
                    Text("The addresses").tag(Destination.CopyMode.addresses)
                    Text("The mailto: link").tag(Destination.CopyMode.mailto)
                    Text("Everything: To, Cc, subject and body").tag(Destination.CopyMode.all)
                }
                .labelsHidden().fixedSize()
            }
        case .template:
            FieldRow(label: "URL", help: Help.template) {
                TextField("", text: $destination.templateText, prompt: Text("https://…?to={to}&subject={subject}").foregroundStyle(.tertiary), axis: .vertical)
                    .textFieldStyle(.roundedBorder).font(.system(.title3, design: .monospaced)).lineLimit(2...6)
            }
            browserRows
        case .browserHandler:
            FieldRow(label: "How it works", help: Help.browserHandler) {
                Text("The browser's own email handler takes the link.").font(.title3).foregroundStyle(.secondary)
            }
            browserRows
        }
    }

    @ViewBuilder private var browserRows: some View {
        FieldRow(label: "Browser", help: Help.browser) {
            Picker("", selection: $destination.browserBundleID) {
                Text("System default").tag("default")
                ForEach(model.installedBrowsers, id: \.bundleID) { app in
                    Label { Text(app.name) } icon: { Image(nsImage: TileImages.fitted(NSWorkspace.shared.icon(forFile: app.url.path), size: 18)) }.tag(app.bundleID)
                }
            }
            .labelsHidden().fixedSize()
        }
        let profiles = model.profiles(forBrowser: destination.browser?.bundleID)
        if !profiles.isEmpty {
            FieldRow(label: "Profile", help: Help.profile) {
                Picker("", selection: $destination.browserProfile) {
                    Text("Whichever was used last").tag("")
                    ForEach(profiles, id: \.directory) { Text($0.name).tag($0.directory) }
                    if !destination.browserProfile.isEmpty, !profiles.contains(where: { $0.directory == destination.browserProfile }) {
                        Text("\(destination.browserProfileName.isEmpty ? destination.browserProfile : destination.browserProfileName) (not found on this Mac)").tag(destination.browserProfile)
                    }
                }
                .labelsHidden().fixedSize()
                .onChange(of: destination.browserProfile) { _, new in
                    destination.browserProfileName = profiles.first { $0.directory == new }.map { String($0.name.split(separator: "·").first ?? "").trimmingCharacters(in: .whitespaces) } ?? ""
                    refreshTiles()
                }
            }
        }
        if let id = destination.browser?.bundleID, BrowserLauncher.family(of: id) == .firefox {
            FieldRow(label: "Container", help: Help.container) { BoxedField(text: $destination.browserContainer, example: "Work") }
        }
        if let id = destination.browser?.bundleID, BrowserLauncher.family(of: id) != .safari, destination.type != .browserHandler {
            FieldRow(label: "Open in", help: Help.openIn) {
                Picker("", selection: $destination.browserWindowMode) {
                    Text("A tab").tag(BrowserTarget.WindowMode.tab)
                    Text("A new window").tag(BrowserTarget.WindowMode.window)
                    if BrowserLauncher.family(of: id) == .chromium { Text("Its own window (no toolbar)").tag(BrowserTarget.WindowMode.app) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    /// Keeps the name in step with the account until the user types their own.
    private func autoRename() {
        let auto = model.autoName(for: destination)
        let stale = destination.name.isEmpty || destination.name == lastAutoName
            || destination.name == (destination.provider?.displayName ?? "") || destination.name == "Gmail"
        if stale { destination.name = auto }
        lastAutoName = auto
    }

    private func refreshTiles() { TileImageCache.clear(supportDirectory: model.supportDirectory) }

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

// MARK: - Rules

enum RuleFields {
    static let labels: [(field: String, label: String)] = [
        ("to.domain", "Recipient's domain"),
        ("to", "Recipient address"),
        ("recipient.domain", "Any recipient's domain (To, Cc, Bcc)"),
        ("recipient", "Any recipient address"),
        ("cc.domain", "Cc domain"), ("cc", "Cc address"),
        ("bcc.domain", "Bcc domain"), ("bcc", "Bcc address"),
        ("sourceApp", "App the link came from"),
        ("sourceApp.name", "App the link came from (by name)"),
        ("subject", "Subject"), ("body", "Body"),
        ("kind", "Kind (mailto, reply, replyAll, forward, cli)"),
        ("original.from.domain", "Original sender's domain (.eml)"),
        ("original.from", "Original sender address (.eml)"),
        ("original.deliveredTo", "Address the original went to (.eml)"),
        ("original.deliveredTo.domain", "Domain the original went to (.eml)"),
        ("original.listId", "Mailing list (.eml)"),
        ("original.messageId", "Message-ID (.eml)"),
    ]
    static func label(_ field: String) -> String { labels.first { $0.field == field }?.label ?? field }
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
                                Text(rule.name).font(.title3.weight(.semibold))
                                Text(summary(rule)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(i)
                    }
                    .onMove { from, to in model.config.rules.move(fromOffsets: from, toOffset: to); selected = nil }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Add a rule") { model.addRule(); selected = model.config.rules.count - 1 }
                        Button("Remove", role: .destructive) {
                            if let i = selected, i < model.config.rules.count { model.config.rules.remove(at: i); selected = nil }
                        }
                        .disabled(selected == nil)
                        Spacer()
                        Text("Top rule wins · drag to reorder").font(.callout).foregroundStyle(.secondary)
                    }
                    FieldRow(label: "If no rule matches", help: Help.fallback) {
                        Picker("", selection: Binding(
                            get: { if case .destination(let id) = model.config.fallback { return id } else { return "chooser" } },
                            set: { model.config.fallback = $0 == "chooser" ? .chooser : .destination($0) })) {
                            Text("Show the chooser").tag("chooser")
                            ForEach(model.config.destinations) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                .controlSize(.large)
                .padding(10)
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)

            if let i = selected, i < model.config.rules.count {
                RuleEditor(model: model, rule: $model.config.rules[i]).id(i).frame(minWidth: 440)
            } else {
                VStack(spacing: 10) {
                    Text("Rules send a link somewhere without asking.").font(.title2)
                    Text("They run top to bottom; the first match wins.").font(.title3).foregroundStyle(.secondary)
                }
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func summary(_ r: Rule) -> String {
        if let b = r.builtin { return "Built-in: \(Rule.Builtin(rawValue: b)?.defaultName ?? b)" }
        let conds = r.when.map { "\(RuleFields.label($0.field)) \(opTitle($0.op)) \($0.value)" }.joined(separator: r.match == .all ? " AND " : " OR ")
        let dest = r.then.flatMap { model.config.destination(id: $0)?.name } ?? "(no button chosen)"
        return "\(conds) → \(dest)"
    }
}

func opTitle(_ op: Condition.Op) -> String {
    switch op {
    case .is: return "is"
    case .domainIs: return "is in the domain"
    case .contains: return "contains"
    case .startsWith: return "starts with"
    case .matches: return "matches the pattern"
    }
}

struct RuleEditor: View {
    @Bindable var model: AppModel
    @Binding var rule: Rule

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FieldRow(label: "Rule name") { BoxedField(text: $rule.name, example: "Slack → work") }
                FieldRow(label: "Enabled") { Toggle("", isOn: $rule.enabled).labelsHidden() }
                if rule.builtin != nil {
                    Text("This built-in rule sends a reply to the button whose “Sends from” address matches the address the message was delivered to.")
                        .font(.title3).foregroundStyle(.secondary)
                } else {
                    FieldRow(label: "Match", help: Help.ruleMatch) {
                        Picker("", selection: $rule.match) {
                            Text("all of these").tag(Rule.MatchMode.all)
                            Text("any of these").tag(Rule.MatchMode.any)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                    }
                    Text("WHEN").font(.headline).foregroundStyle(.secondary)
                    ForEach(rule.when.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Picker("", selection: $rule.when[i].field) {
                                ForEach(RuleFields.labels, id: \.field) { Text($0.label).tag($0.field) }
                                if !RuleFields.labels.contains(where: { $0.field == rule.when[i].field }) { Text(rule.when[i].field).tag(rule.when[i].field) }
                            }
                            .labelsHidden().frame(width: 230)
                            Picker("", selection: $rule.when[i].op) {
                                ForEach(Condition.Op.allCases, id: \.self) { Text(opTitle($0)).tag($0) }
                            }
                            .labelsHidden().frame(width: 170)
                            if rule.when[i].field == "sourceApp" {
                                Menu {
                                    ForEach(model.runningApps(), id: \.bundleID) { app in Button(app.name) { rule.when[i].value = app.bundleID } }
                                } label: { Text(rule.when[i].value.isEmpty ? "Choose an app…" : rule.when[i].value).lineLimit(1) }
                                .frame(maxWidth: .infinity)
                            } else {
                                BoxedField(text: $rule.when[i].value, example: "acme.com")
                            }
                            Button(role: .destructive) { rule.when.remove(at: i) } label: { Image(systemName: "minus.circle").font(.title3) }
                                .buttonStyle(.borderless).accessibilityLabel("Remove condition")
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Add a condition") { rule.when.append(Condition(field: "to.domain", op: .domainIs, value: "")) }
                        HelpButton(text: Help.ruleField)
                    }
                    FieldRow(label: "Then open with", help: Help.ruleThen) {
                        Picker("", selection: $rule.thenText) {
                            Text("Choose a button…").tag("")
                            ForEach(model.config.destinations) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.large)
    }
}
