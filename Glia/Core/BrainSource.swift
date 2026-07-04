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

    static var defaultURL: URL {
        // GLIA_DATA overrides the export location (useful for demo data,
        // testing, and non-default gbrain homes).
        if let override = ProcessInfo.processInfo.environment["GLIA_DATA"] {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
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
                var lastStamp = ""
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
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
