import SwiftUI

/// Lightweight markdown rendering for the inspector's content section.
/// Deliberately small: headers, paragraphs with inline styling, list
/// items, and code fences — enough to read a brain page comfortably.
struct MarkdownPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
    }

    private var blocks: [String] {
        MarkdownPreview.stripFrontmatter(text)
            .replacingOccurrences(of: "<!--- gbrain:facts:begin -->", with: "")
            .replacingOccurrences(of: "<!--- gbrain:facts:end -->", with: "")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(40).map { String($0) }
    }

    @ViewBuilder
    private func render(_ block: String) -> some View {
        if block.hasPrefix("#") {
            let level = block.prefix(while: { $0 == "#" }).count
            let title = block.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            Text(title)
                .font(.system(size: level <= 1 ? 13 : 12, weight: .semibold))
                .padding(.top, 3)
        } else if block.hasPrefix("```") {
            Text(block.trimmingCharacters(in: CharacterSet(charactersIn: "`\n")))
                .font(.system(size: 10, design: .monospaced))
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        } else if block.hasPrefix("|") {
            // tables render as monospace — a fact table stays scannable
            Text(block)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(14)
        } else {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true)
            VStack(alignment: .leading, spacing: 2.5) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    inlineText(String(line))
                }
            }
        }
    }

    private func inlineText(_ raw: String) -> some View {
        let isBullet = raw.hasPrefix("- ") || raw.hasPrefix("* ")
        let content = isBullet ? String(raw.dropFirst(2)) : raw
        let attr = (try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(content)
        return HStack(alignment: .top, spacing: 5) {
            if isBullet {
                Text("•").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Text(attr)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    static func stripFrontmatter(_ s: String) -> String {
        guard s.hasPrefix("---") else { return s }
        let parts = s.components(separatedBy: "\n---")
        guard parts.count > 1 else { return s }
        return parts.dropFirst().joined(separator: "\n---")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
