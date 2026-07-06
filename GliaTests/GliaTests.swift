import XCTest
import simd
// Hostless test bundle: app sources are compiled directly into this target
// (see project.yml), so there is no separate Glia module to import.

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

    // Guards the bug CLASS that four audit rounds kept surfacing: cross-poll state
    // (selection, hover, replay blooms) must be remapped by STABLE node.id, never
    // by array index — because a poll re-parses the whole graph in fresh JSON order.
    func testIndexByIDReflectsNodeOrderSoIdRemapSurvivesReorder() {
        // Same three pages, but a later poll returns them in a DIFFERENT order
        // (e.g. a new page inserted ahead shifts everyone's array index).
        let first = BrainGraph(generatedAt: "1",
            nodes: [node(10, "a"), node(20, "b"), node(30, "c")], links: [])
        let reordered = BrainGraph(generatedAt: "2",
            nodes: [node(20, "b"), node(30, "c"), node(10, "a")], links: [])

        // The user had node id=10 selected — at index 0 in `first`.
        XCTAssertEqual(first.indexByID[10], 0)
        // After the reorder, INDEX 0 is a different page (id=20) — an index-keyed
        // selection would silently jump. The id remap must land back on id=10.
        XCTAssertEqual(reordered.nodes[0].id, 20)                 // index 0 moved
        XCTAssertEqual(reordered.indexByID[10], 2)                // id 10 is now index 2
        XCTAssertEqual(reordered.nodes[reordered.indexByID[10]!].slug, "a")  // same page
    }

    func testIndexByIDDropsRemovedNodeSoRemapClears() {
        let before = BrainGraph(generatedAt: "1",
            nodes: [node(10, "a"), node(20, "b")], links: [])
        let after = BrainGraph(generatedAt: "2", nodes: [node(20, "b")], links: [])
        XCTAssertNotNil(before.indexByID[10])
        // A poll that removed the selected page → id absent → remap yields nil
        // (selection correctly cleared, not pointed at the wrong node).
        XCTAssertNil(after.indexByID[10])
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

    /// A snapshot smaller than 2×padding must not yield a negative/zero zoom (which
    /// point-mirrors or collapses the PNG the CI/agent visual check depends on).
    @MainActor func testFittingCameraClampsZoomPositiveForTinySnapshot() {
        let positions = [SIMD2<Float>(-50, -50), SIMD2<Float>(50, 50), SIMD2<Float>(0, 20)]
        // size (400×260) is smaller than 2×padding (320) in height → unclamped usable < 0
        let cam = GraphRenderer.fittingCamera(
            positions: positions, visible: [], size: CGSize(width: 400, height: 260), padding: 160)
        XCTAssertGreaterThan(cam.zoom, 0, "zoom must stay positive so the snapshot isn't mirrored")
        XCTAssertGreaterThanOrEqual(cam.zoom, 0.05)
        XCTAssertLessThanOrEqual(cam.zoom, 60)
        XCTAssertEqual(cam.center.x, 0, accuracy: 0.001)   // centered on the span midpoint
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
            "2026 06 29 2026 06 29 Athena Kick-Off".collapsedDatePrefix,
            "2026 06 29 Athena Kick-Off")
    }

    func testSingleDatePrefixUntouched() {
        XCTAssertEqual("2026-06-06 — Daily Brief".collapsedDatePrefix,
                       "2026-06-06 — Daily Brief")
        XCTAssertEqual("Athena Kick-Off".collapsedDatePrefix, "Athena Kick-Off")
    }

    func testDisplayTitleHumanizesSlugEchoes() {
        func node(slug: String, title: String) -> BrainNode {
            BrainNode(id: 1, slug: slug, type: "concept", source: "default",
                      title: title, created: "2026-06-01", updated: "2026-06-01T00:00:00Z")
        }
        XCTAssertEqual(node(slug: "people-david", title: "people-david").displayTitle, "David")
        XCTAssertEqual(node(slug: "granola-ingest-process", title: "").displayTitle,
                       "Granola Ingest Process")
        // real titles pass through untouched
        XCTAssertEqual(node(slug: "companies/fountain", title: "Company — Fountain").displayTitle,
                       "Company — Fountain")
        // hash suffixes drop from date-slugged notes
        XCTAssertEqual(node(slug: "2026-03-16-david-rob-i4ktq6df", title: "").displayTitle,
                       "2026 03 16 David Rob")
    }

    @MainActor
    func testSourceMirrorRejectsPathEscapes() {
        // slug/source strings come from external data — traversal must fail
        XCTAssertNil(BrainLocation.sourceMirror(for: "../evil"))
        XCTAssertNil(BrainLocation.sourceMirror(for: "a/b"))
        XCTAssertNil(BrainLocation.sourceMirror(for: "ea; rm -rf"))
        XCTAssertNotNil(BrainLocation.sourceMirror(for: "default"))
        XCTAssertNotNil(BrainLocation.sourceMirror(for: "ea"))
    }

    @MainActor
    func testUpdaterDisabledWithoutFeed() {
        // No SUFeedURL in the test bundle's Info.plist -> updater must be off.
        XCTAssertFalse(UpdaterModel.shared.isEnabled)
    }

    func testContextBundleTokenEstimate() {
        let b = ContextBundle(text: String(repeating: "x", count: 4000), pageCount: 3)
        XCTAssertEqual(b.tokenEstimate, 1000)
        XCTAssertEqual(b.pageCount, 3)
    }

    func testIdentityTypesExcludeProvenance() {
        XCTAssertTrue(ContextBundle.identityTypes.contains("person"))
        XCTAssertTrue(ContextBundle.identityTypes.contains("concept"))
        XCTAssertFalse(ContextBundle.identityTypes.contains("atom"))
        XCTAssertFalse(ContextBundle.identityTypes.contains("source"))
    }

    func testContextScopesIncludeCollection() {
        // collection is the first (default-preferred) scope for curated export
        XCTAssertEqual(ContextScope.allCases.first, .collection)
        XCTAssertEqual(ContextScope.collection.label, "My collection (starred)")
    }

    func testIdentityRankFrontLoadsSelfThenEssays() {
        func n(_ slug: String, _ type: String) -> BrainNode {
            BrainNode(id: 1, slug: slug, type: type, source: "default",
                      title: slug, created: "2026-06-01", updated: "2026-06-01T00:00:00Z")
        }
        let selfPage = ContextBundle.identityRank(n("people-david", "concept"))
        let essay = ContextBundle.identityRank(n("originals/telos-is-velocity", "original"))
        let concept = ContextBundle.identityRank(n("concepts/legibility", "concept"))
        let note = ContextBundle.identityRank(n("notes/some-note", "note"))
        XCTAssertLessThan(selfPage, essay)
        XCTAssertLessThan(essay, concept)
        XCTAssertLessThan(concept, note)
    }

    func testTableParsing() {
        let table = "| # | claim | kind |\n|---|-------|------|\n| 1 | David likes X | preference |"
        let rows = MarkdownPreview.parseTable(table)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0][1], "claim")
        XCTAssertEqual(rows[1][1], "David likes X")
        XCTAssertEqual(rows[1][2], "preference")
    }
}

