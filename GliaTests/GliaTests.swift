import XCTest
import simd
@testable import Glia

final class BrainGraphTests: XCTestCase {
    private func node(_ id: Int, _ slug: String) -> BrainNode {
        BrainNode(id: id, slug: slug, type: "note", source: "default",
                  title: slug, created: "2026-06-01", updated: "2026-06-01T00:00:00Z")
    }

    func testDuplicateLinksCollapse() {
        let g = BrainGraph(
            generatedAt: "t",
            nodes: [node(1, "a"), node(2, "b")],
            links: [
                BrainLink(source: 1, target: 2, type: "mentions"),
                BrainLink(source: 1, target: 2, type: "mentions"),
                BrainLink(source: 2, target: 1, type: "mentions"),   // reverse dup
            ])
        XCTAssertEqual(g.links.count, 1)
        XCTAssertEqual(g.degree, [1, 1])
        XCTAssertEqual(g.neighbors[0], [1])
        XCTAssertEqual(g.neighbors[1], [0])
    }

    func testDanglingAndSelfLinksDropped() {
        let g = BrainGraph(
            generatedAt: "t",
            nodes: [node(1, "a")],
            links: [
                BrainLink(source: 1, target: 1, type: "self"),
                BrainLink(source: 1, target: 99, type: "dangling"),
            ])
        XCTAssertTrue(g.links.isEmpty)
        XCTAssertEqual(g.degree, [0])
    }
}

final class CameraTests: XCTestCase {
    func testAnchoredZoomKeepsWorldPointUnderCursor() {
        var cam = Camera()
        cam.center = SIMD2(10, -4)
        cam.zoom = 3
        let viewport = SIMD2<Float>(1200, 800)
        let anchor = SIMD2<Float>(300, 550)
        let worldBefore = cam.viewToWorld(anchor, viewport: viewport)
        cam.zoom(by: 1.7, anchorView: anchor, viewport: viewport)
        let worldAfter = cam.viewToWorld(anchor, viewport: viewport)
        XCTAssertLessThan(simd_length(worldBefore - worldAfter), 0.001)
    }

    func testRoundTripTransform() {
        var cam = Camera()
        cam.center = SIMD2(-3, 7)
        cam.zoom = 12
        let viewport = SIMD2<Float>(1000, 700)
        let p = SIMD2<Float>(123, 456)
        let back = cam.worldToView(cam.viewToWorld(p, viewport: viewport), viewport: viewport)
        XCTAssertLessThan(simd_length(p - back), 0.001)
    }
}

final class LayoutEngineTests: XCTestCase {
    private func chain(_ n: Int) -> BrainGraph {
        let nodes = (0..<n).map {
            BrainNode(id: $0, slug: "n\($0)", type: "note", source: "default",
                      title: "n\($0)", created: "2026-06-01", updated: "2026-06-01T00:00:00Z")
        }
        let links = (1..<n).map { BrainLink(source: $0 - 1, target: $0, type: "l") }
        return BrainGraph(generatedAt: "t", nodes: nodes, links: links)
    }

    func testSeedingIsDeterministic() {
        let g = chain(50)
        XCTAssertEqual(LayoutEngine.seedPositions(for: g),
                       LayoutEngine.seedPositions(for: g))
    }

    func testSettleBringsLinkedNodesTowardSpringLength() {
        let g = chain(30)
        var config = LayoutEngine.Config()
        config.maxIterations = 400
        let final = LayoutEngine.settle(graph: g,
                                        start: LayoutEngine.seedPositions(for: g),
                                        config: config)
        var total: Float = 0
        for (s, t) in g.linkIndices {
            total += simd_length(final[Int(s)] - final[Int(t)])
        }
        let mean = total / Float(g.linkIndices.count)
        // settled chain spacing should be within 3x of the spring rest length
        XCTAssertLessThan(mean, config.springLength * 3)
        XCTAssertGreaterThan(mean, config.springLength * 0.3)
    }

    func testInsertionSeedsAtNeighborBarycenter() {
        let g = chain(3)   // 0-1-2
        let placed: [Int: SIMD2<Float>] = [0: SIMD2(0, 0), 2: SIMD2(10, 0)]
        let seeded = LayoutEngine.seedInsertions(graph: g, placed: placed)
        // node 1 links to both placed nodes -> lands near (5, 0)
        XCTAssertLessThan(simd_length(seeded[1] - SIMD2(5, 0)), 10)
    }
}

final class LabelTests: XCTestCase {
    func testRepeatedDatePrefixCollapses() {
        XCTAssertEqual(
            LabelOverlay.collapseRepeatedDatePrefix("2026 06 29 2026 06 29 Athena Kick-Off"),
            "2026 06 29 Athena Kick-Off")
    }

    func testSingleDatePrefixUntouched() {
        XCTAssertEqual(
            LabelOverlay.collapseRepeatedDatePrefix("2026-06-06 — Daily Brief"),
            "2026-06-06 — Daily Brief")
        XCTAssertEqual(
            LabelOverlay.collapseRepeatedDatePrefix("Athena Kick-Off"),
            "Athena Kick-Off")
    }
}

final class MarkdownTests: XCTestCase {
    func testFrontmatterStripped() {
        let s = "---\ntype: note\ntitle: X\n---\n\n# Hello\nBody"
        let out = MarkdownPreview.stripFrontmatter(s)
        XCTAssertFalse(out.contains("type: note"))
        XCTAssertTrue(out.contains("# Hello"))
    }

    func testNoFrontmatterPassthrough() {
        let s = "# Just content"
        XCTAssertEqual(MarkdownPreview.stripFrontmatter(s), s)
    }
}
