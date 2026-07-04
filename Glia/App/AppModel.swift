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
    var shortcutsVisible = false
    /// Bumped on any camera/scene change; the label overlay observes it.
    private(set) var cameraTick = 0
    /// Mirrors BrainLocation.demoMode as observable state.
    private(set) var demoActive = false

    let renderer: GraphRenderer
    let replay = ReplayController()
    private weak var view: GraphMTKView?
    private var source: BrainSource
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

    init(source: BrainSource? = nil) {
        guard let renderer = GraphRenderer() else {
            fatalError("Glia requires a Metal-capable GPU")
        }
        BrainLocation.startUp()
        self.renderer = renderer
        self.source = source ?? JSONFileBrainSource(url: JSONFileBrainSource.defaultURL)
        renderer.onFrame = { [weak self] _ in self?.frameTicked() }
        replay.attach(model: self)
        AppModel.shared = self
        // Snapshot mode must not depend on a window ever appearing (the
        // accessory activation policy may keep SwiftUI from presenting one):
        // drive the load → settle → render pipeline directly.
        Markers.drop("model.init")
        if ProcessInfo.processInfo.environment["GLIA_SNAPSHOT"] != nil {
            start()
        }
    }

    private var started = false

    /// Re-point the app at the current BrainLocation (after folder choice
    /// or demo-mode toggle) and reload from scratch.
    func reloadFromLocation() {
        loadError = nil
        demoActive = BrainLocation.demoMode
        source = JSONFileBrainSource(url: JSONFileBrainSource.defaultURL)
        selectedIndex = nil
        hoveredIndex = nil
        start()
    }

    func exploreDemo() {
        BrainLocation.enterDemoMode()
        reloadFromLocation()
    }

    func exitDemo() {
        BrainLocation.exitDemoMode()
        reloadFromLocation()
    }

    func chooseBrainFolder() {
        if BrainLocation.chooseFolder() { reloadFromLocation() }
    }

    /// Deep-link entry: glia://node/<id> or Spotlight "node:<id>".
    func open(nodeID: Int) {
        guard let i = graph.indexByID[nodeID] else { return }
        select(index: i)
    }

    func attach(view: GraphMTKView) {
        self.view = view
        if graph.nodes.isEmpty && !started { start() }
    }

    func start() {
        Markers.drop("start")
        started = true
        updateTask?.cancel()
        Task { await initialLoad() }
        updateTask = Task { [source] in
            for await fresh in source.updates() {
                self.apply(graph: fresh, animateInsertions: true)
            }
        }
    }

    private func initialLoad() async {
        Markers.drop("initialLoad.begin")
        do {
            let g = try await source.loadGraph()
            Markers.drop("loaded nodes=\(g.nodes.count)")
            apply(graph: g, animateInsertions: false)
        } catch {
            loadError = "Couldn't read the brain: \(error.localizedDescription)"
            // error state is a first-class screen — verifiable like the rest
            snapshotIfRequested()
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
                // Stable spatial memory extends across launches: come back
                // to exactly where you were, not a re-fit.
                if !self.restoreViewState() { self.fitView() }
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
        Markers.drop("snapshot.begin")
        guard let path = ProcessInfo.processInfo.environment["GLIA_SNAPSHOT"] else { return }
        if let focus = ProcessInfo.processInfo.environment["GLIA_SNAPSHOT_FOCUS"],
           let idx = graph.nodes.firstIndex(where: { $0.slug.contains(focus) }) {
            selectedIndex = idx
            sceneDirty()
        }
        if let f = ProcessInfo.processInfo.environment["GLIA_SNAPSHOT_REPLAY"].flatMap(Double.init) {
            replay.scrub(to: f)
        }
        if let q = ProcessInfo.processInfo.environment["GLIA_SNAPSHOT_QUERY"] {
            searchText = q
            paletteVisible = true
        }
        // GLIA_SNAPSHOT_SIZE=2880x1800 for App Store screenshot resolution
        var size = CGSize(width: 1600, height: 1000)
        if let s = ProcessInfo.processInfo.environment["GLIA_SNAPSHOT_SIZE"] {
            let parts = s.lowercased().split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, parts[0] >= 320, parts[1] >= 240 {
                size = CGSize(width: parts[0], height: parts[1])
            }
        }
        // snapshot framing matches the app: structure only, dust bleeds out
        var structureMask = renderer.scene.visible
        if !structureMask.isEmpty {
            for i in 0..<structureMask.count where (Int(renderer.scene.flags[i]) & 16) != 0 {
                structureMask[i] = false
            }
        }
        var cam = GraphRenderer.fittingCamera(positions: positions,
                                              visible: structureMask,
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

        // Error-state snapshot: the empty-state card centered over the void.
        var errorCard: CGImage?
        if let loadError {
            let view = ErrorCard(message: loadError, retry: {})
                .environment(\.colorScheme, .dark)
            let er = ImageRenderer(content: view)
            er.scale = 1
            errorCard = er.cgImage
        }

        // Palette snapshot: composite the search UI over the canvas.
        var palette: CGImage?
        if paletteVisible {
            let view = CommandPalette(model: self)
                .environment(\.colorScheme, .dark)
                .frame(width: size.width, height: size.height)
            let pr = ImageRenderer(content: view)
            pr.scale = 1
            palette = pr.cgImage
        }

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
            if let palette {
                ctx.draw(palette, in: rect)
            }
            if let errorCard {
                let w = CGFloat(errorCard.width), h = CGFloat(errorCard.height)
                ctx.draw(errorCard, in: CGRect(x: (size.width - w) / 2,
                                               y: (size.height - h) / 2,
                                               width: w, height: h))
            }
            if let out = ctx.makeImage() {
                GraphRenderer.writePNG(out, to: URL(fileURLWithPath: path))
                print("glia: snapshot written to \(path)")
            }
        }
        // Hard exit: NSApp.terminate can hang for accessory apps with no
        // presented window, and snapshot runs are tooling, not sessions.
        exit(0)
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
            let typeOn = enabledSources.contains(node.source)
                && enabledTypes.contains(node.type)
            let isOrphan = graph.degree[i] == 0
            // Orphans under "hide unlinked" become DUST: barely-there points
            // that keep the full corpus tangible — the brain's dark matter —
            // without cluttering the structure.
            var dust = false
            var vis = typeOn
            if vis && hideOrphans && isOrphan { dust = true }
            // The selected node is always fully visible, whatever the filters:
            // search must never fly the camera to nothing.
            if i == selectedIndex && typeOn { vis = true; dust = false }
            // ...but time wins: during replay, nothing exists before its
            // birth date — selection included.
            if let replayCursor, let created = createdDates[i], created > replayCursor {
                vis = false; dust = false
            }
            visible[i] = vis
            if vis && !dust { shown += 1 }
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
            if dust { radius = 0.9; f += 16 }
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
            if inFocus.isEmpty {
                edgeColors.append(Theme.ambientEdge)
            } else {
                let focused = inFocus.contains(si) && inFocus.contains(ti)
                edgeColors.append(Theme.edgeColor(focused: focused))
            }
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
        if on { view?.preferredFramesPerSecond = 120 }   // full rate for motion
        if !on { view?.requestDraw() }
    }

    private func frameTicked() {
        cameraTick &+= 1
        // Called from the render loop; wind down when idle. Selection keeps
        // a slow loop alive for the glow breathing — 24fps is plenty for a
        // 2.2rad/s sine and an 80% energy cut vs. ProMotion rate.
        if !isSettling && !renderer.camera.isAnimating && !replay.isPlaying {
            saveViewState()
            if selectedIndex == nil {
                setContinuousRendering(false)
            } else if view?.preferredFramesPerSecond != 24 {
                view?.preferredFramesPerSecond = 24
            }
        }
    }

    // MARK: view-state persistence (camera + selection across launches)

    private var restoredOnce = false

    private func saveViewState() {
        // tooling runs (snapshots) and demo browsing don't own the viewpoint
        guard ProcessInfo.processInfo.environment["GLIA_SNAPSHOT"] == nil,
              !demoActive else { return }
        let d = UserDefaults.standard
        let cam = renderer.camera
        d.set([Double(cam.center.x), Double(cam.center.y), Double(cam.zoom)],
              forKey: "viewCamera")
        d.set(selectedIndex.map { graph.nodes[$0].slug } ?? "", forKey: "viewSelection")
    }

    /// Returns true if a previous session's viewpoint was restored.
    private func restoreViewState() -> Bool {
        guard !restoredOnce else { return true }   // only on first settle
        restoredOnce = true
        guard !demoActive,
              let arr = UserDefaults.standard.array(forKey: "viewCamera") as? [Double],
              arr.count == 3, arr[2] > 0.04 else { return false }
        renderer.camera.center = SIMD2(Float(arr[0]), Float(arr[1]))
        renderer.camera.zoom = Float(arr[2])
        if let slug = UserDefaults.standard.string(forKey: "viewSelection"), !slug.isEmpty,
           let i = graph.nodes.firstIndex(where: { $0.slug == slug }) {
            selectedIndex = i
        }
        cameraChanged()
        return true
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
        let vis = renderer.scene.visible
        let flags = renderer.scene.flags
        for i in 0..<positions.count where vis.isEmpty || vis[i] {
            // frame the structure; the dust halo bleeds past the edges
            if !flags.isEmpty && (Int(flags[i]) & 16) != 0 { continue }
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
        let flags = renderer.scene.flags
        for i in 0..<positions.count where vis.isEmpty || vis[i] {
            if !flags.isEmpty && (Int(flags[i]) & 16) != 0 { continue }   // dust isn't clickable
            let d = simd_length(positions[i] - world)
            let hitRadius = max(renderer.scene.radii[i], bestDist)
            if d < min(hitRadius, bestDist) { best = i; bestDist = d }
        }
        return best
    }

    func hover(atView p: SIMD2<Float>?, viewport: SIMD2<Float>) {
        let target = p.flatMap { pick(atView: $0, viewport: viewport) }
        if target != hoveredIndex {
            // subtle trackpad detent when the cursor acquires a node —
            // the graph pushes back like a physical object
            if target != nil && !Camera.reduceMotion {
                NSHapticFeedbackManager.defaultPerformer
                    .perform(.alignment, performanceTime: .now)
            }
            hoveredIndex = target
            (target != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }

    /// File → Export Snapshot…: render the CURRENT view (camera, filters,
    /// selection — exactly what's on screen) at 2x to a user-chosen PNG.
    func exportSnapshot() {
        guard let view else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Brain — \(Date.now.formatted(.iso8601.year().month().day())).png"
        panel.message = "Export the current view as an image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var cam = renderer.camera
        cam.cancelFlight()
        cam.zoom *= 2   // 2x supersample of the live viewport
        let size = CGSize(width: view.bounds.width * 2, height: view.bounds.height * 2)
        if let image = renderer.snapshotImage(size: size, camera: cam) {
            GraphRenderer.writePNG(image, to: url)
        }
    }

    /// Arrow-key traversal: hop from the selected node to the connected
    /// neighbor whose direction best matches the pressed arrow. Pairs with
    /// VoiceOver announcements for eyes-free graph walking.
    func step(direction: SIMD2<Float>) {
        guard let sel = selectedIndex else { return }
        let origin = positions[sel]
        var best: Int? = nil
        var bestScore: Float = 0.25   // ignore neighbors >75° off-axis
        for nb in graph.neighbors[sel] {
            let j = Int(nb)
            let d = positions[j] - origin
            let len = simd_length(d)
            guard len > 0.001 else { continue }
            let score = simd_dot(d / len, direction)
            if score > bestScore { bestScore = score; best = j }
        }
        if let best { select(index: best) }
    }

    /// Keyboard zoom (⌘+ / ⌘− / ⌘0), anchored at the viewport center.
    func zoomStep(_ factor: Float) {
        guard let view else { return }
        let viewport = SIMD2(Float(view.bounds.width), Float(view.bounds.height))
        renderer.camera.zoom(by: factor, anchorView: viewport / 2, viewport: viewport)
        cameraChanged()
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
        let node = graph.nodes[index]
        view?.announceSelection(
            "\(node.displayTitle), \(node.type), \(graph.degree[index]) connections")
    }

    func clearFocus() {
        selectedIndex = nil
        paletteVisible = false
    }

    // MARK: page content

    /// On-disk mirror file for the selected node, when one exists —
    /// powers both the inspector preview and Quick Look (Space).
    var selectedFileURL: URL? {
        guard let node = selectedNode,
              let base = BrainLocation.sourceMirror(for: node.source) else { return nil }
        let url = base.appendingPathComponent(node.slug + ".md")
        guard url.standardizedFileURL.path.hasPrefix(base.path),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Markdown body for the selected node, when the page exists in that
    /// source's on-disk mirror (atoms/raw live only in the DB).
    var selectedMarkdown: String? {
        guard let node = selectedNode,
              let base = BrainLocation.sourceMirror(for: node.source) else { return nil }
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