final class TraversalMathTests: XCTestCase {
    func testDirectionalScoringPrefersOnAxisNeighbor() {
        // pure math mirror of AppModel.step: dot(normalized delta, direction)
        let origin = SIMD2<Float>(0, 0)
        let right = SIMD2<Float>(10, 1)
        let up = SIMD2<Float>(0.5, -8)
        let dir = SIMD2<Float>(1, 0)
        func score(_ p: SIMD2<Float>) -> Float {
            let d = p - origin
            return simd_dot(d / simd_length(d), dir)
        }
        XCTAssertGreaterThan(score(right), 0.9)
        XCTAssertLessThan(score(up), 0.25)
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

    func testHeadingNormalization() {
        // "# people-david" should be recognized as redundant with slug
        // "people-david" and displayTitle "David" comparisons happen on
        // normalized forms
        XCTAssertEqual(MarkdownPreview.normalize("people-david"), "peopledavid")
        XCTAssertEqual(MarkdownPreview.normalize("People David"), "peopledavid")
        XCTAssertNotEqual(MarkdownPreview.normalize("Company — Fountain"),
                          MarkdownPreview.normalize("Fountain"))
    }
}

// MARK: - Psyche sync status (Phase 2 pure seams)

final class PsycheSyncTests: XCTestCase {
    func testRelativeTimeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(relativePsycheTime(now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(relativePsycheTime(now.addingTimeInterval(-120), now: now), "2m ago")
        XCTAssertEqual(relativePsycheTime(now.addingTimeInterval(-7200), now: now), "2h ago")
        XCTAssertEqual(relativePsycheTime(now.addingTimeInterval(-172_800), now: now), "2d ago")
    }

    func testFileStateMirrorsServerGate() {
        // missing file → MCP falls back to building from source
        var s = PsycheSyncStatus()
        XCTAssertEqual(s.fileState, .missing)
        XCTAssertFalse(s.mcpWillUseFile)
        // present but ≤200 bytes → thin (server's loadPsyche rejects it)
        s.fileModified = .now; s.fileBytes = 200
        XCTAssertEqual(s.fileState, .thin)
        XCTAssertFalse(s.mcpWillUseFile)
        // present and >200 bytes → usable (server injects it)
        s.fileBytes = 201
        XCTAssertEqual(s.fileState, .usable)
        XCTAssertTrue(s.mcpWillUseFile)
    }

    func testSourceLabels() {
        XCTAssertEqual(PsycheSyncStatus.Source.collection.label, "starred collection")
        XCTAssertEqual(PsycheSyncStatus.Source.identity.label, "identity map")
        XCTAssertEqual(PsycheSyncStatus.Source.custom.label, "custom scope")
    }
}

// MARK: - MCP provisioning: config merge must never clobber (Phase 3)

final class MCPProvisionTests: XCTestCase {
    private func json(_ obj: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: obj) }
    private func parse(_ d: Data?) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: d ?? Data())) as? [String: Any] ?? [:]
    }

    func testMergePreservesOtherKeysAndSiblingServers() {
        let existing = json([
            "coworkUserFilesPath": "/tmp/x",
            "preferences": ["theme": "dark"],
            "mcpServers": ["other": ["command": "foo", "args": ["bar"]]],
        ])
        let out = MCPProvision.mergeDesktopConfig(existing: existing,
                                                  node: "/opt/homebrew/bin/node",
                                                  dist: "/x/dist/index.js")
        let root = parse(out)
        XCTAssertEqual(root["coworkUserFilesPath"] as? String, "/tmp/x")   // preserved
        XCTAssertNotNil(root["preferences"])                               // preserved
        let servers = root["mcpServers"] as! [String: Any]
        XCTAssertNotNil(servers["other"])                                  // sibling server preserved
        let glia = servers["glia-context"] as! [String: Any]
        XCTAssertEqual(glia["command"] as? String, "/opt/homebrew/bin/node")
        XCTAssertEqual((glia["args"] as? [String])?.first, "/x/dist/index.js")
    }

    func testMergeIntoNilCreatesServer() {
        let servers = parse(MCPProvision.mergeDesktopConfig(existing: nil, node: "/n", dist: "/d"))["mcpServers"] as! [String: Any]
        XCTAssertNotNil(servers["glia-context"])
    }

    func testCorruptExistingIsDetected() {
        let corrupt = Data("not json {".utf8)
        XCTAssertFalse(MCPProvision.isParseableJSON(corrupt))
        // merge still yields a valid config (caller backs up + aborts on corrupt)
        let out = MCPProvision.mergeDesktopConfig(existing: corrupt, node: "/n", dist: "/d")
        XCTAssertTrue(MCPProvision.isParseableJSON(out ?? Data()))
    }
}

