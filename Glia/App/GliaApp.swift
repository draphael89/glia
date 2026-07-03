import SwiftUI

@main
struct GliaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
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
