import SwiftUI

/// Slide-in detail card for the selected node.
struct InspectorPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        if let node = model.selectedNode, let index = model.selectedIndex {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.displayTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(3)
                        Text(node.slug)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        model.clearFocus()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }

                HStack(spacing: 6) {
                    chip(node.type, color: Theme.swatch(type: node.type))
                    chip(node.source, color: node.source == "ea"
                         ? Color(red: 0.22, green: 0.74, blue: 0.97) : Theme.accent)
                    Spacer()
                }

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("created").foregroundStyle(.tertiary)
                        Text(node.created)
                    }
                    GridRow {
                        Text("updated").foregroundStyle(.tertiary)
                        Text(String(node.updated.prefix(10)))
                    }
                    GridRow {
                        Text("links").foregroundStyle(.tertiary)
                        Text("\(model.graph.degree[index])")
                    }
                }
                .font(.system(size: 11))

                if let markdown = model.selectedMarkdown {
                    Divider().opacity(0.4)
                    Text("PAGE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .kerning(0.8)
                    scrollableUnlessSnapshot(maxHeight: 240) {
                        MarkdownPreview(text: markdown,
                                        redundantHeadings: [node.slug, node.title, node.displayTitle])
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                let neighbors = model.graph.neighbors[index]
                if !neighbors.isEmpty {
                    Divider().opacity(0.4)
                    Text("CONNECTED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .kerning(0.8)
                    scrollableUnlessSnapshot(maxHeight: 200) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(neighbors.prefix(40), id: \.self) { nb in
                                let j = Int(nb)
                                let neighbor = model.graph.nodes[j]
                                Button {
                                    model.select(index: j)
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Theme.swatch(type: neighbor.type))
                                            .frame(width: 5, height: 5)
                                        Text(neighbor.displayTitle)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if node.source == "default" && !node.slug.hasPrefix("atoms/") {
                    Divider().opacity(0.4)
                    Button {
                        openInObsidian(slug: node.slug)
                    } label: {
                        Label("Open in Obsidian", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(14)
            .frame(width: 300, alignment: .leading)
            .panelBackground()
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// ScrollView content doesn't render under ImageRenderer, so snapshot
    /// mode (agent verification) uses a flat, height-capped stack instead.
    @ViewBuilder
    private func scrollableUnlessSnapshot<Content: View>(
        maxHeight: CGFloat, @ViewBuilder content: () -> Content
    ) -> some View {
        if ProcessInfo.processInfo.environment["GLIA_SNAPSHOT"] != nil {
            content().frame(maxHeight: maxHeight * 1.6, alignment: .top).clipped()
        } else {
            ScrollView { content() }.frame(maxHeight: maxHeight)
        }
    }

    private func chip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private func openInObsidian(slug: String) {
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? slug
        if let url = URL(string: "obsidian://open?vault=source-default&file=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}
