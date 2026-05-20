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
        updateShadertoyMouse(with: event, isDown: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let viewport else { return }

        beginInteraction()

        let location = convert(event.locationInWindow, from: nil)
        let delta = screenPointInPixels(location) - screenPointInPixels(lastDragLocation)
        updateShadertoyMouse(with: event, isDown: true)
        if !viewport.kind.usesShadertoyInput {
            switch dragMode {
            case .none:
                break
            case .pan:
                viewport.pan(screenDelta: delta, viewSize: viewSizeInPixels)
            case .rotateCamera:
                viewport.rotateCamera(screenDelta: delta, viewSize: viewSizeInPixels)
            }
        }
        lastDragLocation = location
    }

    override func mouseUp(with event: NSEvent) {
        updateShadertoyMouse(with: event, isDown: false)
        isDragging = false
        dragMode = .none
        endInteractionSoon()
    }

    override func rightMouseDown(with event: NSEvent) {
        beginInteraction()
        isDragging = true
        dragMode = .pan
        lastDragLocation = convert(event.locationInWindow, from: nil)
        updateShadertoyMouse(with: event, isDown: true)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let viewport, viewport.kind.usesShadertoyInput, setShadertoyKey(event, isDown: true) {
            beginInteraction()
            redrawOnce()
            return
        }

        guard let viewport, viewport.kind.isBlackHole else {
            super.keyDown(with: event)
            return
        }

        let stepMultiplier = event.modifierFlags.contains(.shift) ? 3.0 : 1.0
        let distanceStep = stepMultiplier * 1.25
        let angleStep = stepMultiplier * 3.0
        let pitchStep = stepMultiplier * 2.0

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w":
            viewport.cameraDistance = max(6, viewport.cameraDistance - distanceStep)
        case "s":
            viewport.cameraDistance = min(160, viewport.cameraDistance + distanceStep)
        case "a":
            viewport.rotationDegrees = viewport.wrappedCameraDegrees(viewport.rotationDegrees - angleStep)
        case "d":
            viewport.rotationDegrees = viewport.wrappedCameraDegrees(viewport.rotationDegrees + angleStep)
        case "r":
            viewport.cameraPitch = min(55, viewport.cameraPitch + pitchStep)
        case "f":
            viewport.cameraPitch = max(-55, viewport.cameraPitch - pitchStep)
        case "q":
            viewport.rotationDegrees = viewport.wrappedCameraDegrees(viewport.rotationDegrees - angleStep * 0.65)
        case "e":
            viewport.rotationDegrees = viewport.wrappedCameraDegrees(viewport.rotationDegrees + angleStep * 0.65)
        default:
            super.keyDown(with: event)
            return
        }

        beginInteraction()
        redrawOnce()
        endInteractionSoon()
    }

    override func keyUp(with event: NSEvent) {
        if let viewport, viewport.kind.usesShadertoyInput, setShadertoyKey(event, isDown: false) {
            beginInteraction()
            redrawOnce()
            endInteractionSoon()
            return
        }

        super.keyUp(with: event)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    private func updateShadertoyMouse(with event: NSEvent, isDown: Bool) {
        guard let viewport, viewport.kind.usesShadertoyInput else { return }

        let location = convert(event.locationInWindow, from: nil)
        let pixel = drawablePointInPixels(location)
        let buttonState = isDown ? 1.0 : -1.0
        viewport.shadertoyMouse = SIMD4(Double(pixel.x), Double(pixel.y), buttonState, buttonState)
    }

    @discardableResult
    private func setShadertoyKey(_ event: NSEvent, isDown: Bool) -> Bool {
        guard let viewport, let bit = shadertoyKeyBit(for: event) else {
            return false
        }

        let mask = Int32(1 << bit)
        if isDown {
            viewport.shadertoyKeyMask |= mask
        } else {
            viewport.shadertoyKeyMask &= ~mask
        }
        return true
    }

    private func shadertoyKeyBit(for event: NSEvent) -> Int? {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": return 0
        case "a": return 1
        case "s": return 2
        case "d": return 3
        case "q": return 4
        case "e": return 5
        case "r": return 6
        case "f": return 7
        default: return nil
        }
    }

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

    private func drawablePointInPixels(_ point: CGPoint) -> SIMD2<Float> {
        let width = max(Float(bounds.width), 1)
        let height = max(Float(bounds.height), 1)
        let x = max(0, min(Float(point.x) / width, 1))
        let yPoint = isFlipped ? height - Float(point.y) : Float(point.y)
        let y = max(0, min(yPoint / height, 1))
        return SIMD2(x * Float(drawableSize.width), y * Float(drawableSize.height))
    }
}
