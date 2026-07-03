import Foundation
import simd

/// Barnes-Hut force layout, run in settle-bursts off the main thread.
///
/// Glia deliberately does NOT run live physics as a render loop:
/// a brain viewer's core value is a *stable spatial memory*. The engine
/// runs a burst (alpha-cooled velocity Verlet, d3-force-style) until the
/// system settles, then freezes. New nodes are seeded at the barycenter
/// of their neighbors and only their local neighborhood is relaxed.
enum LayoutEngine {

    struct Config: Sendable {
        var repulsion: Float = 22.0          // many-body strength
        var theta: Float = 0.85              // BH opening criterion
        var springLength: Float = 26.0       // link rest length
        var springStiffness: Float = 0.28
        var gravity: Float = 0.035           // pull toward origin
        var velocityDecay: Float = 0.82
        var alphaStart: Float = 1.0
        var alphaMin: Float = 0.003
        var alphaDecay: Float = 0.0228       // ~300 iterations to settle
        var maxIterations: Int = 600
    }

    /// Deterministic seed positions: linked nodes spiral out from center,
    /// orphans form a calm outer ring — hash-stable so every launch of the
    /// same brain starts from the same sky.
    static func seedPositions(for graph: BrainGraph) -> [SIMD2<Float>] {
        let n = graph.nodes.count
        var pos = [SIMD2<Float>](repeating: .zero, count: n)
        let golden = Float(2.399963229728653)  // golden angle
        var linkedRank = 0, orphanRank = 0
        let linkedCount = graph.degree.lazy.filter { $0 > 0 }.count
        let orphanRingRadius = 60 + 8 * Float(linkedCount).squareRoot()
        for i in 0..<n {
            var h = UInt64(bitPattern: Int64(graph.nodes[i].slug.stableHash))
            h = (h ^ (h >> 33)) &* 0xff51afd7ed558ccd
            let jitter = Float(h % 1000) / 1000.0 - 0.5
            if graph.degree[i] > 0 {
                let r = 6 * Float(linkedRank).squareRoot() + jitter * 3
                let a = golden * Float(linkedRank) + jitter * 0.2
                pos[i] = SIMD2(r * cos(a), r * sin(a))
                linkedRank += 1
            } else {
                let r = orphanRingRadius * (1.0 + 0.35 * jitter)
                let a = golden * Float(orphanRank) + jitter
                pos[i] = SIMD2(r * cos(a), r * sin(a))
                orphanRank += 1
            }
        }
        return pos
    }

    /// Run one settle burst. `pinned[i] == true` nodes do not move
    /// (used for incremental relaxation around insertions).
    /// `onTick` is called on the calling task every `tickEvery` iterations
    /// with a snapshot — stream it to the renderer for the live settle.
    static func settle(
        graph: BrainGraph,
        start: [SIMD2<Float>],
        pinned: [Bool]? = nil,
        config: Config = Config(),
        tickEvery: Int = 3,
        onTick: (@Sendable ([SIMD2<Float>], Float) -> Void)? = nil
    ) -> [SIMD2<Float>] {
        let n = graph.nodes.count
        guard n > 0 else { return [] }
        var pos = start
        var vel = [SIMD2<Float>](repeating: .zero, count: n)
        var alpha = config.alphaStart
        let deg = graph.degree
        var iter = 0

        while alpha > config.alphaMin && iter < config.maxIterations {
            let tree = QuadTree(positions: pos, masses: deg.map { Float(1 + $0) })

            // Many-body repulsion (Barnes-Hut)
            for i in 0..<n {
                let f = tree.repulsion(at: pos[i], skip: i, theta: config.theta)
                vel[i] += f * (config.repulsion * alpha)
            }
            // Link springs
            for (s, t) in graph.linkIndices {
                let si = Int(s), ti = Int(t)
                let d = pos[ti] - pos[si]
                let dist = max(simd_length(d), 0.01)
                let stretch = (dist - config.springLength) / dist
                let f = d * (stretch * config.springStiffness * alpha)
                // heavier (higher-degree) nodes move less
                let ws = Float(deg[ti] + 1) / Float(deg[si] + deg[ti] + 2)
                let wt = 1 - ws
                vel[si] += f * ws
                vel[ti] -= f * wt
            }
            // Gravity toward origin (keeps disconnected clusters from drifting)
            for i in 0..<n {
                vel[i] -= pos[i] * (config.gravity * alpha)
            }
            // Integrate
            for i in 0..<n {
                if let pinned, pinned[i] { vel[i] = .zero; continue }
                vel[i] *= config.velocityDecay
                pos[i] += vel[i]
            }

            alpha += (0 - alpha) * config.alphaDecay
            iter += 1
            if let onTick, iter % tickEvery == 0 { onTick(pos, alpha) }
        }
        onTick?(pos, 0)
        return pos
    }

