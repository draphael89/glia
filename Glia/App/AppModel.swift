import SwiftUI
import Observation
import simd

/// The app's single source of truth: brain snapshot, filters, selection,
/// layout orchestration, camera control, and RenderScene production.
@MainActor
@Observable
final class AppModel {

    // MARK: state

    private(set) var graph: BrainGraph = .empty
    private(set) var positions: [SIMD2<Float>] = []
    private(set) var isSettling = false
    private(set) var loadError: String?

    var hideOrphans = true { didSet { sceneDirty() } }
    var enabledSources: Set<String> = [] { didSet { sceneDirty() } }
    var enabledTypes: Set<String> = [] { didSet { sceneDirty() } }

    var selectedIndex: Int? { didSet { sceneDirty() } }
    var hoveredIndex: Int? { didSet { sceneDirty() } }
    var searchText = ""
    var paletteVisible = false
    /// Bumped on any camera/scene change; the label overlay observes it.
    private(set) var cameraTick = 0

    let renderer: GraphRenderer
    let replay = ReplayController()
    private weak var view: GraphMTKView?
    private let source: BrainSource
    private var updateTask: Task<Void, Never>?
    /// Parsed once per graph — hot path for replay visibility.
    private var createdDates: [Date?] = []

    var allSources: [String] { Array(Set(graph.nodes.map(\.source))).sorted() }
    var typeCounts: [(type: String, count: Int)] {
        var c: [String: Int] = [:]
        for n in graph.nodes { c[n.type, default: 0] += 1 }
        return c.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
    var updatedTodayCount: Int {
        let today = Calendar.current.startOfDay(for: .now)
        return graph.nodes.lazy.filter { ($0.updatedDate ?? .distantPast) >= today }.count
    }
    var selectedNode: BrainNode? { selectedIndex.map { graph.nodes[$0] } }

    // MARK: init / lifecycle

    /// Single app-lifetime instance, reachable from App Intents / URL routing.
    static var shared: AppModel?

    init(source: BrainSource = JSONFileBrainSource(url: JSONFileBrainSource.defaultURL)) {
        guard let renderer = GraphRenderer() else {
            fatalError("Glia requires a Metal-capable GPU")
        }
        self.renderer = renderer
        self.source = source
        renderer.onFrame = { [weak self] _ in self?.frameTicked() }
        replay.attach(model: self)
        AppModel.shared = self
    }

    /// Deep-link entry: glia://node/<id> or Spotlight "node:<id>".
    func open(nodeID: Int) {
        guard let i = graph.indexByID[nodeID] else { return }
        select(index: i)
    }

    func attach(view: GraphMTKView) {
        self.view = view
        if graph.nodes.isEmpty { start() }
    }

    func start() {
        updateTask?.cancel()
        Task { await initialLoad() }
        updateTask = Task { [source] in
            for await fresh in source.updates() {
                self.apply(graph: fresh, animateInsertions: true)
            }
        }
    }

    private func initialLoad() async {
        do {
            let g = try await source.loadGraph()
            apply(graph: g, animateInsertions: false)
        } catch {
            loadError = "Couldn't read the brain: \(error.localizedDescription)"
        }
    }

    // MARK: graph application + layout

    private func apply(graph newGraph: BrainGraph, animateInsertions: Bool) {
        let old = graph
        graph = newGraph
        createdDates = newGraph.nodes.map(\.createdDate)
        replay.recomputeRange()
        SpotlightIndexer.reindex(graph: newGraph)
        if enabledSources.isEmpty { enabledSources = Set(newGraph.nodes.map(\.source)) }
        if enabledTypes.isEmpty { enabledTypes = Set(newGraph.nodes.map(\.type)) }

        // carry over positions by node id; seed the rest
        var placed: [Int: SIMD2<Float>] = [:]
        if !old.nodes.isEmpty && positions.count == old.nodes.count {
            for (i, n) in old.nodes.enumerated() { placed[n.id] = positions[i] }
        } else if let persisted = LayoutStore.load(for: newGraph) {
            placed = persisted
        }

        let seeded = placed.isEmpty
            ? LayoutEngine.seedPositions(for: newGraph)
            : LayoutEngine.seedInsertions(graph: newGraph, placed: placed)
        positions = seeded
        sceneDirty()

        // Live arrivals bloom exactly like replay births.
        if animateInsertions && !placed.isEmpty {
            let newborn = newGraph.nodes.enumerated()
                .filter { placed[$0.element.id] == nil }
                .map(\.offset)
            replay.noteLiveBirths(indices: newborn)
        }

        // Full settle on first load; gentle local settle for updates.
        let full = placed.isEmpty
        var config = LayoutEngine.Config()
        if !full {
            config.alphaStart = 0.25
            config.maxIterations = 120
        }
        runSettle(config: config, pinNothing: full || placed.isEmpty)
        if selectedIndex.map({ $0 >= newGraph.nodes.count }) == true { selectedIndex = nil }
        if hoveredIndex.map({ $0 >= newGraph.nodes.count }) == true { hoveredIndex = nil }
    }

    private func runSettle(config: LayoutEngine.Config, pinNothing: Bool) {
        isSettling = true
        setContinuousRendering(true)
        let g = graph
        let start = positions
        Task.detached(priority: .userInitiated) {
            let final = LayoutEngine.settle(
                graph: g, start: start, pinned: nil, config: config,
                tickEvery: 2,
                onTick: { snapshot, _ in
                    Task { @MainActor in
                        guard self.graph.generatedAt == g.generatedAt else { return }
                        self.positions = snapshot
                        self.sceneDirty()
                    }
                }
            )
            Task { @MainActor in
                guard self.graph.generatedAt == g.generatedAt else { return }
                self.positions = final
                self.isSettling = false
                self.sceneDirty()
                self.setContinuousRendering(false)
                self.fitView()
                LayoutStore.save(graph: g, positions: final)
                self.snapshotIfRequested()
                // GLIA_AUTOPLAY_REPLAY=1: start the growth replay shortly
                // after settling — used for hands-free demo recordings.
                if ProcessInfo.processInfo.environment["GLIA_AUTOPLAY_REPLAY"] != nil {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2.5))
                        self.replay.play()
                    }
                }
            }
        }
    }

    /// GLIA_SNAPSHOT=/path.png — render one settled frame and exit.
    /// GLIA_SNAPSHOT_FOCUS=<slug substring> — select that node first.
    /// GLIA_SNAPSHOT_REPLAY=<0..1> — scrub the growth replay first.
    private func snapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["GLIA_SNAPSHOT"] else { return }
        if let focus = ProcessInfo.processInfo.environment["GLIA_SNAPSHOT_FOCUS"],
           let idx = graph.nodes.firstIndex(where: { $0.slug.contains(focus) }) {
            selectedIndex = idx
            sceneDirty()
        }
        if let f = ProcessInfo.processInfo.environment["GLIA_SNAPSHOT_REPLAY"].flatMap(Double.init) {
            replay.scrub(to: f)
        }
        let size = CGSize(width: 1600, height: 1000)
        var cam = GraphRenderer.fittingCamera(positions: positions,
                                              visible: renderer.scene.visible,
                                              size: size)
        if let sel = selectedIndex {
            // Frame the selected node's neighborhood, not just the node.
            var pts = [positions[sel]]
            for nb in graph.neighbors[sel] { pts.append(positions[Int(nb)]) }
            cam = GraphRenderer.fittingCamera(positions: pts,
                                              visible: [],
                                              size: size, padding: 160)
            cam.zoom = min(cam.zoom, 10)
        }
        renderer.camera = cam   // label overlay reads the live camera
        cameraTick &+= 1
        guard let metal = renderer.snapshotImage(size: size, camera: cam) else {
            print("glia: snapshot FAILED"); NSApp.terminate(nil); return
        }
        // Composite the native label layer on top so snapshots match the app.
        let overlay = LabelOverlay(model: self)
            .frame(width: size.width, height: size.height)
        let ir = ImageRenderer(content: overlay)
        ir.scale = 1
        let labels = ir.cgImage

        // In focus snapshots, also composite the inspector so agent-driven
        // review sees the full user-facing state.
        var inspector: CGImage?
        var inspectorSize = CGSize.zero
        if selectedIndex != nil {
            let panel = InspectorPanel(model: self)
                .environment(\.colorScheme, .dark)
                .background(Theme.background)
            let pir = ImageRenderer(content: panel)
            pir.scale = 1
            pir.proposedSize = .init(width: 300, height: nil)
            inspector = pir.cgImage
            if let inspector {
                inspectorSize = CGSize(width: inspector.width, height: inspector.height)
            }
        }

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        if let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                               bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            let rect = CGRect(origin: .zero, size: size)
            ctx.draw(metal, in: rect)
            if let labels { ctx.draw(labels, in: rect) }
            if let inspector {
                ctx.draw(inspector, in: CGRect(x: size.width - inspectorSize.width - 14,
                                               y: size.height - inspectorSize.height - 56,
                                               width: inspectorSize.width,
                                               height: inspectorSize.height))
            }
            if let out = ctx.makeImage() {
                GraphRenderer.writePNG(out, to: URL(fileURLWithPath: path))
                print("glia: snapshot written to \(path)")
            }
        }
        NSApp.terminate(nil)
    }

    // MARK: scene production

    private(set) var visibleCount = 0
    private(set) var visibleEdgeCount = 0

    func sceneDirty() {
        guard positions.count == graph.nodes.count else { return }
        var scene = RenderScene()
        scene.positions = positions
        scene.version = renderer.scene.version + 1

        let n = graph.nodes.count
        var visible = [Bool](repeating: false, count: n)
        var flags = [Float](repeating: 0, count: n)
        var radii = [Float](repeating: 0, count: n)
        var colors = [SIMD4<Float>](repeating: .zero, count: n)

        // focus neighborhood when a node is selected
        var inFocus: Set<Int> = []
        if let sel = selectedIndex {
            inFocus.insert(sel)
            for nb in graph.neighbors[sel] { inFocus.insert(Int(nb)) }
        }

        let replayCursor = replay.cursor
        let now = CACurrentMediaTime()
        var shown = 0
        for i in 0..<n {
            let node = graph.nodes[i]
            var vis = enabledSources.contains(node.source)
                && enabledTypes.contains(node.type)
                && (!hideOrphans || graph.degree[i] > 0)
            if let replayCursor, let created = createdDates[i], created > replayCursor {
                vis = false
            }
            visible[i] = vis
            if vis { shown += 1 }
            var radius = 1.6 + min(7.5, 1.35 * Float(graph.degree[i]).squareRoot())
            colors[i] = Theme.color(type: node.type, source: node.source)
            var f: Float = 0
            if i == selectedIndex { f += 1 }
            if i == hoveredIndex { f += 2 }
            if !inFocus.isEmpty && !inFocus.contains(i) { f += 4 }
            // birth bloom: pop in bright and settle over ~0.9s
            if let birth = replay.birthTimes[i] {
                let age = Float(now - birth)
                if age < 0.9 {
                    let t = 1 - age / 0.9
                    radius *= 1 + 1.7 * t * t
                    f += 8
                }
            }
            radii[i] = radius
            flags[i] = f
        }

        var edgeColors: [SIMD4<Float>] = []
        edgeColors.reserveCapacity(graph.linkIndices.count)
        var edges: [(Int32, Int32)] = []
        edges.reserveCapacity(graph.linkIndices.count)
        var shownEdges = 0
        for (s, t) in graph.linkIndices {
            let si = Int(s), ti = Int(t)
            guard visible[si] && visible[ti] else { continue }
            edges.append((s, t))
            shownEdges += 1
            let focused = inFocus.isEmpty || (inFocus.contains(si) && inFocus.contains(ti))
            edgeColors.append(Theme.edgeColor(focused: focused))
        }

        scene.visible = visible
        scene.flags = flags
        scene.radii = radii
        scene.colors = colors
        scene.edges = edges
        scene.edgeColors = edgeColors
        scene.dimStrength = inFocus.isEmpty ? 0 : 1
        renderer.scene = scene
        visibleCount = shown
        visibleEdgeCount = shownEdges
        cameraTick &+= 1
        view?.requestDraw()
    }

    // MARK: camera + interaction

    private func setContinuousRendering(_ on: Bool) {
        view?.isPaused = !on
        view?.enableSetNeedsDisplay = !on
        if !on { view?.requestDraw() }
    }

    private func frameTicked() {
        cameraTick &+= 1
        // Called from the render loop; wind down to on-demand when idle.
        if !isSettling && !renderer.camera.isAnimating && selectedIndex == nil {
            setContinuousRendering(false)
        }
    }

    func cameraChanged() {
        cameraTick &+= 1
        view?.requestDraw()
    }

    func replayChanged() { sceneDirty() }
    func setReplayRendering(_ on: Bool) { setContinuousRendering(on) }

    func fitView() {
        guard !positions.isEmpty, let view else { return }
        var lo = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var hi = -lo
        var any = false
        for i in 0..<positions.count where renderer.scene.visible.isEmpty || renderer.scene.visible[i] {
            lo = simd_min(lo, positions[i]); hi = simd_max(hi, positions[i]); any = true
        }
        guard any else { return }
        // Optical center: leave room for the filter card (left) and header.
        var cam = renderer.camera
        cam.fit(bounds: (lo, hi),
                viewport: SIMD2(Float(view.bounds.width), Float(view.bounds.height)),
                padding: 110)
        let insetShift = SIMD2<Float>(-92, -18) / cam.zoomTarget   // px -> world
        renderer.camera.fly(to: cam.centerTarget - insetShift, zoom: cam.zoomTarget)
        setContinuousRendering(true)
    }

    func pick(atView p: SIMD2<Float>, viewport: SIMD2<Float>, radiusPx: Float = 14) -> Int? {
        guard positions.count == graph.nodes.count else { return nil }
        let world = renderer.camera.viewToWorld(p, viewport: viewport)
        let maxWorld = radiusPx / renderer.camera.zoom
        var best: Int? = nil
        var bestDist = maxWorld
        let vis = renderer.scene.visible
        for i in 0..<positions.count where vis.isEmpty || vis[i] {
            let d = simd_length(positions[i] - world)
            let hitRadius = max(renderer.scene.radii[i], bestDist)
            if d < min(hitRadius, bestDist) { best = i; bestDist = d }
        }
        return best
    }

    func hover(atView p: SIMD2<Float>?, viewport: SIMD2<Float>) {
        let target = p.flatMap { pick(atView: $0, viewport: viewport) }
        if target != hoveredIndex {
            hoveredIndex = target
            (target != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }

    func click(atView p: SIMD2<Float>, viewport: SIMD2<Float>) {
        selectedIndex = pick(atView: p, viewport: viewport)
        if selectedIndex != nil { setContinuousRendering(true) }   // glow breathing
    }

    func flyToNode(atView p: SIMD2<Float>, viewport: SIMD2<Float>) {
        guard let i = pick(atView: p, viewport: viewport) else { return }
        select(index: i)
    }

    func select(index: Int) {
        selectedIndex = index
        renderer.camera.fly(to: positions[index], zoom: max(renderer.camera.zoom, 9))
        setContinuousRendering(true)
    }

    func clearFocus() {
        selectedIndex = nil
        paletteVisible = false
    }

    // MARK: page content

    /// Markdown body for the selected node, when the page exists in the
    /// on-disk mirror (default source; atoms/raw live only in the DB).
    var selectedMarkdown: String? {
        guard let node = selectedNode, node.source == "default" else { return nil }
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gbrain/source-default")
        let url = base.appendingPathComponent(node.slug + ".md")
        // guard against slug path escapes
        guard url.standardizedFileURL.path.hasPrefix(base.path),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count < 400_000,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    // MARK: search

    struct SearchHit: Identifiable {
        let id: Int          // node index
        let node: BrainNode
    }

    var searchHits: [SearchHit] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        var hits: [(Int, Int)] = []   // (index, rank)
        for (i, n) in graph.nodes.enumerated() {
            let slug = n.slug.lowercased()
            let title = n.title.lowercased()
            if slug.hasPrefix(q) || title.hasPrefix(q) { hits.append((i, 0)) }
            else if slug.contains(q) || title.contains(q) { hits.append((i, 1)) }
            if hits.count > 400 { break }
        }
        hits.sort { ($0.1, -graph.degree[$0.0]) < ($1.1, -graph.degree[$1.0]) }
        return hits.prefix(30).map { SearchHit(id: $0.0, node: graph.nodes[$0.0]) }
    }
}

// MARK: - Layout persistence

enum LayoutStore {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Glia", isDirectory: true)
    }
    private static var file: URL { dir.appendingPathComponent("layout.json") }

    static func save(graph: BrainGraph, positions: [SIMD2<Float>]) {
        guard graph.nodes.count == positions.count else { return }
        var payload: [String: [Float]] = [:]
        payload.reserveCapacity(graph.nodes.count)
        for (i, n) in graph.nodes.enumerated() {
            payload["\(n.id)"] = [positions[i].x, positions[i].y]
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: file, options: .atomic)
        }
    }

    static func load(for graph: BrainGraph) -> [Int: SIMD2<Float>]? {
        guard let data = try? Data(contentsOf: file),
              let payload = try? JSONDecoder().decode([String: [Float]].self, from: data),
              !payload.isEmpty else { return nil }
        var out: [Int: SIMD2<Float>] = [:]
        for (k, v) in payload where v.count == 2 {
            if let id = Int(k) { out[id] = SIMD2(v[0], v[1]) }
        }
        // Only reuse if it covers a meaningful share of the graph
        let coverage = graph.nodes.lazy.filter { out[$0.id] != nil }.count
        return coverage * 3 >= graph.nodes.count ? out : nil
    }
}
