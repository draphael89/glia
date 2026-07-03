import SwiftUI
import MetalKit
import simd

/// The Metal canvas plus every trackpad/mouse gesture, wrapped for SwiftUI.
/// Interaction contract:
///   two-finger scroll → pan (with system momentum)
///   pinch            → zoom anchored under the cursor
///   left-drag        → pan
///   move             → hover pick
///   click            → select / clear
///   double-click     → fly to node
struct GraphView: NSViewRepresentable {
    @Bindable var model: AppModel

    func makeNSView(context: Context) -> GraphMTKView {
        let view = GraphMTKView(model: model)
        model.attach(view: view)
        return view
    }

    func updateNSView(_ view: GraphMTKView, context: Context) {
        view.requestDraw()
    }
}

@MainActor
final class GraphMTKView: MTKView {
    private unowned let model: AppModel
    private var trackingArea: NSTrackingArea?

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero, device: model.renderer.device)
        delegate = model.renderer
        colorPixelFormat = .bgra8Unorm
        sampleCount = 4
        clearColor = MTLClearColor(red: 0.043, green: 0.051, blue: 0.071, alpha: 1)
        preferredFramesPerSecond = 120
        // Render on demand; AppModel flips to continuous during animation.
        isPaused = true
        enableSetNeedsDisplay = true
        layer?.isOpaque = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    func requestDraw() { needsDisplay = true }

    // MARK: tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    private func viewPoint(_ event: NSEvent) -> SIMD2<Float> {
        let p = convert(event.locationInWindow, from: nil)
        // AppKit origin is bottom-left; camera/view space is top-left.
        return SIMD2(Float(p.x), Float(bounds.height - p.y))
    }

    private var viewportSize: SIMD2<Float> {
        SIMD2(Float(bounds.width), Float(bounds.height))
    }

    // MARK: gestures

    override func scrollWheel(with event: NSEvent) {
        let dx = Float(event.scrollingDeltaX)
        let dy = Float(event.scrollingDeltaY)
        if event.modifierFlags.contains(.command) {
            // ⌘-scroll zooms (mouse-wheel users)
            let factor = exp2(dy / 240)
            model.renderer.camera.zoom(by: factor, anchorView: viewPoint(event), viewport: viewportSize)
        } else {
            model.renderer.camera.pan(byViewDelta: SIMD2(-dx, -dy) * -1)
        }
        model.cameraChanged()
    }

    override func magnify(with event: NSEvent) {
        let factor = 1 + Float(event.magnification)
        model.renderer.camera.zoom(by: factor, anchorView: viewPoint(event), viewport: viewportSize)
        model.cameraChanged()
    }

    override func mouseMoved(with event: NSEvent) {
        model.hover(atView: viewPoint(event), viewport: viewportSize)
    }

    override func mouseExited(with event: NSEvent) {
        model.hover(atView: nil, viewport: viewportSize)
    }

    private var dragStarted = false

    override func mouseDown(with event: NSEvent) { dragStarted = false }

    override func mouseDragged(with event: NSEvent) {
        dragStarted = true
        model.renderer.camera.pan(byViewDelta: SIMD2(-Float(event.deltaX), -Float(event.deltaY)) * -1)
        model.cameraChanged()
    }

    override func mouseUp(with event: NSEvent) {
        guard !dragStarted else { return }
        if event.clickCount == 2 {
            model.flyToNode(atView: viewPoint(event), viewport: viewportSize)
        } else {
            model.click(atView: viewPoint(event), viewport: viewportSize)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "f": model.fitView()
        case String(UnicodeScalar(27)): model.clearFocus()   // esc
        default: super.keyDown(with: event)
        }
    }
}
