import Foundation
import CoreSpotlight

/// Indexes brain pages into system Spotlight: your knowledge is findable
/// from anywhere on the Mac, and results deep-link back into the graph.
@MainActor
enum SpotlightIndexer {
    private static var lastIndexedStamp = ""

    static func reindex(graph: BrainGraph) {
        guard graph.generatedAt != lastIndexedStamp, !graph.nodes.isEmpty else { return }
        lastIndexedStamp = graph.generatedAt

        // (title, description, keywords, id) — Sendable payload for the
        // background indexing task; CSSearchableItem itself is not Sendable.
        let payload = graph.nodes.map { node in
            (node.title.isEmpty ? node.slug : node.title,
             "\(node.type) · \(node.slug) · \(node.source) brain",
             [node.type, node.source, "gbrain", "glia"],
             node.id)
        }

        Task.detached(priority: .utility) {
            let items = payload.map { title, desc, keywords, id in
                let attrs = CSSearchableItemAttributeSet(contentType: .text)
                attrs.title = title
                attrs.contentDescription = desc
                attrs.keywords = keywords
                return CSSearchableItem(
                    uniqueIdentifier: "node:\(id)",
                    domainIdentifier: "ai.glia.pages",
                    attributeSet: attrs)
            }
            let index = CSSearchableIndex.default()
            try? await index.deleteSearchableItems(withDomainIdentifiers: ["ai.glia.pages"])
            var start = 0
            while start < items.count {
                let end = min(start + 1000, items.count)
                try? await index.indexSearchableItems(Array(items[start..<end]))
                start = end
            }
        }
    }
}
