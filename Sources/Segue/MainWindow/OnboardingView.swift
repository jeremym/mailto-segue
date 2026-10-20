import SwiftUI
import SegueCore

/// The first-run screen: three big cards, each with one button and a
/// checkmark when done. Nothing is sent and no permission is requested;
/// the only system prompt is Apple's own "Use / Keep".
struct OnboardingView: View {
    @Bindable var model: AppModel
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to Mailto Segue").font(.largeTitle.bold())
                        Text("Every email link goes exactly where you want it: the right Gmail account, browser, or mail app.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                }

                card(number: 1, title: "Make Mailto Segue your email app", done: model.isMailtoDefault,
                     detail: model.isMailtoDefault
                        ? "Done. Email links now open the chooser."
                        : "macOS will ask you to confirm. If you choose “Keep”, nothing changes and you can try again here or in Settings.") {
                    Button("Make it my email app") { model.makeDefaultForMailto() }
                        .buttonStyle(.borderedProminent)
                }

                card(number: 2, title: "Also open .eml files", done: model.isEmlDefault,
                     detail: model.isEmlDefault
                        ? "Done. Double-clicking a saved message shows it with Reply buttons."
                        : "Optional. A saved message opens in Mailto Segue with “Reply with …” buttons under it.") {
                    Button("Open .eml files here") { model.makeDefaultForEml() }
                }

                card(number: 3, title: "Your buttons", done: !model.config.destinations.isEmpty,
                     detail: "These were found on your Mac. Rename them, add a picture, or add more under Destinations.") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(model.config.destinations.prefix(6)) { d in
                                VStack(spacing: 4) {
                                    Image(nsImage: TileImages.image(for: d, supportDirectory: model.supportDirectory, size: 48))
                                        .resizable().frame(width: 48, height: 48)
                                    Text(d.name).font(.callout).lineLimit(1).frame(width: 96)
                                }
                            }
                        }
                        HStack {
                            Button("Edit the buttons") { model.requestSection?(.destinations) }
                            Button("Try it: send a test link") { model.onTryIt?() }
                                .help("Opens the chooser once with a sample email, so you can see how it works.")
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Done") { onDone() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Text("Mailto Segue never asks for a password and never sends mail. Your sign-ins stay in your browser.")
                    .font(.callout).foregroundStyle(.tertiary)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .controlSize(.large)
    }

    @ViewBuilder private func card<Content: View>(number: Int, title: String, done: Bool, detail: String,
                                                  @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor).frame(width: 40, height: 40)
                if done { Image(systemName: "checkmark").font(.title2.bold()).foregroundStyle(.white) }
                else { Text("\(number)").font(.title2.bold()).foregroundStyle(.white) }
            }
            .accessibilityLabel(done ? "Step \(number), done" : "Step \(number)")
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title2.bold())
                Text(detail).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}
