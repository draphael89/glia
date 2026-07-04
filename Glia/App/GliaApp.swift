import SwiftUI
import CoreSpotlight

@main
struct GliaApp: App {
    @State private var model = AppModel()

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
            CheckForUpdatesCommand()
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
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: "brain.head.profile")
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