// MARK: - MCPProvision.runProcess (Phase 3 fix regression guards)

final class MCPProcessTests: XCTestCase {
    func testRunProcessCapturesOutput() async {
        let r = await MCPProvision.runProcess(URL(fileURLWithPath: "/bin/echo"), ["hello-glia"])
        XCTAssertEqual(r.status, 0)
        XCTAssertTrue(r.stdout.contains("hello-glia"))
    }

    func testRunProcessDoesNotHangWhenGrandchildHoldsPipe() async {
        // Regression for the code-review finding: a fast-exiting child that
        // leaves a grandchild holding the stdout pipe must NOT hang runProcess —
        // the timeout bounds the drain rather than waiting for EOF.
        let start = Date()
        let r = await MCPProvision.runProcess(URL(fileURLWithPath: "/bin/sh"),
                                              ["-c", "sleep 5 & echo started"], timeout: 1)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 4, "runProcess must return ~timeout, not wait for the grandchild")
        XCTAssertTrue(r.stderr.contains("timed out") || r.stdout.contains("started"))
    }
}

final class MarkdownPreviewTests: XCTestCase {
    func testCodeBodyStripsLangAndFence() {
        // round-8 audit: the ```lang info string was rendered as the first code line
        XCTAssertEqual(MarkdownPreview.codeBody("```swift\nlet x = 1\n```"), "let x = 1")
        XCTAssertEqual(MarkdownPreview.codeBody("```\nplain\n```"), "plain")
        XCTAssertEqual(MarkdownPreview.codeBody("```ts\na\n\nb\n```"), "a\n\nb")  // internal blank line kept
    }

