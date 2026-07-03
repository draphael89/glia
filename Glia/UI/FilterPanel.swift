import SwiftUI

/// Floating filter card: sources, orphans, and the type legend
/// (legend rows double as toggles).
struct FilterPanel: View {
    @Bindable var model: AppModel
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.25)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text("Filters")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if !collapsed {
                Toggle(isOn: $model.hideOrphans) {
                    Text("Hide unlinked").font(.system(size: 11))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                if model.allSources.count > 1 {
                    Divider().opacity(0.4)
                    ForEach(model.allSources, id: \.self) { source in
                        toggleRow(
                            label: source,
                            color: source == "ea" ? Color(red: 0.22, green: 0.74, blue: 0.97) : Theme.accent,
                            isOn: model.enabledSources.contains(source)
                        ) { on in
                            if on { model.enabledSources.insert(source) }
                            else { model.enabledSources.remove(source) }
                        }
                    }
                }

                Divider().opacity(0.4)
                ForEach(model.typeCounts, id: \.type) { entry in
                    toggleRow(
                        label: entry.type,
                        detail: entry.count.formatted(),
                        color: Theme.swatch(type: entry.type),
                        isOn: model.enabledTypes.contains(entry.type)
                    ) { on in
                        if on { model.enabledTypes.insert(entry.type) }
                        else { model.enabledTypes.remove(entry.type) }
                    }
                }

                Divider().opacity(0.4)
                Button {
                    model.fitView()
                } label: {
                    Label("Fit view", systemImage: "scope")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 172, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.07)))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func toggleRow(label: String, detail: String? = nil, color: Color,
                           isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        Button { action(!isOn) } label: {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                    .opacity(isOn ? 1 : 0.25)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(isOn ? .primary : .tertiary)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.quaternary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
