import SwiftUI

/// ⌘/ — the app's keyboard language on one card.
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let rows: [(String, String)] = [
        ("⌘K", "Search the brain — return flies to the result"),
        ("← ↑ ↓ →", "Walk to a connected node"),
        ("Space", "Quick Look the selected page"),
        ("Click / Double-click", "Select / fly to a node"),
        ("Pinch · Scroll", "Zoom · pan the canvas"),
        ("⌘+ / ⌘− / ⌘0", "Zoom in / out / fit"),
        ("F · ⇧⌘F", "Fit view"),
        ("Esc", "Clear selection, exit search"),
        ("⌘O", "Choose brain folder"),
        ("⇧⌘E", "Export snapshot as PNG"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keyboard & Gestures")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(rows, id: \.0) { key, what in
                    GridRow {
                        Text(key)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .gridColumnAlignment(.trailing)
                        Text(what)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 400)
        .background(Theme.background)
    }
}
