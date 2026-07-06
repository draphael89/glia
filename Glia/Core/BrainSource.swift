import Foundation

/// Seam between Glia and any brain backend. v1 ships the JSON-export
/// adapter; a gbrain ops-contract client (`export_graph` /
/// `get_brain_identity`) slots in behind the same protocol later.
protocol BrainSource: Sendable {
    /// One immutable snapshot of the whole graph.
    func loadGraph() async throws -> BrainGraph
    /// Emits a fresh snapshot whenever the backend content changes.
    /// The stream never emits identical consecutive snapshots.
    func updates() -> AsyncStream<BrainGraph>
}

// MARK: - JSON export adapter

/// Reads the graph.json written by gbrain-viz-export.py (atomic swap),
/// re-reading on file change (DispatchSource) with a slow poll as backstop.
final class JSONFileBrainSource: BrainSource {
    private let url: URL

    init(url: URL) { self.url = url }

    @MainActor
    static var defaultURL: URL {
        BrainLocation.graphURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gbrain/viz/graph.json")
    }

    func loadGraph() async throws -> BrainGraph {
        let url = self.url
        return try await Task.detached(priority: .userInitiated) {
            try Self.parse(Data(contentsOf: url))
        }.value
    }

    func updates() -> AsyncStream<BrainGraph> {
        let url = self.url
        return AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                // Cheap on-disk signature (sub-second mtime + size). Two things ride on it:
                //  • skip the read + O(V+E) decode/index-rebuild entirely when the file is
                //    unchanged — otherwise an all-day viewer rebuilds the whole graph every
                //    10s forever just to discard it on the stamp check;
                //  • detect a change by CONTENT, not the writer's second-granular
                //    generatedAt string, so a same-second re-export isn't silently dropped.
                func signature() -> String? {
                    guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
                          let m = a[.modificationDate] as? Date, let s = a[.size] as? Int
                    else { return nil }
                    return "\(m.timeIntervalSinceReferenceDate)|\(s)"
                }
                // Seed from the file loadGraph() already read, so the first poll doesn't
                // re-yield the just-applied snapshot (a redundant re-settle ~10s post-load).
                var lastSig = signature()
                var lastStamp = ""
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    let sig = signature()
                    if let sig, sig == lastSig { continue }   // unchanged on disk — no work
                    lastSig = sig
                    guard let data = try? Data(contentsOf: url),
                          let graph = try? Self.parse(data),
                          graph.generatedAt != lastStamp else { continue }
                    lastStamp = graph.generatedAt
                    continuation.yield(graph)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: parsing

    private struct Payload: Codable {
        let generated_at: String
        let nodes: [BrainNode]
        let links: [BrainLink]
    }

    static func parse(_ data: Data) throws -> BrainGraph {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        return BrainGraph(generatedAt: p.generated_at, nodes: p.nodes, links: p.links)
    }
}
