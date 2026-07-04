import SwiftUI

/// ⌘K palette: type, arrow, return — the camera flies to the node.
struct CommandPalette: View {
    @Bindable var model: AppModel
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var isSnapshot: Bool {
        ProcessInfo.processInfo.environment["GLIA_SNAPSHOT"] != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            // click-away scrim
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { model.paletteVisible = false }

            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                    if isSnapshot {
                        // AppKit-backed TextField can't render in ImageRenderer
                        Text(model.searchText.isEmpty ? "Search the brain…" : model.searchText)
                            .font(.system(size: 15))
                            .foregroundStyle(model.searchText.isEmpty ? .tertiary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("Search the brain…", text: $model.searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .focused($fieldFocused)
                            .onSubmit { commit() }
                            .onKeyPress(.downArrow) { move(1); return .handled }
                            .onKeyPress(.upArrow) { move(-1); return .handled }
                            .onKeyPress(.escape) { model.paletteVisible = false; return .handled }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                let hits = model.searchHits
                if !hits.isEmpty {
                    Divider().opacity(0.4)
                    if isSnapshot {
                        VStack(spacing: 1) {
                            ForEach(Array(hits.prefix(9).enumerated()), id: \.element.id) { i, hit in
                                row(hit: hit, isHighlighted: i == highlighted)
                            }
                        }
                        .padding(6)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 1) {
                                    ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                                        row(hit: hit, isHighlighted: i == highlighted)
                                            .id(i)
                                            .onTapGesture {
                                                highlighted = i
                                                commit()
                                            }
                                    }
                                }
                                .padding(6)
                            }
                            .frame(maxHeight: 320)
                            .onChange(of: highlighted) { _, new in
                                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(new) }
                            }
                        }
                    }
                }
            }
            .frame(width: 460)
            .panelBackground(cornerRadius: 14)
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
            .padding(.top, 110)
            .onAppear {
                fieldFocused = true
                highlighted = 0
            }
            .onChange(of: model.searchText) { _, _ in highlighted = 0 }
        }
    }

    private func row(hit: AppModel.SearchHit, isHighlighted: Bool) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Theme.swatch(type: hit.node.type))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.node.displayTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(hit.node.slug)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(hit.node.type)
                .font(.system(size: 9.5))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHighlighted ? Theme.accent.opacity(0.22) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        let count = model.searchHits.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    private func commit() {
        let hits = model.searchHits
        guard highlighted < hits.count else { return }
        model.paletteVisible = false
        model.select(index: hits[highlighted].id)
    }
}
