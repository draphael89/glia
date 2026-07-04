import SwiftUI
import CoreSpotlight

@main
struct GliaApp: App {
    @State private var model = AppModel()

    init() {
        // Snapshot runs are tooling, not sessions: stay out of the Dock and
        // never steal focus from whatever the user is doing.
        if ProcessInfo.processInfo.environment["GLIA_SNAPSHOT"] != nil {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        Markers.drop("app.init")
    }

    var body: some Scene {
        // Window (not WindowGroup): Glia is single-window by design — the
        // model owns one Metal view attachment, and a second window would
        // silently steal it.
        Window("Glia", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .onOpenURL { url in
                    // glia://node/<id>
                    guard url.scheme == "glia", url.host == "node",
                          let id = Int(url.lastPathComponent) else { return }
                    model.open(nodeID: id)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          raw.hasPrefix("node:"), let id = Int(raw.dropFirst(5)) else { return }
                    model.open(nodeID: id)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .defaultPosition(.center)
        .commands {
            #if !MAS
            CheckForUpdatesCommand()
            #endif
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Search Brain…") {
                    model.paletteVisible = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Fit View") {
                    model.fitView()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Zoom In") { model.zoomStep(1.35) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { model.zoomStep(1 / 1.35) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { model.fitView() }
                    .keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Choose Brain Folder…") {
                    model.chooseBrainFolder()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Export Snapshot…") {
                    model.exportSnapshot()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                if model.demoActive {
                    Button("Exit Demo") { model.exitDemo() }
                }
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            // pulses when a fresh brain snapshot lands — the "it's alive"
            // heartbeat you can see without opening the window
            Image(systemName: "brain.head.profile")
                .symbolEffect(.bounce, value: model.graph.generatedAt)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text("\(model.graph.nodes.count.formatted()) pages · \(model.updatedTodayCount) today")
            Divider()
            Button("Open Glia") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Quit Glia") { NSApp.terminate(nil) }
        }
    }
}
