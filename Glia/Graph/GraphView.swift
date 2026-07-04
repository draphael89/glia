import SwiftUI
import MetalKit
import Quartz
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

        // VoiceOver: the canvas is one element describing the brain;
        // selection changes are announced (see announceSelection).
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Brain graph")
    }

    /// Called by AppModel when the selection changes — VoiceOver users
    /// hear what the camera flew to.
    func announceSelection(_ summary: String?) {
        setAccessibilityValue(summary ?? "nothing selected")
        guard let summary else { return }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: summary,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
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
        switch event.specialKey {
        case .some(.leftArrow):  model.step(direction: SIMD2(-1, 0)); return
        case .some(.rightArrow): model.step(direction: SIMD2(1, 0)); return
        case .some(.upArrow):    model.step(direction: SIMD2(0, -1)); return
        case .some(.downArrow):  model.step(direction: SIMD2(0, 1)); return
        default: break
        }
        switch event.charactersIgnoringModifiers {
        case "f": model.fitView()
        case " ": toggleQuickLook()                          // space
        case String(UnicodeScalar(27)): model.clearFocus()   // esc
        default: super.keyDown(with: event)
        }
    }

    // MARK: Quick Look (Space on a selected node)

    private func toggleQuickLook() {
        guard model.selectedFileURL != nil,
              let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

// QLPreviewPanel drives these on the main thread; the protocols predate
// Swift concurrency annotations.
extension GraphMTKView: @preconcurrency QLPreviewPanelDataSource,
                        @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        model.selectedFileURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        model.selectedFileURL as NSURL?
    }
}
