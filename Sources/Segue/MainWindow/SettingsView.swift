import SwiftUI
import SegueCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var doctorLines: [Doctor.Line]? = nil

    var body: some View {
        Form {
            Section("Default apps") {
                LabeledContent("Email links (mailto:)") {
                    HStack {
                        Text(model.isMailtoDefault ? "Segue" : "Not Segue").foregroundStyle(model.isMailtoDefault ? .green : .secondary)
                        Button("Make Segue default") { model.makeDefaultForMailto() }.disabled(model.isMailtoDefault)
                        Button("Restore Mail") { model.restoreMailForMailto() }
                    }
                }
                LabeledContent(".eml files") {
                    HStack {
                        Text(model.isEmlDefault ? "Segue" : "Not Segue").foregroundStyle(model.isEmlDefault ? .green : .secondary)
                        Button("Open .eml with Segue") { model.makeDefaultForEml() }.disabled(model.isEmlDefault)
                        Button("Restore Mail") { model.restoreMailForEml() }
                    }
                }
                Text("macOS asks you to confirm each change. Choosing “Keep” leaves things as they were.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Chooser") {
                Picker("Layout", selection: $model.config.chooser.layout) {
                    Text("Large tiles").tag(ChooserSettings.Layout.largeTiles)
                    Text("Small tiles").tag(ChooserSettings.Layout.smallTiles)
                    Text("Compact list").tag(ChooserSettings.Layout.compactList)
                }
                .pickerStyle(.segmented)
                Picker("Position", selection: $model.config.chooser.position) {
                    Text("Centre of the screen").tag(ChooserSettings.Position.center)
                    Text("Near the mouse").tag(ChooserSettings.Position.mouse)
                }
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $model.config.chooser.textScale, in: 1.0...2.0, step: 0.1)
                        Text(String(format: "%.1f×", model.config.chooser.textScale)).monospacedDigit().frame(width: 44)
                    }
                }
                Picker("Hold this key to force the chooser", selection: $model.config.chooser.forceModifier) {
                    Text("⌥ Option").tag(ChooserSettings.Modifier.option)
                    Text("⇧ Shift").tag(ChooserSettings.Modifier.shift)
                    Text("⌃ Control").tag(ChooserSettings.Modifier.control)
                    Text("⌘ Command").tag(ChooserSettings.Modifier.command)
                }
                Toggle("Highlight the last choice for the same app or domain", isOn: $model.config.chooser.learnDefault)
                Button("Forget learned choices") { LearnedChoices(directory: model.supportDirectory).clear(); model.statusMessage = "Forgotten." }
            }

            Section(".eml files") {
                Toggle("Let rules route an opened .eml without showing it", isOn: $model.config.eml.autoRoute)
                Text("Off by default: opening a file is deliberate, so rules only suggest (★).").font(.callout).foregroundStyle(.secondary)
            }

            Section("History") {
                LabeledContent("On disk", value: model.historyUsage())
                Stepper("Keep up to \(model.config.history.keepItems) items (0 turns history off)", value: $model.config.history.keepItems, in: 0...5000, step: 50)
                    .onChange(of: model.config.history.keepItems) { _, _ in model.history.enforce(settings: model.config.history); model.refresh() }
                Stepper("At most \(model.config.history.maxMB) MB", value: $model.config.history.maxMB, in: 1...1000, step: 10)
                    .onChange(of: model.config.history.maxMB) { _, _ in model.history.enforce(settings: model.config.history); model.refresh() }
                Button("Clear history", role: .destructive) { model.clearHistory(); model.statusMessage = "History cleared." }
            }

            Section("General") {
                Toggle("Stay running in the menu bar (and open at login)", isOn: $model.config.general.stayRunning)
                    .onChange(of: model.config.general.stayRunning) { _, on in model.onStayRunningChanged?(on) }
                Toggle("Pause rules (every link shows the chooser)", isOn: $model.config.general.rulesPaused)
                Text("Off by default: Segue launches when a link arrives and quits when it's done.").font(.callout).foregroundStyle(.secondary)
                Toggle("Treat + as a space in links (some senders encode spaces that way)", isOn: $model.config.general.plusAsSpace)
            }

            Section("Maintenance") {
                HStack {
                    Button("Check setup") { doctorLines = model.doctor() }
                    Button("Reveal config.json") { NSWorkspace.shared.activateFileViewerSelecting([model.store.fileURL]) }
                    Button("Clear tile cache") { TileImageCache.clear(supportDirectory: model.supportDirectory); model.statusMessage = "Tile cache cleared." }
                }
                if let err = model.configError {
                    Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let lines = doctorLines {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Label(line.text, systemImage: line.ok ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(line.ok ? Color.primary : Color.orange)
                                .textSelection(.enabled)
                        }
                    }
                    .font(.body)
                }
            }
        }
        .formStyle(.grouped)
        .font(.title3)
        .controlSize(.large)
    }
}
