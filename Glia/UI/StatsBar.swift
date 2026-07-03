import SwiftUI

/// The header strip: identity + the numbers that say the brain is alive.
struct StatsBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text("Glia")
                    .font(.system(size: 13, weight: .semibold))
            }

            if !model.graph.nodes.isEmpty {
                stat("\(model.graph.nodes.count.formatted())", "pages")
                stat("\(model.graph.links.count.formatted())", "links")
                stat("\(model.updatedTodayCount.formatted())", "updated today")
                stat("\(model.visibleCount.formatted())", "shown")
                if model.isSettling {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("settling…").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button {
                model.paletteVisible = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10))
                    Text("Search").font(.caption)
                    Text("⌘K").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.white.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Theme.background.opacity(0.9), Theme.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}
