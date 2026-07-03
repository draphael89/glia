import AppKit
import Foundation
import simd

/// 2D camera over the world plane. `zoom` is pixels-per-world-unit.
/// Supports critically-damped spring flights (fit view, fly-to-node)
/// so every camera move feels like one continuous gesture.
struct Camera {
    var center = SIMD2<Float>(0, 0)
    var zoom: Float = 4.0

    // spring targets (nil == at rest)
    private var targetCenter: SIMD2<Float>?
    private var targetZoom: Float?
    private var velCenter = SIMD2<Float>.zero
    private var velZoom: Float = 0

    var isAnimating: Bool { targetCenter != nil || targetZoom != nil }
    /// Where the camera is heading (== current values when at rest).
    var centerTarget: SIMD2<Float> { targetCenter ?? center }
    var zoomTarget: Float { targetZoom ?? zoom }

    // MARK: transforms

    func worldToView(_ p: SIMD2<Float>, viewport: SIMD2<Float>) -> SIMD2<Float> {
        (p - center) * zoom + viewport / 2
    }

    func viewToWorld(_ p: SIMD2<Float>, viewport: SIMD2<Float>) -> SIMD2<Float> {
        (p - viewport / 2) / zoom + center
    }

    // MARK: gestures

    mutating func pan(byViewDelta d: SIMD2<Float>) {
        cancelFlight()
        center -= d / zoom
    }

    /// Zoom anchored at a view-space point: the world point under the
    /// cursor stays exactly under the cursor.
    mutating func zoom(by factor: Float, anchorView: SIMD2<Float>, viewport: SIMD2<Float>) {
        cancelFlight()
        let anchorWorld = viewToWorld(anchorView, viewport: viewport)
        zoom = min(max(zoom * factor, 0.05), 400)
        center = anchorWorld - (anchorView - viewport / 2) / zoom
    }

    // MARK: flights

    mutating func fly(to newCenter: SIMD2<Float>, zoom newZoom: Float? = nil) {
        if Camera.reduceMotion {
            center = newCenter
            if let newZoom { zoom = min(max(newZoom, 0.05), 400) }
            cancelFlight()
            return
        }
        targetCenter = newCenter
        if let newZoom { targetZoom = min(max(newZoom, 0.05), 400) }
    }

    /// Honors the system accessibility setting; flights become cuts.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    mutating func fit(bounds: (lo: SIMD2<Float>, hi: SIMD2<Float>), viewport: SIMD2<Float>, padding: Float = 90) {
        let size = simd_max(bounds.hi - bounds.lo, SIMD2<Float>(1, 1))
        let usable = simd_max(viewport - SIMD2(padding * 2, padding * 2), SIMD2<Float>(64, 64))
        let z = min(usable.x / size.x, usable.y / size.y)
        fly(to: (bounds.lo + bounds.hi) / 2, zoom: min(max(z, 0.05), 60))
    }

    mutating func cancelFlight() {
        targetCenter = nil; targetZoom = nil
        velCenter = .zero; velZoom = 0
    }

    /// Advance the spring; returns true while still moving.
    @discardableResult
    mutating func tick(dt: Float) -> Bool {
        guard isAnimating else { return false }
        let stiffness: Float = 130
        let damping: Float = 2 * stiffness.squareRoot()   // critical damping

        if let t = targetCenter {
            let accel = (t - center) * stiffness - velCenter * damping
            velCenter += accel * dt
            center += velCenter * dt
            if simd_length(t - center) < 0.01 && simd_length(velCenter) < 0.05 {
                center = t; targetCenter = nil; velCenter = .zero
            }
        }
        if let t = targetZoom {
            // spring in log-space so zoom feels uniform
            let cur = log(zoom), tgt = log(t)
            let accel = (tgt - cur) * stiffness - velZoom * damping
            velZoom += accel * dt
            zoom = exp(cur + velZoom * dt)
            if abs(tgt - log(zoom)) < 0.0005 && abs(velZoom) < 0.005 {
                zoom = t; targetZoom = nil; velZoom = 0
            }
        }
        return isAnimating
    }
}
