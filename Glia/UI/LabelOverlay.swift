import SwiftUI
import simd

/// Native-text labels floating over the Metal canvas.
/// Labeling policy: the hovered and selected nodes always; then the
/// highest-degree visible nodes whose screen radius clears a zoom
/// threshold — so labels breathe in as you dive and vanish as you rise.
struct LabelOverlay: View {
    @Bindable var model: AppModel

    var body: some View {
        // cameraTick invalidates the canvas on every camera/scene change
        let _ = model.cameraTick
        Canvas { context, size in
            let cam = model.renderer.camera
            let viewport = SIMD2(Float(size.width), Float(size.height))
            let scene = model.renderer.scene
            guard model.positions.count == model.graph.nodes.count,
                  !model.positions.isEmpty else { return }

            struct Candidate { let index: Int; let priority: Float }
            var candidates: [Candidate] = []
            let n = model.graph.nodes.count
            let focusActive = model.selectedIndex != nil

            // The landmark hubs stay labeled at any zoom — they ARE the map.
            var landmark = Set<Int>()
            do {
                var byDegree: [Int] = []
                for i in 0..<n where scene.visible.isEmpty || scene.visible[i] {
                    byDegree.append(i)
                }
                byDegree.sort { model.graph.degree[$0] > model.graph.degree[$1] }
                landmark = Set(byDegree.prefix(14))
            }

            for i in 0..<n where scene.visible.isEmpty || scene.visible[i] {
                if !scene.flags.isEmpty && (Int(scene.flags[i]) & 16) != 0 { continue }  // dust
                let screenR = scene.radii[i] * cam.zoom
                let dimmed = !scene.flags.isEmpty && (Int(scene.flags[i]) & 4) != 0
                var priority: Float = -1
                if i == model.selectedIndex || i == model.hoveredIndex {
                    priority = .greatestFiniteMagnitude
                } else if focusActive && !dimmed {
                    priority = 1e9 + Float(model.graph.degree[i])   // whole neighborhood reads
                } else if landmark.contains(i) && screenR >= 2.0 {
                    priority = 1e6 + Float(model.graph.degree[i])
                } else if screenR >= 5.5 && !dimmed {
                    priority = Float(model.graph.degree[i]) * screenR
                }
                guard priority > 0 else { continue }
                let p = cam.worldToView(model.positions[i], viewport: viewport)
                guard p.x > -60, p.x < viewport.x + 60, p.y > -30, p.y < viewport.y + 30 else { continue }
                candidates.append(Candidate(index: i, priority: priority))
            }
            candidates.sort { $0.priority > $1.priority }

            var occupied: [CGRect] = []
            var drawn = 0
            for cand in candidates {
                guard drawn < 90 else { break }
                let i = cand.index
                let node = model.graph.nodes[i]
                let p = cam.worldToView(model.positions[i], viewport: viewport)
                let screenR = CGFloat(scene.radii[i] * cam.zoom)

                var title = node.title.isEmpty ? String(node.slug.split(separator: "/").last ?? "") : node.title
                title = title.collapsedDatePrefix
                if title.count > 34 { title = String(title.prefix(33)) + "…" }

                let isFocusNode = i == model.selectedIndex || i == model.hoveredIndex
                let dimmed = !scene.flags.isEmpty && (Int(scene.flags[i]) & 4) != 0
                if dimmed && !isFocusNode { continue }

                let fontSize: CGFloat = isFocusNode ? 12 : 10.5
                let text = Text(title)
                    .font(.system(size: fontSize, weight: isFocusNode ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isFocusNode ? 0.95 : 0.62))
                let resolved = context.resolve(text)
                let textSize = resolved.measure(in: CGSize(width: 260, height: 40))
                let origin = CGPoint(x: CGFloat(p.x) - textSize.width / 2,
                                     y: CGFloat(p.y) + screenR + 5)
                let rect = CGRect(origin: origin, size: textSize).insetBy(dx: -4, dy: -2)
                if occupied.contains(where: { $0.intersects(rect) }) { continue }
                occupied.append(rect)

                // soft plate for legibility over bright nodes
                if isFocusNode {
                    context.fill(Path(roundedRect: rect, cornerRadius: 5),
                                 with: .color(.black.opacity(0.45)))
                }
                context.draw(resolved, at: CGPoint(x: origin.x + textSize.width / 2,
                                                   y: origin.y + textSize.height / 2),
                             anchor: .center)
                drawn += 1
            }
        }
        .allowsHitTesting(false)
    }
}
