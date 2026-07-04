import SwiftUI

/// Lightweight markdown rendering for the inspector's content section.
/// Deliberately small: headers, paragraphs with inline styling, list
/// items, and code fences — enough to read a brain page comfortably.
struct MarkdownPreview: View {
    let text: String
    /// Titles already shown by the panel chrome — a leading H1 that
    /// matches any of these is redundant and dropped.
    var redundantHeadings: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
    }

    private var blocks: [String] {
        var out = MarkdownPreview.stripFrontmatter(text)
            .replacingOccurrences(of: "<!--- gbrain:facts:begin -->", with: "")
            .replacingOccurrences(of: "<!--- gbrain:facts:end -->", with: "")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let first = out.first, first.hasPrefix("#") {
            let heading = MarkdownPreview.normalize(
                first.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
            if redundantHeadings.contains(where: { MarkdownPreview.normalize($0) == heading }) {
                out.removeFirst()
            }
        }
        return Array(out.prefix(40))
    }

    nonisolated static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
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
            TableBlock(rows: MarkdownPreview.parseTable(block))
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

    /// Parse a markdown pipe table into header + data rows.
    nonisolated static func parseTable(_ block: String) -> [[String]] {
        block.split(separator: "\n")
            .map { line in
                line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
            .filter { row in
                // drop separator rows (---|---|---)
                !row.allSatisfy { $0.allSatisfy { "-: ".contains($0) } }
            }
    }

    nonisolated static func stripFrontmatter(_ s: String) -> String {
        guard s.hasPrefix("---") else { return s }
        let parts = s.components(separatedBy: "\n---")
        guard parts.count > 1 else { return s }
        return parts.dropFirst().joined(separator: "\n---")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Native rendering for markdown tables. gbrain fact tables (claim/kind/
/// confidence/…) become readable fact rows with chips; anything else falls
/// back to a compact two-column layout. Never a monospace dump.
private struct TableBlock: View {
    let rows: [[String]]

    var body: some View {
        if rows.count > 1 {
            let header = rows[0].map { $0.lowercased() }
            let claimCol = header.firstIndex(of: "claim")
            let kindCol = header.firstIndex(of: "kind")
            let confCol = header.firstIndex(of: "confidence")

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(rows.dropFirst().prefix(12).enumerated()), id: \.offset) { _, row in
                    factRow(row, claimCol: claimCol, kindCol: kindCol, confCol: confCol)
                }
                if rows.count - 1 > 12 {
                    Text("+ \(rows.count - 13) more")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }

    @ViewBuilder
    private func factRow(_ row: [String], claimCol: Int?, kindCol: Int?, confCol: Int?) -> some View {
        // primary text: the claim column, else the longest cell
        let primary = claimCol.flatMap { row.indices.contains($0) ? row[$0] : nil }
            ?? row.max(by: { $0.count < $1.count }) ?? ""
        if !primary.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(Theme.accent.opacity(0.65))
                    .frame(width: 4, height: 4)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(primary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack(spacing: 5) {
                        if let k = kindCol, row.indices.contains(k), !row[k].isEmpty {
                            miniChip(row[k])
                        }
                        if let c = confCol, row.indices.contains(c), !row[c].isEmpty {
                            miniChip("conf \(row[c])")
                        }
                    }
                }
            }
        }
    }

    private func miniChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(.white.opacity(0.07), in: Capsule())
            .foregroundStyle(.tertiary)
    }
}