    /// Seed new nodes at the barycenter of their already-placed neighbors
    /// (plus a small deterministic offset), matching gbrain's mental model:
    /// new knowledge appears *next to what it's about*.
    static func seedInsertions(
        graph: BrainGraph,
        placed: [Int: SIMD2<Float>]   // node.id -> existing position
    ) -> [SIMD2<Float>] {
        var pos = seedPositions(for: graph)
        for (i, node) in graph.nodes.enumerated() {
            if let p = placed[node.id] { pos[i] = p; continue }
            let neigh = graph.neighbors[i]
            var acc = SIMD2<Float>.zero
            var count: Float = 0
            for j in neigh {
                if let p = placed[graph.nodes[Int(j)].id] { acc += p; count += 1 }
            }
            if count > 0 {
                let h = Float(node.slug.stableHash % 628) / 100.0
                pos[i] = acc / count + SIMD2(cos(h), sin(h)) * 9
            }
        }
        return pos
    }
}

// MARK: - Quadtree (flat-array Barnes-Hut)

struct QuadTree {
    private struct Cell {
        var centerOfMass = SIMD2<Float>.zero
        var mass: Float = 0
        var origin: SIMD2<Float>
        var size: Float
        var children: (Int32, Int32, Int32, Int32) = (-1, -1, -1, -1)
        var body: Int32 = -1        // leaf's single body, -1 if none/internal
        var isLeaf = true
    }

    private var cells: [Cell] = []
    private let positions: [SIMD2<Float>]
    private let masses: [Float]

    init(positions: [SIMD2<Float>], masses: [Float]) {
        self.positions = positions
        self.masses = masses
        guard !positions.isEmpty else { return }
        var lo = positions[0], hi = positions[0]
        for p in positions { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let size = max(hi.x - lo.x, hi.y - lo.y, 1)
        cells.reserveCapacity(positions.count * 2)
        cells.append(Cell(origin: lo, size: size))
        for i in 0..<positions.count { insert(body: Int32(i), into: 0, depth: 0) }
    }

    private mutating func insert(body: Int32, into cellIndex: Int, depth: Int) {
        let p = positions[Int(body)]
        let m = masses[Int(body)]
        // update aggregate
        let total = cells[cellIndex].mass + m
        cells[cellIndex].centerOfMass =
            (cells[cellIndex].centerOfMass * cells[cellIndex].mass + p * m) / total
        cells[cellIndex].mass = total

        if cells[cellIndex].isLeaf {
            if cells[cellIndex].body == -1 {
                cells[cellIndex].body = body
                return
            }
            if depth > 24 { return }   // coincident points guard
            let existing = cells[cellIndex].body
            cells[cellIndex].body = -1
            cells[cellIndex].isLeaf = false
            descend(body: existing, from: cellIndex, depth: depth)
            descend(body: body, from: cellIndex, depth: depth)
        } else {
            descend(body: body, from: cellIndex, depth: depth)
        }
    }

    private mutating func descend(body: Int32, from cellIndex: Int, depth: Int) {
        let p = positions[Int(body)]
        let half = cells[cellIndex].size / 2
        let o = cells[cellIndex].origin
        let right = p.x >= o.x + half
        let top = p.y >= o.y + half
        let quadrant = (top ? 2 : 0) + (right ? 1 : 0)
        var childIndex: Int32
        switch quadrant {
        case 0: childIndex = cells[cellIndex].children.0
        case 1: childIndex = cells[cellIndex].children.1
        case 2: childIndex = cells[cellIndex].children.2
        default: childIndex = cells[cellIndex].children.3
        }
        if childIndex == -1 {
            let origin = SIMD2(o.x + (right ? half : 0), o.y + (top ? half : 0))
            cells.append(Cell(origin: origin, size: half))
            childIndex = Int32(cells.count - 1)
            switch quadrant {
            case 0: cells[cellIndex].children.0 = childIndex
            case 1: cells[cellIndex].children.1 = childIndex
            case 2: cells[cellIndex].children.2 = childIndex
            default: cells[cellIndex].children.3 = childIndex
            }
        }
        insert(body: body, into: Int(childIndex), depth: depth + 1)
    }

    /// Net repulsive force on a point from all bodies (except `skip`).
    func repulsion(at p: SIMD2<Float>, skip: Int, theta: Float) -> SIMD2<Float> {
        guard !cells.isEmpty else { return .zero }
        var force = SIMD2<Float>.zero
        var stack: [Int32] = [0]
        stack.reserveCapacity(64)
        while let idx = stack.popLast() {
            let cell = cells[Int(idx)]
            if cell.mass == 0 { continue }
            let d = p - cell.centerOfMass
            let distSq = max(simd_length_squared(d), 0.01)
            if cell.isLeaf {
                if cell.body == Int32(skip) || cell.body == -1 { continue }
                force += d * (cell.mass / distSq)
            } else if cell.size * cell.size < theta * theta * distSq {
                force += d * (cell.mass / distSq)
            } else {
                let c = cell.children
                if c.0 != -1 { stack.append(c.0) }
                if c.1 != -1 { stack.append(c.1) }
                if c.2 != -1 { stack.append(c.2) }
                if c.3 != -1 { stack.append(c.3) }
            }
        }
        return force
    }
}

extension String {
    /// Stable across launches (unlike `hashValue`).
    var stableHash: Int {
        var h: UInt64 = 5381
        for b in utf8 { h = (h << 5) &+ h &+ UInt64(b) }
        return Int(bitPattern: UInt(truncatingIfNeeded: h))
    }
}