    func testParseTablePreservesEmptyLeadingCell() {
        // round-8 audit: a char-set trim swallowed empty edge cells, shifting columns
        let rows = MarkdownPreview.parseTable("| claim | kind | confidence |\n|  | preference | 0.9 |")
        XCTAssertEqual(rows.first, ["claim", "kind", "confidence"])
        XCTAssertEqual(rows.last, ["", "preference", "0.9"])   // empty first cell preserved
    }
}

final class ContextBundleTests: XCTestCase {
    private func node(_ id: Int, slug: String, source: String) -> BrainNode {
        BrainNode(id: id, slug: slug, type: "company", source: source,
                  title: "", created: "2026-06-01", updated: "2026-06-01T00:00:00Z")
    }

    func testURLIsInsideRejectsSiblingPrefixDir() {
        // Regression for the round-14 audit: a raw hasPrefix let a sibling dir whose
        // name shares the prefix (source-foobar vs source-foo) escape the guard.
        let base = URL(fileURLWithPath: "/Users/x/.gbrain/source-foo")
        XCTAssertTrue(base.isInside(base))                                               // the dir itself
        XCTAssertTrue(URL(fileURLWithPath: "/Users/x/.gbrain/source-foo/people/david.md").isInside(base))
        XCTAssertFalse(URL(fileURLWithPath: "/Users/x/.gbrain/source-foobar/secret.md").isInside(base)) // sibling
        XCTAssertFalse(URL(fileURLWithPath: "/Users/x/.gbrain/other/x.md").isInside(base))
    }

    func testBuildDedupsBySlugAcrossSources() throws {
        // Regression for the round-7 audit: a slug present in two enabled sources
        // was injected twice (wasted budget, inflated pageCount). Must emit once.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("glia-cbtest-\(getpid())")
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try "# Fountain\n\nreal body content for the page".write(
            to: dir.appendingPathComponent("companies-fountain.md"), atomically: true, encoding: .utf8)

        let nodes = [node(1, slug: "companies-fountain", source: "principal"),
                     node(2, slug: "companies-fountain", source: "ea")]   // same slug, two sources
        let bundle = ContextBundle.build(nodes: nodes, header: "test",
                                         mirrors: ["principal": dir, "ea": dir])
        XCTAssertEqual(bundle.pageCount, 1, "duplicate slug must be emitted once")
        // the section marker must appear exactly once
        let occurrences = bundle.text.components(separatedBy: "· companies-fountain*").count - 1
        XCTAssertEqual(occurrences, 1)
    }
}
