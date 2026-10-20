import AppKit
import SwiftUI
import SegueCore

/// The main window: History · Destinations · Rules · Settings · About.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let model: AppModel
    private var onClose: (() -> Void)?

    static func present(model: AppModel, section: MainSection = .history, onClose: @escaping () -> Void) -> MainWindowController {
        let c = MainWindowController(model: model, section: section)
        c.onClose = onClose
        NSApp.setActivationPolicy(.regular)
        c.showWindow(nil)
        NSApp.activate()
        c.window?.makeKeyAndOrderFront(nil)
        return c
    }

    private init(model: AppModel, section: MainSection) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Mailto Segue"
        window.minSize = NSSize(width: 760, height: 480)
        window.center()
        window.setFrameAutosaveName("SegueMain")
        window.contentView = NSHostingView(rootView: MainView(model: model, initialSection: section))
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        model.saveNow()
        let handler = onClose
        onClose = nil
        handler?()
    }

    @discardableResult
    func snapshot(to file: URL) -> Bool {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: file, options: .atomic)) != nil
    }

    func select(_ section: MainSection) {
        window?.contentView = NSHostingView(rootView: MainView(model: model, initialSection: section))
    }
}

enum MainSection: String, CaseIterable, Identifiable {
    case history, destinations, rules, settings, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .history: return "History"
        case .destinations: return "Destinations"
        case .rules: return "Rules"
        case .settings: return "Settings"
        case .about: return "About"
        }
    }
    var symbol: String {
        switch self {
        case .history: return "clock"
        case .destinations: return "square.grid.2x2"
        case .rules: return "arrow.triangle.branch"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct MainView: View {
    @Bindable var model: AppModel
    @State private var section: MainSection

    init(model: AppModel, initialSection: MainSection) {
        self.model = model
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: Binding(get: { section }, set: { section = $0 ?? .history })) { s in
                Label(s.title, systemImage: s.symbol).font(.title3).padding(.vertical, 4).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch section {
                case .history: HistoryView(model: model)
                case .destinations: DestinationsView(model: model)
                case .rules: RulesView(model: model)
                case .settings: SettingsView(model: model)
                case .about: AboutView()
                }
            }
            .frame(minWidth: 520)
        }
        .overlay(alignment: .bottom) {
            if let msg = model.statusMessage {
                Text(msg)
                    .font(.title3)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 14)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        if model.statusMessage == msg { model.statusMessage = nil }
                    }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refresh() }
    }
}
