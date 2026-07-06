import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            GraphView(model: model)
                .ignoresSafeArea()

            LabelOverlay(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                StatsBar(model: model)
                Spacer()
            }

            ReplayBar(model: model)

            HStack(spacing: 0) {
                FilterPanel(model: model)
                    .padding(.leading, 14)
                    .padding(.top, 56)
                Spacer()
                if model.selectedNode != nil {
                    InspectorPanel(model: model)
                        .padding(.trailing, 14)
                        .padding(.top, 56)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.32), value: model.selectedNode?.id)

            if model.paletteVisible {
                CommandPalette(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if let error = model.loadError {
                ErrorCard(message: error,
                          retry: { model.reloadFromLocation() },
                          chooseFolder: { model.chooseBrainFolder() },
                          exploreDemo: { model.exploreDemo() })
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.paletteVisible)
        .sheet(isPresented: $model.shortcutsVisible) {
            ShortcutsSheet()
        }
        .sheet(isPresented: $model.contextExportVisible) {
            ContextExportSheet(model: model)
        }
        .sheet(isPresented: $model.enableMCPVisible) {
            EnableMCPSheet(model: model)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .focusedSceneValue(\.appModel, model)
    }
}

// Expose the model to menu commands (⌘K etc.)
struct AppModelKey: FocusedValueKey {
    typealias Value = AppModel
}
extension FocusedValues {
    var appModel: AppModel? {
        get { self[AppModelKey.self] }
        set { self[AppModelKey.self] = newValue }
    }
}

/// First-run / no-brain state: welcoming, and tells a new user exactly
/// how to feed Glia — not just that something failed.
struct ErrorCard: View {
    let message: String
    let retry: () -> Void
    var chooseFolder: () -> Void = {}
    var exploreDemo: () -> Void = {}

    private var dataPath: String {
        JSONFileBrainSource.defaultURL.path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("No brain here yet")
                .font(.system(size: 17, weight: .semibold))
            Text("Glia looks for a graph export at")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(dataPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
                .textSelection(.enabled)
            Text("Point a gbrain exporter there — or any JSON of\n{ nodes: [...], links: [...] } (shape in the README)")
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 400)
            HStack(spacing: 10) {
                Button("Choose Brain Folder…", action: chooseFolder)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                Button("Explore the Demo", action: exploreDemo)
                    .buttonStyle(.bordered)
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .padding(32)
        .panelBackground(cornerRadius: 16)
    }
}
