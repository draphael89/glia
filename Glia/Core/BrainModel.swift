import Foundation

/// A page in the brain. `id` is the backend's stable integer id;
/// `index` (position in `BrainGraph.nodes`) is what the render/layout
/// pipeline uses everywhere for cache-friendly array access.
struct BrainNode: Identifiable, Hashable, Sendable, Codable {
    let id: Int
    let slug: String
    let type: String
    let source: String
    let title: String
    let created: String        // "YYYY-MM-DD" from the export
    let updated: String        // ISO8601

    var createdDate: Date? { BrainDates.parseDay(created) }
    var updatedDate: Date? { BrainDates.parseISO(updated) }

    /// Human-facing name. Pages whose title is missing or just echoes the
    /// slug get a humanized form: "people-david" → "David",
    /// "granola-ingest-process" → "Granola Ingest Process".
    var displayTitle: String {
        if !title.isEmpty && title != slug {
            return title.collapsedDatePrefix
        }
        var tail = String(slug.split(separator: "/").last ?? "")
        for prefix in ["people-", "projects-", "companies-", "clients-"]
        where tail.hasPrefix(prefix) && tail.count > prefix.count {
            tail = String(tail.dropFirst(prefix.count))
        }
        // date-slugged pages keep their date; hash suffixes drop
        let words = tail.split(separator: "-").filter { part in
            // drop 8-char base36 hash suffixes ("i4ktq6df"): digits don't
            // count as lowercase, so test letter-case and digit separately
            !(part.count == 8
              && part.allSatisfy { ($0.isLetter && $0.isLowercase) || $0.isNumber }
              && part.contains(where: \.isNumber)
              && part.contains(where: \.isLetter))
        }
        return words.map { w -> String in
            let s = String(w)
            return s.allSatisfy(\.isNumber) ? s : s.prefix(1).uppercased() + s.dropFirst()
        }.joined(separator: " ")
    }
}

struct BrainLink: Hashable, Sendable, Codable {
    let source: Int            // BrainNode.id
    let target: Int            // BrainNode.id
    let type: String
}

/// An immutable snapshot of the whole brain, plus the index structures
/// every downstream consumer needs. Built off the main thread.
struct BrainGraph: Sendable {
    let generatedAt: String
    let nodes: [BrainNode]
    let links: [BrainLink]

    /// node.id -> index into `nodes`
    let indexByID: [Int: Int]
    /// links expressed as (sourceIndex, targetIndex) pairs
    let linkIndices: [(Int32, Int32)]
    /// degree per node index
    let degree: [Int]
    /// adjacency (node index -> neighbor node indices)
    let neighbors: [[Int32]]

    static let empty = BrainGraph(generatedAt: "", nodes: [], links: [])

    init(generatedAt: String, nodes: [BrainNode], links: [BrainLink]) {
        self.generatedAt = generatedAt
        self.nodes = nodes

        var byID = [Int: Int](minimumCapacity: nodes.count)
        for (i, n) in nodes.enumerated() { byID[n.id] = i }
        self.indexByID = byID

        var pairs: [(Int32, Int32)] = []
        pairs.reserveCapacity(links.count)
        var deg = [Int](repeating: 0, count: nodes.count)
        var adj = [[Int32]](repeating: [], count: nodes.count)
        var kept: [BrainLink] = []
        kept.reserveCapacity(links.count)
        var seenPairs = Set<Int64>()
        for l in links {
            guard let s = byID[l.source], let t = byID[l.target], s != t else { continue }
            // collapse duplicate link rows (same pair, any direction)
            let key = Int64(min(s, t)) << 32 | Int64(max(s, t))
            guard seenPairs.insert(key).inserted else { continue }
            kept.append(l)
            pairs.append((Int32(s), Int32(t)))
            deg[s] += 1; deg[t] += 1
            adj[s].append(Int32(t)); adj[t].append(Int32(s))
        }
        self.links = kept
        self.linkIndices = pairs
        self.degree = deg
        self.neighbors = adj
    }
}

extension String {
    /// Some ingested titles carry a doubled date prefix
    /// ("2026 06 29 2026 06 29 Athena Kick-Off") — collapse the repeat.
    /// Presentation-only; the underlying data is untouched.
    var collapsedDatePrefix: String {
        let pattern = /^((20\d{2})[ \-\/](\d{2})[ \-\/](\d{2}))[ \-]+\1[ \-]*/
        if let match = prefixMatch(of: pattern) {
            return String(match.output.1) + " " +
                self[match.range.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        return self
    }
}

enum BrainDates {
    // DateFormatter/ISO8601DateFormatter are documented thread-safe on
    // modern OS versions but aren't marked Sendable; parse via the
    // Sendable FormatStyle APIs instead.
    nonisolated static func parseDay(_ s: String) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    nonisolated static func parseISO(_ s: String) -> Date? {
        try? Date(s, strategy: .iso8601)
    }
}
