import MetalKit
import QuartzCore
import SwiftUI

struct MetalView: NSViewRepresentable {
    var fpsMonitor: FPSMonitor
    var viewport: FractalViewport

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> InteractiveMTKView {
        let view = InteractiveMTKView()
        view.viewport = viewport
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this Mac.")
        }
        view.device = device
        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.maximumDrawableCount = 2
            metalLayer.allowsNextDrawableTimeout = true
        }

        let renderer = MetalRenderer(
            device: device,
            pixelFormat: view.colorPixelFormat,
            fpsMonitor: fpsMonitor,
            viewport: viewport
        )
        context.coordinator.renderer = renderer
        context.coordinator.metalView = view
        view.renderer = renderer
        view.delegate = renderer

        return view
    }

    func updateNSView(_ nsView: InteractiveMTKView, context: Context) {
        nsView.viewport = viewport
        nsView.preferredFramesPerSecond = Int(viewport.fpsCap.rounded())
        nsView.scheduleRedrawIfNeeded()
    }

    static func dismantleNSView(_ nsView: InteractiveMTKView, coordinator: Coordinator) {
        coordinator.renderer = nil
        coordinator.metalView = nil
        nsView.teardown()
    }

    final class Coordinator {
        var renderer: MetalRenderer?
        weak var metalView: InteractiveMTKView?
    }
}

final class InteractiveMTKView: MTKView {
    var viewport: FractalViewport?
    weak var renderer: MetalRenderer?

    private(set) var renderQuality: Float = 1.0

    private var isDragging = false
    private var lastDragLocation: CGPoint = .zero
    private var dragMode: DragMode = .none
    private var idleTimer: Timer?
    private var appObservers: [NSObjectProtocol] = []

    private enum DragMode {
        case none
        case pan
        case rotateCamera
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            window?.makeFirstResponder(self)
            registerAppObservers()
            scheduleRedraw()
        } else {
            teardown()
        }
    }

    deinit {
        teardown()
    }

    func teardown() {
        guard delegate != nil || device != nil else { return }

        idleTimer?.invalidate()
        idleTimer = nil
        unregisterAppObservers()

        isPaused = true
        enableSetNeedsDisplay = false
        delegate = nil
        renderer = nil
        viewport = nil

        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.delegate = nil
            metalLayer.device = nil
        }
        device = nil
    }

    func beginInteraction() {
        idleTimer?.invalidate()
        renderQuality = viewport?.livePreview == true ? 0.55 : 1.0
        applyDrawableSize()
        isPaused = false
    }

    func endInteractionSoon() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.restoreRenderQuality()
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    func redrawOnce() {
        scheduleRedraw()
    }

    func scheduleRedrawIfNeeded() {
        scheduleRedraw()
    }

    private func scheduleRedraw() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        applyDrawableSize()
        setNeedsDisplay(bounds)
    }

    private func pauseRendering() {
        renderQuality = 1.0
        applyDrawableSize()
        isPaused = true
        redrawOnce()
    }

    private func restoreRenderQuality() {
        renderQuality = 1.0
        applyDrawableSize()
        isPaused = false
        scheduleRedraw()
    }

    private func applyDrawableSize() {
        guard let metalLayer = layer as? CAMetalLayer, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let resolutionScale = min(max(CGFloat(viewport?.resolutionScale ?? 1), 0.35), 1.5)
        let pixelScale = CGFloat(window?.backingScaleFactor ?? 1) * CGFloat(renderQuality) * resolutionScale
        metalLayer.drawableSize = CGSize(
            width: max(1, bounds.width * pixelScale),
            height: max(1, bounds.height * pixelScale)
        )
    }

    override func layout() {
        super.layout()
        scheduleRedraw()
    }

    private func registerAppObservers() {
        guard appObservers.isEmpty else { return }

        let center = NotificationCenter.default
        appObservers = [
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.teardown()
            },
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.pauseRendering()
            },
            center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.restoreRenderingIfVisible()
            },
            center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.updateRenderingForVisibility()
            },
            center.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.teardown()
            },
        ]
    }

    private func unregisterAppObservers() {
        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appObservers.removeAll()
    }

    private func updateRenderingForVisibility() {
        guard let window, !window.isMiniaturized else {
            pauseRendering()
            return
        }

        if window.occlusionState.contains(.visible) {
            restoreRenderingIfVisible()
        } else {
            pauseRendering()
        }
    }

    private func restoreRenderingIfVisible() {
        guard let window, !window.isMiniaturized, window.occlusionState.contains(.visible) else {
            return
        }

        restoreRenderQuality()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let viewport else {
            super.scrollWheel(with: event)
            return
        }

        beginInteraction()

        let location = convert(event.locationInWindow, from: nil)
        let zoomBase = max(0.75, min(0.98, 1.0 - Float(viewport.zoomSpeed)))
        let factor = pow(zoomBase, Float(event.scrollingDeltaY))
        viewport.zoom(
            by: factor,
            anchorScreen: screenPointInPixels(location),
            viewSize: viewSizeInPixels
        )
        endInteractionSoon()
    }

    override func magnify(with event: NSEvent) {
        guard let viewport else {
            super.magnify(with: event)
            return
        }

        beginInteraction()

        let location = convert(event.locationInWindow, from: nil)
        viewport.zoom(
            by: Float(1.0 - event.magnification),
            anchorScreen: screenPointInPixels(location),
            viewSize: viewSizeInPixels
        )
        endInteractionSoon()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            viewport?.reset()
            redrawOnce()
            return
        }

        beginInteraction()
        isDragging = true
        dragMode = viewport?.isSpatial == true ? .rotateCamera : .pan
        lastDragLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let viewport else { return }

        beginInteraction()

        let location = convert(event.locationInWindow, from: nil)
        let delta = screenPointInPixels(location) - screenPointInPixels(lastDragLocation)
        switch dragMode {
        case .none:
            break
        case .pan:
            viewport.pan(screenDelta: delta, viewSize: viewSizeInPixels)
        case .rotateCamera:
            viewport.rotateCamera(screenDelta: delta, viewSize: viewSizeInPixels)
        }
        lastDragLocation = location
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        dragMode = .none
        endInteractionSoon()
    }

    override func rightMouseDown(with event: NSEvent) {
        beginInteraction()
        isDragging = true
        dragMode = .pan
        lastDragLocation = convert(event.locationInWindow, from: nil)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: isDragging ? .closedHand : .openHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetCursorRects()
    }

    override func mouseEntered(with event: NSEvent) {
        resetCursorRects()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override var isHidden: Bool {
        get { super.isHidden }
        set {
            super.isHidden = newValue
            if newValue {
                pauseRendering()
            }
        }
    }

    private var backingScale: Float {
        Float(window?.backingScaleFactor ?? 1)
    }

    private var viewSizeInPixels: SIMD2<Float> {
        SIMD2(Float(bounds.width), Float(bounds.height)) * backingScale
    }

    private func screenPointInPixels(_ point: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(point.x), Float(point.y)) * backingScale
    }
}
