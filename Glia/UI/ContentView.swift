import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            GraphView(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                StatsBar(model: model)
                Spacer()
            }

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
                ErrorCard(message: error) { model.start() }
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.paletteVisible)
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

struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
