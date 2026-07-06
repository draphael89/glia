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
    // Hover flips only a flag bit — edges are untouched, so skip the O(E) edge
    // rebuild + reshuffle + GPU re-upload as the cursor crosses nodes.
    var hoveredIndex: Int? { didSet { sceneDirty(edgesChanged: false) } }
    var searchText = ""
    var paletteVisible = false
    var shortcutsVisible = false
    var contextExportVisible = false
    var enableMCPVisible = false
    /// State of registering glia-context with Claude Code + Desktop (sheet observes).
    private(set) var mcpStatus = MCPStatus()
    /// Live preview of what the MCP would inject for a task (nil until previewed).
    private(set) var injectionPreview: String?
    private(set) var previewingInjection = false
    /// Slugs the user has starred as core-identity — the curated "who I am"
    /// set that becomes a Context Bundle scope. Persisted across launches.
    private(set) var starredSlugs: Set<String> = []
    /// Bumped on any camera/scene change; the label overlay observes it.
    private(set) var cameraTick = 0
    /// Mirrors BrainLocation.demoMode as observable state.
    private(set) var demoActive = false

    /// Live status of the psyche → glia-context MCP sync (menu bar + sheet observe).
    private(set) var psycheStatus = PsycheSyncStatus()
    /// Best-effort: is the glia-context server registered with Claude Code? (nil = unknown)
    private(set) var serverRegistered: Bool?
    /// Coalesces rapid star toggles into one atomic psyche write. A `let`, so
    /// @Observable leaves it untracked; @MainActor so it needs no annotation.
    private let liveSyncDebouncer = Debouncer(delay: .milliseconds(700))

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
        var stars = Set(UserDefaults.standard.stringArray(forKey: "starredSlugs") ?? [])
        // GLIA_STAR=slug1,slug2 — deterministic star seeding for snapshots/tests
        if let s = ProcessInfo.processInfo.environment["GLIA_STAR"] {
            stars.formUnion(s.split(separator: ",").map(String.init))
        }
        starredSlugs = stars
        self.renderer = renderer
        self.source = source ?? JSONFileBrainSource(url: JSONFileBrainSource.defaultURL)
        renderer.onFrame = { [weak self] _ in self?.frameTicked() }
        replay.attach(model: self)
        AppModel.shared = self
        // Headless/automation runs must not depend on a window ever appearing
        // (the accessory activation policy may keep SwiftUI from presenting
        // one): drive the load → settle → render pipeline directly.
        Markers.drop("model.init")
        let env = ProcessInfo.processInfo.environment
        if env["GLIA_SNAPSHOT"] != nil || env["GLIA_ENABLE_MCP"] != nil
            || env["GLIA_EXPORT_CONTEXT"] != nil || env["GLIA_PREVIEW"] != nil {
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

    /// A deep link that arrived before the graph finished loading (cold launch via
    /// Spotlight / glia://), retried once the brain is installed.
    private var pendingNodeID: Int?

    /// Deep-link entry: glia://node/<id> or Spotlight "node:<id>".
    func open(nodeID: Int) {
        if let i = graph.indexByID[nodeID] {
            pendingNodeID = nil
            select(index: i)
        } else {
            // Graph not loaded yet (cold start) — remember it; apply() retries.
            pendingNodeID = nodeID
        }
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
        // Headless automation hooks run OUTSIDE the do/catch so a load failure
        // can't skip them and leave a scripted (windowless) process hanging.
        // GLIA_EXPORT_CONTEXT=<scope>:<path> — headless bundle export.
        if let spec = ProcessInfo.processInfo.environment["GLIA_EXPORT_CONTEXT"],
           let colon = spec.firstIndex(of: ":") {
            let scope = ContextScope(rawValue: String(spec[..<colon])) ?? .identity
            let path = String(spec[spec.index(after: colon)...])
            let b = buildContextBundle(scope)
            try? b.text.data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
            print("glia: context \(b.pageCount) pages, ~\(b.tokenEstimate) tokens -> \(path)")
            exit(0)
        }
        // GLIA_ENABLE_MCP=1 — headless one-click enable (register Claude Code +
        // Desktop). Registration doesn't need the graph, so it runs even if the
        // brain failed to load; the psyche sync just no-ops on an empty graph.
        if ProcessInfo.processInfo.environment["GLIA_ENABLE_MCP"] != nil {
            await enableMCP()
            print("glia: enableMCP node=\(mcpStatus.node) code=\(mcpStatus.claudeCode) desktop=\(mcpStatus.claudeDesktop) dist=\(mcpStatus.distPath ?? "-") phase=\(mcpStatus.phase)")
            exit(0)
        }
        // GLIA_PREVIEW=<task> — headless run of the in-app injection preview
        // (resolve node + staged dist + --explain) for automation/verification.
        if let task = ProcessInfo.processInfo.environment["GLIA_PREVIEW"] {
            await previewInjection(task: task)
            print("glia: previewInjection ↓\n\(injectionPreview ?? "nil")")
            exit(0)
        }
    }

    // MARK: graph application + layout

    private func apply(graph newGraph: BrainGraph, animateInsertions: Bool) {
        let old = graph
        // selectedIndex/hoveredIndex are raw indices into the OLD node array; the
        // new payload is JSON-ordered, so remap them by stable node id (not clamp)
        // or the selection silently jumps to a different node after a poll.
        let selectedID = selectedIndex.flatMap { $0 < old.nodes.count ? old.nodes[$0].id : nil }
        let hoveredID = hoveredIndex.flatMap { $0 < old.nodes.count ? old.nodes[$0].id : nil }
        graph = newGraph
        selectedIndex = selectedID.flatMap { newGraph.indexByID[$0] }
        hoveredIndex = hoveredID.flatMap { newGraph.indexByID[$0] }
        createdDates = newGraph.nodes.map(\.createdDate)
        replay.recomputeRange()
        // Demo is a sandbox: reindexing would WIPE the real brain's system Spotlight
        // index and expose synthetic demo pages (with deep-links) in system-wide
        // search. The one side-effecting path that was left ungated — gate it like
        // toggleStar / performSync / saveViewState.
        if !demoActive { SpotlightIndexer.reindex(graph: newGraph) }
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
        // Incremental update: PIN carried-over nodes so only the newly-inserted
        // neighborhood relaxes. Without this every poll re-relaxes the whole graph
        // and drifts every node — destroying the stable spatial memory that is the
        // viewer's whole promise ("come back to exactly where you were").
        let pinned: [Bool]? = full ? nil : newGraph.nodes.map { placed[$0.id] != nil }
        runSettle(config: config, pinned: pinned)
        // (selection/hover were already remapped by id at the top of apply)
        // A cold-launch deep link (Spotlight / glia://) that arrived before the
        // graph loaded now resolves against the freshly-installed brain.
        if let pending = pendingNodeID, let i = graph.indexByID[pending] {
            pendingNodeID = nil
            select(index: i)
        }
    }

    private func runSettle(config: LayoutEngine.Config, pinned: [Bool]?) {
        isSettling = true
        // Reduce Motion: the settle swirl is the app's biggest full-field motion —
        // suppress it (compute off-thread, SNAP to the final layout) the same way
        // camera flights and haptics already honor the setting.
        let reduce = Camera.reduceMotion
        if !reduce { setContinuousRendering(true) }
        let g = graph
        let start = positions
        Task.detached(priority: .userInitiated) {
            let final = LayoutEngine.settle(
                graph: g, start: start, pinned: pinned, config: config,
                tickEvery: 2,
                onTick: { snapshot, _ in
                    if reduce { return }   // Reduce Motion: no intermediate streaming, snap to final
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
                self.refreshContinuousRendering()   // don't cut an in-flight camera/selection animation
                // Stable spatial memory extends across launches: come back
                // to exactly where you were, not a re-fit.
                if !self.restoreViewState() { self.fitView() }
                self.viewStateReady = true
                LayoutStore.save(graph: g, positions: final)
                // Seed the MCP psyche once if it doesn't exist yet, so the
                // injection layer works even before the user syncs manually —
                // and refresh status so the menu bar is accurate at launch.
                Task {
                    await self.refreshPsycheStatusFromDisk()
                    if !FileManager.default.fileExists(atPath: Self.psycheFileURL.path) {
                        await self.performSync(scope: nil)
                    }
                }
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

    func sceneDirty(edgesChanged: Bool = true) {
        guard positions.count == graph.nodes.count else { return }
        let prior = renderer.scene
        var scene = RenderScene()
        scene.positions = positions
        scene.version = prior.version + 1
        // Edges depend only on positions + visibility + focus — never on the
        // hover flag. A flags-only update keeps the prior edgeVersion so the edge
        // buffer is NOT rebuilt.
        scene.edgeVersion = edgesChanged ? prior.edgeVersion + 1 : prior.edgeVersion

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
        let reduceMotion = Camera.reduceMotion
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
            // search / Spotlight / glia:// can target a node whose type or source
            // is filtered off, and the camera must never fly to nothing.
            if i == selectedIndex { vis = true; dust = false }
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
            // Birth bloom: pop in bright and settle over ~0.9s — but under Reduce
            // Motion the node just appears at full size (no scale-in animation).
            if !reduceMotion, let birth = replay.birthTimes[graph.nodes[i].id] {
                let age = Float(now - birth)
                if age < 0.9 {
                    let t = 1 - age / 0.9
                    radius *= 1 + 1.7 * t * t
                    f += 8
                }
            }
            if dust { radius = 0.9; f += 16 }
            if !starredSlugs.isEmpty && starredSlugs.contains(graph.nodes[i].slug) { f += 32 }
            radii[i] = radius
            flags[i] = f
        }

        if edgesChanged {
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
            scene.edges = edges
            scene.edgeColors = edgeColors
            visibleEdgeCount = shownEdges
        } else {
            // hover-only: reuse the prior edges verbatim (they can't have changed)
            scene.edges = prior.edges
            scene.edgeColors = prior.edgeColors
        }

        scene.visible = visible
        scene.flags = flags
        scene.radii = radii
        scene.colors = colors
        scene.dimStrength = inFocus.isEmpty ? 0 : 1
        renderer.scene = scene
        visibleCount = shown
        cameraTick &+= 1
        view?.requestDraw()
    }

    // MARK: camera + interaction

    private func setContinuousRendering(_ on: Bool) {
        guard let view else { return }
        let currentlyOn = !view.isPaused
        if on { view.preferredFramesPerSecond = 120 }    // full rate for motion
        // Only act on TRANSITIONS. Re-pausing while already paused used to
        // fire the "one last frame" kick every idle tick — pause → kick →
        // draw → tick → pause → kick: an infinite ~80fps loop disguised
        // as on-demand rendering.
        guard on != currentlyOn else { return }
        view.isPaused = !on
        view.enableSetNeedsDisplay = !on
        if !on { view.requestDraw() }   // flush the final state once
    }

    /// Pause ONLY if nothing still needs frames. Several owners (settle, camera
    /// flight, replay, selection-glow) drive continuous rendering; a raw
    /// setContinuousRendering(false) from one used to freeze another's in-flight
    /// animation. Route every "I'm done" through here so the view keeps rendering
    /// while ANY reason remains, and pauses only when all are quiet.
    private func refreshContinuousRendering() {
        let stillAnimating = isSettling
            || renderer.camera.isAnimating
            || replay.isPlaying
            // selection glow breathes — but under Reduce Motion the glow (and the
            // starfield twinkle) should be STILL, so a selection isn't a reason to
            // keep redrawing forever (accessibility + battery). Sampling u.time only
            // on draw means ceasing to render freezes the pulse to a static frame.
            || (selectedIndex != nil && !Camera.reduceMotion)
        setContinuousRendering(stillAnimating)
    }

    private func frameTicked() {
        let inMotion = isSettling || renderer.camera.isAnimating || replay.isPlaying
        // Invalidate SwiftUI overlays only while something MOVES. Bumping
        // every draw created a feedback loop (draw -> observable bump ->
        // overlay invalidation -> window redraw -> draw) that kept the app
        // rendering ~15fps forever and racing view-state saves.
        if inMotion { cameraTick &+= 1 }
        guard !inMotion else { return }
        // idle transition: persist the viewpoint once, then wind down
        if viewStateReady { saveViewState() }
        if selectedIndex == nil {
            setContinuousRendering(false)
        } else if view?.preferredFramesPerSecond != 24 {
            view?.preferredFramesPerSecond = 24
        }
    }

    // MARK: view-state persistence (camera + selection across launches)

    private var restoredOnce = false
    /// Saves are armed only after the first settle has restored-or-fit the
    /// camera — pre-settle draws must never persist the pristine state
    /// (that race poisoned the store and defeated restore-vs-fit).
    private var viewStateReady = false

    private var lastSavedView: (SIMD2<Float>, Float, Int?)?

    private func saveViewState() {
        // tooling runs (snapshots) and demo browsing don't own the viewpoint
        guard ProcessInfo.processInfo.environment["GLIA_SNAPSHOT"] == nil,
              !demoActive else { return }
        let cam = renderer.camera
        // dirty-check: the selection-breathing loop draws at 24fps — without
        // this it would write UserDefaults 24×/sec for as long as you read
        if let last = lastSavedView,
           last.0 == cam.center, last.1 == cam.zoom, last.2 == selectedIndex {
            return
        }
        lastSavedView = (cam.center, cam.zoom, selectedIndex)
        Markers.drop("save.viewState zoom=\(cam.zoom)")
        let d = UserDefaults.standard
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
        refreshContinuousRendering()   // a restored selection's glow must breathe, not sit static
        return true
    }

    func cameraChanged() {
        cameraTick &+= 1
        view?.requestDraw()
    }

    func replayChanged() { sceneDirty() }
    func setReplayRendering(_ on: Bool) { on ? setContinuousRendering(true) : refreshContinuousRendering() }

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
        var bestDist = Float.greatestFiniteMagnitude
        let vis = renderer.scene.visible
        let flags = renderer.scene.flags
        let radii = renderer.scene.radii
        for i in 0..<positions.count where vis.isEmpty || vis[i] {
            if !flags.isEmpty && (Int(flags[i]) & 16) != 0 { continue }   // dust isn't clickable
            let d = simd_length(positions[i] - world)
            // A node is clickable anywhere within its visual disk, or within the
            // base pick radius — whichever is larger — so hub nodes are as easy
            // to hit as they look. Among all such nodes, take the nearest center.
            let hitRadius = max(i < radii.count ? radii[i] : 0, maxWorld)
            if d < hitRadius && d < bestDist { best = i; bestDist = d }
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

    // MARK: identity collection (starred core-identity nodes)

    func isStarred(_ index: Int) -> Bool { starredSlugs.contains(graph.nodes[index].slug) }

    func toggleStar(_ index: Int) {
        // Demo mode is a sandbox: starring a DEMO node must not write a phantom slug
        // into the REAL starred collection — that flips scope to .collection, and
        // contextNodes(.collection) then matches zero real nodes, silently stopping
        // the user's psyche sync. Matches the !demoActive guard on every other
        // identity-mutating path (starIdentityCore, performSync, saveViewState).
        guard !demoActive else { return }
        let slug = graph.nodes[index].slug
        if starredSlugs.contains(slug) { starredSlugs.remove(slug) } else { starredSlugs.insert(slug) }
        UserDefaults.standard.set(Array(starredSlugs), forKey: "starredSlugs")
        sceneDirty()   // reflect the star ring on the canvas immediately
        view?.requestDraw()
        scheduleLiveSync()   // debounced: coalesce rapid toggles into one write
    }

    // MARK: psyche → MCP sync (the injection loop)

    /// The exact path the glia-context MCP reads, honoring GLIA_PSYCHE so the
    /// app writes precisely what the server reads.
    static var psycheFileURL: URL {
        if let p = ProcessInfo.processInfo.environment["GLIA_PSYCHE"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".glia/psyche.md")
    }

    private struct PsycheWriteResult: Sendable { let pageCount: Int; let bytes: Int; let modified: Date?; let wrote: Bool }

    /// Debounced live sync — called from `toggleStar` and the first-settle seed.
    /// Coalesces a burst of star toggles into a single atomic write 700ms later.
    func scheduleLiveSync() {
        guard !demoActive else { return }
        psycheStatus.phase = .pending                        // menu reflects it instantly
        psycheStatus.source = starredSlugs.isEmpty ? .identity : .collection
        liveSyncDebouncer.schedule { [weak self] in await self?.performSync(scope: nil) }
    }

    /// Manual override (File ▸ Sync Psyche to MCP ⌘⇧Y, menu bar, sheet). Cancels
    /// any pending debounce and syncs now. Keeps the public name its call sites use.
    @discardableResult
    func syncPsycheToMCP(scope: ContextScope? = nil) async -> Int {
        liveSyncDebouncer.cancel()
        return await performSync(scope: scope)
    }

    // Serialize syncs: `cancel()` can't stop a debounced write already past its
    // sleep, so a manual sync could otherwise run concurrently with it and
    // publish status that disagrees with the bytes on disk. Instead, coalesce —
    // a request arriving mid-write records a re-run with the newest scope, and
    // the in-flight sync loops once more so the LAST write always wins.
    private var syncInFlight = false
    private var syncRerunPending = false
    private var syncRerunScope: ContextScope?

    @discardableResult
    private func performSync(scope: ContextScope? = nil) async -> Int {
        guard !demoActive else { psycheStatus.phase = .skipped; return 0 }
        if syncInFlight {
            syncRerunPending = true
            syncRerunScope = scope
            return psycheStatus.pageCount
        }
        syncInFlight = true
        defer { syncInFlight = false }
        var currentScope = scope
        var pages = 0
        while true {
            pages = await runOneSync(scope: currentScope)
            if syncRerunPending {
                syncRerunPending = false
                currentScope = syncRerunScope
                syncRerunScope = nil
                continue
            }
            break
        }
        // A sync rewrote ~/.glia/psyche.md, so any on-screen injection preview now
        // reflects the OLD identity — clear it so a stale manifest can't sit beside
        // a freshly-synced status footer.
        if pages > 0 { injectionPreview = nil }
        return pages
    }

    /// One sync pass: gather Sendable inputs on the main actor, do the build +
    /// atomic write + stat off the main actor, then publish status that reflects
    /// what actually landed on disk.
    @discardableResult
    private func runOneSync(scope: ContextScope?) async -> Int {
        let resolved = scope ?? (starredSlugs.isEmpty ? .identity : .collection)
        let nodes = contextNodes(resolved)
        guard !nodes.isEmpty else { psycheStatus.phase = .idle; return 0 }  // never wedge at .pending
        let header = contextHeader(resolved)
        let mirrors = sourceMirrors(for: nodes)
        let url = Self.psycheFileURL
        psycheStatus.phase = .syncing
        let out = await Task.detached { () -> PsycheWriteResult in
            let bundle = ContextBundle.build(nodes: nodes, header: header, mirrors: mirrors)
            guard bundle.pageCount > 0 else { return .init(pageCount: 0, bytes: 0, modified: nil, wrote: false) }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            let data = Data(bundle.text.utf8)
            let wrote = ((try? data.write(to: url, options: .atomic)) != nil)   // report the real outcome
            var mtime: Date? = nil
            if wrote { mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date }
            return .init(pageCount: wrote ? bundle.pageCount : 0, bytes: data.count, modified: mtime, wrote: wrote)
        }.value
        if out.wrote && out.pageCount > 0 {
            psycheStatus.phase = .synced
            psycheStatus.pageCount = out.pageCount
            psycheStatus.source = resolved == .collection ? .collection
                : (resolved == .identity ? .identity : .custom)
            psycheStatus.fileBytes = out.bytes
            psycheStatus.fileModified = out.modified ?? .now
            psycheStatus.lastSyncedAt = .now
            UserDefaults.standard.set(out.pageCount, forKey: "psycheLastPageCount")
            UserDefaults.standard.set(psycheStatus.source.rawValue, forKey: "psycheLastSource")
        } else {
            psycheStatus.phase = .failed
        }
        return out.pageCount
    }

    /// Cheap disk probe (mtime + size only, no body parse) so the menu bar shows
    /// accurate status at launch / each menu open, even without a sync this run.
    func refreshPsycheStatusFromDisk() async {
        let url = Self.psycheFileURL
        struct Probe: Sendable { let mtime: Date?; let bytes: Int }
        let p = await Task.detached { () -> Probe in
            guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                return Probe(mtime: nil, bytes: 0)
            }
            return Probe(mtime: a[.modificationDate] as? Date, bytes: (a[.size] as? Int) ?? 0)
        }.value
        psycheStatus.fileModified = p.mtime
        psycheStatus.fileBytes = p.bytes
        if psycheStatus.lastSyncedAt == nil { psycheStatus.lastSyncedAt = p.mtime }
        if psycheStatus.pageCount == 0 {
            psycheStatus.pageCount = UserDefaults.standard.integer(forKey: "psycheLastPageCount")
        }
        if psycheStatus.phase == .idle, p.mtime != nil { psycheStatus.phase = .synced }
    }

    /// Best-effort: is glia-context registered with Claude Code? (nil = unknown/unreadable)
    func refreshServerRegistration() async {
        let cfg = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        serverRegistered = await Task.detached { () -> Bool? in
            guard let d = try? Data(contentsOf: cfg), d.count < 4_000_000,
                  let s = String(data: d, encoding: .utf8) else { return nil }
            return s.contains("glia-context")
        }.value
    }

    /// Whether the MCP will inject the app's file or fall back to building.
    var psycheReachability: PsycheReachability {
        let s = psycheStatus
        return .init(file: s.fileState, bytes: s.fileBytes, modified: s.fileModified, serverRegistered: serverRegistered)
    }

    // MARK: one-click Enable MCP (register with Claude Code + Claude Desktop)

    /// Fast initial status for the Enable sheet (reads configs, cheap node probe).
    func refreshMCPStatus() async {
#if MAS
        return   // sandboxed: the sheet shows a degraded card, no provisioning
#else
        let desktopInstalled = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
        mcpStatus = await MCPProvision.currentStatus(desktopInstalled: desktopInstalled)
#endif
    }

    /// One-click: resolve node, stage the server, register Claude Code + Desktop,
    /// then ensure a psyche exists. All Process/file work is off the main actor.
    func enableMCP() async {
#if MAS
        return
#else
        mcpStatus.phase = .working
        guard let node = await MCPProvision.resolveExecutable("node") else {
            mcpStatus.node = .missing; mcpStatus.phase = .needsNode; return
        }
        mcpStatus.node = .found(node)
        let dist: String
        do { dist = try await MCPProvision.ensureStaged() }
        catch {
            mcpStatus.phase = .error("Couldn't prepare the server: \(error.localizedDescription)")
            return
        }
        mcpStatus.distPath = dist

        if let claude = await MCPProvision.resolveExecutable("claude") {
            mcpStatus.claudeCode = await MCPProvision.registerClaudeCode(node: node, dist: dist, claude: claude)
        } else {
            mcpStatus.claudeCode = .cliMissing
        }
        let desktopInstalled = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
        mcpStatus.desktopInstalled = desktopInstalled
        mcpStatus.claudeDesktop = await MCPProvision.registerClaudeDesktop(node: node, dist: dist, desktopInstalled: desktopInstalled)

        await syncPsycheToMCP()   // ensure ~/.glia/psyche.md exists so the server has data
        // Don't claim success if nothing was actually registered (no Claude CLI AND
        // no Claude Desktop) — surface it instead of a silent green ".done".
        if mcpStatus.claudeCode.isRegistered || mcpStatus.claudeDesktop.isRegistered {
            mcpStatus.phase = .done
        } else {
            mcpStatus.phase = .error("No MCP client was registered — Claude Code CLI not found and Claude Desktop not installed.")
        }
#endif
    }

    /// Preview what the glia-context MCP would inject for a task (identity +
    /// retrieval), by running the server's --explain CLI. Direct build only.
    func previewInjection(task: String) async {
#if MAS
        return
#else
        let t = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        previewingInjection = true
        injectionPreview = await MCPProvision.previewInjection(task: t)
            ?? "Couldn't run the preview — is the glia-context server built and Node installed? (Enable MCP…)"
        previewingInjection = false
#endif
    }

    /// Drop a stale injection preview. The sheet's `previewTask` field is view-local
    /// @State that resets to "" every time the sheet is re-presented, but the preview
    /// itself lives here and would otherwise linger — showing a manifest with no
    /// visible originating query (and possibly reflecting a since-changed psyche.md).
    /// Clear it on sheet appear so a preview only ever shows for a task typed this session.
    func clearInjectionPreview() {
        injectionPreview = nil
    }

    func toggleStarSelected() { if let s = selectedIndex { toggleStar(s) } }

    /// One-click identity core: star the self-page + essays (ContextBundle
    /// identityRank ≤ 1) — the concentrated core the dose-response found reaches
    /// ~95% of the full psyche's blind ranking. Gives a new user a strong psyche
    /// to inject without hunting. Returns how many nodes were added.
    @discardableResult
    func starIdentityCore() -> Int {
        guard !demoActive else { return 0 }
        let core = graph.nodes.filter { ContextBundle.identityRank($0) <= 1 }.map(\.slug)
        guard !core.isEmpty else { return 0 }
        let before = starredSlugs.count
        starredSlugs.formUnion(core)
        UserDefaults.standard.set(Array(starredSlugs), forKey: "starredSlugs")
        sceneDirty()
        view?.requestDraw()
        scheduleLiveSync()
        return starredSlugs.count - before
    }

    var starredCount: Int { starredSlugs.count }

    // MARK: context bundle ("vault of mind" export)

    /// Nodes that would be included for a given scope, in a stable order.
    func contextNodes(_ scope: ContextScope) -> [BrainNode] {
        switch scope {
        case .collection:
            // starred order preserved by recency of update, stable set
            return graph.nodes.filter { starredSlugs.contains($0.slug) }
                .sorted { ($0.updatedDate ?? .distantPast) > ($1.updatedDate ?? .distantPast) }
        case .selection:
            guard let sel = selectedIndex else { return [] }
            var idxs = [sel] + graph.neighbors[sel].map { Int($0) }
            idxs = Array(Set(idxs)).sorted()
            return idxs.map { graph.nodes[$0] }
        case .identity:
            // Psyche map, not an ops dump: keep identity-content types, drop
            // operational streams (briefs, action queues, status reports,
            // raw provenance) — the "who I am", not "what happened today".
            let opsPrefixes = ["briefs/", "actions/", "reports/", "sources/",
                               "raw/", "orchestration/", "plans/", "atoms/"]
            let kept = graph.nodes.filter { node in
                enabledSources.contains(node.source)
                    && ContextBundle.identityTypes.contains(node.type)
                    && !opsPrefixes.contains(where: { node.slug.hasPrefix($0) })
            }
            // Front-load the highest-signal identity so an injected "who I
            // am" leads with the core: the self-page, then essays
            // (originals), concepts, people, then the rest — recency within.
            return kept.sorted { a, b in
                let ra = ContextBundle.identityRank(a), rb = ContextBundle.identityRank(b)
                if ra != rb { return ra < rb }
                return (a.updatedDate ?? .distantPast) > (b.updatedDate ?? .distantPast)
            }
        case .everything:
            return graph.nodes.filter { enabledSources.contains($0.source) }
        }
    }

    func contextHeader(_ scope: ContextScope) -> String {
        switch scope {
        case .collection: return "Context — my collection"
        case .selection:  return "Context — \(selectedNode?.displayTitle ?? "selection")"
        case .identity:   return "Context — identity map"
        case .everything: return "Context — full brain"
        }
    }

    /// Resolve each node's source-id → on-disk mirror base on the main actor
    /// (`BrainLocation` is @MainActor); the map (Sendable) is then handed to the
    /// nonisolated builder so it can read files off the main actor.
    func sourceMirrors(for nodes: [BrainNode]) -> [String: URL] {
        var m: [String: URL] = [:]
        for src in Set(nodes.map(\.source)) where m[src] == nil {
            if let url = BrainLocation.sourceMirror(for: src) { m[src] = url }
        }
        return m
    }

    func buildContextBundle(_ scope: ContextScope) -> ContextBundle {
        let nodes = contextNodes(scope)
        return ContextBundle.build(nodes: nodes, header: contextHeader(scope),
                                   mirrors: sourceMirrors(for: nodes))
    }

    /// Off-main-actor build: gather the nodes + header + mirrors on the main
    /// actor (fast, in-memory), then do the file I/O on a background task so an
    /// interactive caller (a star tap, the export sheet) never blocks on disk.
    func buildContextBundleOffMain(_ scope: ContextScope) async -> ContextBundle {
        let nodes = contextNodes(scope)
        let header = contextHeader(scope)
        let mirrors = sourceMirrors(for: nodes)
        return await Task.detached {
            ContextBundle.build(nodes: nodes, header: header, mirrors: mirrors)
        }.value
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
        // glow breathing — but under Reduce Motion the glow is static, and selectedIndex's
        // didSet already redraws the selection once, so don't spin continuous rendering.
        if selectedIndex != nil && !Camera.reduceMotion { setContinuousRendering(true) }
    }

    func flyToNode(atView p: SIMD2<Float>, viewport: SIMD2<Float>) {
        guard let i = pick(atView: p, viewport: viewport) else { return }
        select(index: i)
    }

    func select(index: Int) {
        selectedIndex = index
        renderer.camera.fly(to: positions[index], zoom: max(renderer.camera.zoom, 9))
        // Under Reduce Motion the flight snaps (Camera.fly) and the glow is static, so a
        // selection isn't a reason to keep redrawing; selectedIndex's didSet draws it once.
        if !Camera.reduceMotion { setContinuousRendering(true) }
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
            // Match the HUMANIZED name each row actually shows too — a page
            // displayed as "David Worthy" (empty/echoed title, slug
            // people-david-worthy-<hash>) was otherwise unfindable by typing it.
            let display = n.displayTitle.lowercased()
            if slug.hasPrefix(q) || title.hasPrefix(q) || display.hasPrefix(q) { hits.append((i, 0)) }
            else if slug.contains(q) || title.contains(q) || display.contains(q) { hits.append((i, 1)) }
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
