import Foundation
import AppKit
import Metal
import MetalKit
import simd
import UniformTypeIdentifiers

/// Offscreen rendering for automated visual verification.
/// `GLIA_SNAPSHOT=/path/out.png [GLIA_SNAPSHOT_FOCUS=slug]` renders one
/// settled frame to disk and exits — the pixel-iteration loop for CI
/// and agent-driven development.
extension GraphRenderer {

    func snapshotImage(size: CGSize, camera snapCamera: Camera) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        let msaaDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        msaaDesc.textureType = .type2DMultisample
        msaaDesc.sampleCount = 4
        msaaDesc.usage = .renderTarget
        msaaDesc.storageMode = .private

        let resolveDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        resolveDesc.usage = [.renderTarget, .shaderRead]

        guard let msaa = device.makeTexture(descriptor: msaaDesc),
              let resolve = device.makeTexture(descriptor: resolveDesc),
              let queue = device.makeCommandQueue(),
              let cmd = queue.makeCommandBuffer() else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = resolve
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.043, green: 0.051, blue: 0.071, alpha: 1)

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encodeScene(into: enc,
                    viewport: SIMD2(Float(w), Float(h)),
                    camera: snapCamera,
                    forceRebuild: true)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        // read back
        let bytesPerRow = w * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        resolve.getBytes(&bytes, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: cs, bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                         UTType.png.identifier as CFString,
                                                         1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// Camera that frames the given positions in a viewport of `size`.
    static func fittingCamera(positions: [SIMD2<Float>], visible: [Bool],
                              size: CGSize, padding: Float = 80) -> Camera {
        var lo = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var hi = -lo
        var any = false
        for i in 0..<positions.count where visible.isEmpty || visible[i] {
            lo = simd_min(lo, positions[i]); hi = simd_max(hi, positions[i]); any = true
        }
        var cam = Camera()
        guard any else { return cam }
        let span = simd_max(hi - lo, SIMD2<Float>(1, 1))
        let usable = SIMD2(Float(size.width) - padding * 2, Float(size.height) - padding * 2)
        cam.zoom = min(usable.x / span.x, usable.y / span.y)
        cam.center = (lo + hi) / 2
        return cam
    }
}
