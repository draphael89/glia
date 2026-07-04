import Foundation
import Metal
import MetalKit
import simd

/// Everything the GPU needs for one frame, produced by AppModel.
struct RenderScene: Sendable {
    var positions: [SIMD2<Float>] = []
    var radii: [Float] = []
    var colors: [SIMD4<Float>] = []
    var flags: [Float] = []                 // bit0 selected, bit1 hovered, bit2 dimmed
    var visible: [Bool] = []
    var edges: [(Int32, Int32)] = []
    var edgeColors: [SIMD4<Float>] = []
    var dimStrength: Float = 0
    var version: Int = 0                    // bump to signal buffer rebuild
}

@MainActor
final class GraphRenderer: NSObject, MTKViewDelegate {

    // Mirror of the Metal structs — layouts must match Graph.metal.
    private struct Uniforms {
        var viewport: SIMD2<Float>
        var center: SIMD2<Float>
        var zoom: Float
        var time: Float
        var dimStrength: Float
        var _pad: Float = 0
    }
    private struct NodeInstance {
        var position: SIMD2<Float>
        var radius: Float
        var flags: Float
        var color: SIMD4<Float>
    }
    private struct EdgeInstance {
        var a: SIMD2<Float>
        var b: SIMD2<Float>
        var color: SIMD4<Float>
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private var bgPipeline: MTLRenderPipelineState!
    private var nodePipeline: MTLRenderPipelineState!
    private var edgePipeline: MTLRenderPipelineState!

    private var nodeBuffer: MTLBuffer?
    private var edgeBuffer: MTLBuffer?
    private var nodeCount = 0
    private var edgeCount = 0
    private var builtVersion = -1

    var camera = Camera()
    var scene = RenderScene()
    private let startTime = CACurrentMediaTime()
    /// Last frame's GPU time in ms (drives the debug HUD + perf budget).
    private(set) var lastGPUms: Double = 0

    /// Set by the view each frame; lets the app pause rendering when idle.
    var onFrame: ((Float) -> Void)?

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        super.init()
        do { try buildPipelines() } catch {
            assertionFailure("Metal pipeline build failed: \(error)")
            return nil
        }
    }

    private func buildPipelines() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw NSError(domain: "Glia", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "missing default Metal library"])
        }
        func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.rasterSampleCount = 4
            let att = d.colorAttachments[0]!
            att.pixelFormat = .bgra8Unorm
            att.isBlendingEnabled = true
            // premultiplied-alpha over
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .one
            att.sourceAlphaBlendFactor = .one
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: d)
        }
        bgPipeline = try pipeline("bg_vertex", "bg_fragment")
        edgePipeline = try pipeline("edge_vertex", "edge_fragment")
        nodePipeline = try pipeline("node_vertex", "node_fragment")
    }

    // MARK: buffers

    private func rebuildBuffersIfNeeded() {
        guard scene.version != builtVersion else { return }
        builtVersion = scene.version

        var nodes: [NodeInstance] = []
        nodes.reserveCapacity(scene.positions.count)
        for i in 0..<scene.positions.count where scene.visible.isEmpty || scene.visible[i] {
            nodes.append(NodeInstance(position: scene.positions[i],
                                      radius: scene.radii[i],
                                      flags: scene.flags[i],
                                      color: scene.colors[i]))
        }
        nodeCount = nodes.count
        nodeBuffer = nodes.isEmpty ? nil :
            device.makeBuffer(bytes: nodes, length: MemoryLayout<NodeInstance>.stride * nodes.count)

        var edges: [EdgeInstance] = []
        edges.reserveCapacity(scene.edges.count)
        for (k, (s, t)) in scene.edges.enumerated() {
            let si = Int(s), ti = Int(t)
            if !scene.visible.isEmpty && (!scene.visible[si] || !scene.visible[ti]) { continue }
            edges.append(EdgeInstance(a: scene.positions[si],
                                      b: scene.positions[ti],
                                      color: scene.edgeColors[k]))
        }
        edgeCount = edges.count
        edgeBuffer = edges.isEmpty ? nil :
            device.makeBuffer(bytes: edges, length: MemoryLayout<EdgeInstance>.stride * edges.count)
    }

    // MARK: MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { drawIsolated(in: view) }
    }

    private func drawIsolated(in view: MTKView) {
        let dt = Float(1.0 / Double(max(view.preferredFramesPerSecond, 30)))
        camera.tick(dt: dt)
        onFrame?(dt)

        rebuildBuffersIfNeeded()

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        let size = view.drawableSize
        var zoomedCamera = camera
        zoomedCamera.zoom = camera.zoom * Float(view.window?.backingScaleFactor ?? 2)
        encodeScene(into: enc,
                    viewport: SIMD2(Float(size.width), Float(size.height)),
                    camera: zoomedCamera,
                    forceRebuild: false)
        enc.endEncoding()
        cmd.addCompletedHandler { [weak self] buf in
            let ms = (buf.gpuEndTime - buf.gpuStartTime) * 1000
            Task { @MainActor in self?.lastGPUms = ms }
        }
        cmd.present(drawable)
        cmd.commit()
    }

    /// Shared by the live view and the offscreen snapshot path.
    func encodeScene(into enc: MTLRenderCommandEncoder,
                     viewport: SIMD2<Float>,
                     camera drawCamera: Camera,
                     forceRebuild: Bool) {
        if forceRebuild { builtVersion = -1 }
        rebuildBuffersIfNeeded()

        var uniforms = Uniforms(
            viewport: viewport,
            center: drawCamera.center,
            zoom: drawCamera.zoom,
            time: Float(CACurrentMediaTime() - startTime),
            dimStrength: scene.dimStrength
        )

        enc.setRenderPipelineState(bgPipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // Edge LOD: edges are the dominant GPU cost at scale (~83% at 100k)
        // because a dense web crisscrosses the whole viewport. When zoomed
        // out over a huge graph the web is a near-uniform haze, so a
        // representative prefix (edges are in ~spatially-random link order)
        // looks identical for a fraction of the fill. Zoomed in, few edges
        // are on screen and cost nothing, so draw them all.
        var drawnEdges = edgeCount
        if edgeCount > 30_000 && drawCamera.zoom < 3.0 {
            let t = max(0, min(1, drawCamera.zoom / 3.0))   // 0 far … 1 near
            drawnEdges = 30_000 + Int(Float(edgeCount - 30_000) * t)
        }
        if let edgeBuffer, drawnEdges > 0 {
            enc.setRenderPipelineState(edgePipeline)
            enc.setVertexBuffer(edgeBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: drawnEdges)
        }
        if let nodeBuffer, nodeCount > 0 {
            enc.setRenderPipelineState(nodePipeline)
            enc.setVertexBuffer(nodeBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: nodeCount)
        }
    }
}
