import MetalKit
import simd

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private weak var fpsMonitor: FPSMonitor?
    private let viewport: FractalViewport
    private var pipelineState: MTLRenderPipelineState?
    private var startTime = CFAbsoluteTimeGetCurrent()
    private var frameCount = 0
    private var framesSinceFPSUpdate = 0
    private var lastFPSUpdateTime = CFAbsoluteTimeGetCurrent()

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, fpsMonitor: FPSMonitor, viewport: FractalViewport) {
        self.fpsMonitor = fpsMonitor
        self.viewport = viewport
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue.")
        }
        self.commandQueue = queue
        super.init()
        buildPipeline(pixelFormat: pixelFormat)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay(view.bounds)
    }

    func draw(in view: MTKView) {
        guard let window = view.window,
              !window.isMiniaturized,
              window.occlusionState.contains(.visible),
              let pipelineState,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let size = view.drawableSize
        guard size.width >= 1, size.height >= 1 else { return }

        var uniforms = FrameUniforms(
            resolution: SIMD2(Float(size.width), Float(size.height)),
            centerHi: SIMD2(Float(viewport.center.x), Float(viewport.center.y)),
            centerLo: .zero,
            juliaConstant: SIMD2(Float(viewport.juliaConstant.x), Float(viewport.juliaConstant.y)),
            backgroundColor: SIMD4(
                Float(viewport.renderBackgroundColor.x),
                Float(viewport.renderBackgroundColor.y),
                Float(viewport.renderBackgroundColor.z),
                1
            ),
            scaleHi: Float(viewport.scale),
            scaleLo: 0,
            time: Float(CFAbsoluteTimeGetCurrent() - startTime),
            bailoutRadius: Float(viewport.bailoutRadius),
            rotation: Float(viewport.rotationDegrees * .pi / 180),
            multibrotPower: Float(viewport.multibrotPower),
            mandelbulbPower: Float(viewport.mandelbulbPower),
            cameraPitch: Float(viewport.cameraPitch * .pi / 180),
            cameraDistance: Float(viewport.cameraDistance),
            surfaceDetail: Float(viewport.surfaceDetail),
            contrast: Float(viewport.contrast),
            exposure: Float(viewport.exposure),
            maxIter: viewport.iterationCount,
            fractalType: viewport.kind.rawValue,
            precisionMode: viewport.precisionMode.rawValue,
            colorPalette: viewport.colorPalette.rawValue,
            antialiasingMode: viewport.antialiasingMode.rawValue,
            smoothColoring: viewport.smoothColoring ? 1 : 0,
            rayMarchSteps: Int32(viewport.rayMarchSteps)
        )
        uniforms.applyDoublePrecision(center: viewport.center, scale: viewport.scale)

        let passDescriptor = MTLRenderPassDescriptor()
        let backgroundColor = viewport.renderBackgroundColor
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: backgroundColor.x,
            green: backgroundColor.y,
            blue: backgroundColor.z,
            alpha: 1
        )
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        frameCount += 1
        framesSinceFPSUpdate += 1

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastFPSUpdateTime
        if elapsed >= 0.25, let fpsMonitor {
            let measuredFPS = Double(framesSinceFPSUpdate) / elapsed
            framesSinceFPSUpdate = 0
            lastFPSUpdateTime = now
            DispatchQueue.main.async { [weak fpsMonitor] in
                MainActor.assumeIsolated {
                    fpsMonitor?.record(measuredFPS: measuredFPS)
                }
            }
        }
    }

    private func buildPipeline(pixelFormat: MTLPixelFormat) {
        guard let library = device.makeDefaultLibrary() else {
            NSLog("FractalForge: default Metal library missing. Is Shaders.metal in the target?")
            return
        }

        guard let vertexFunction = library.makeFunction(name: "mandelbrotVertex"),
              let fragmentFunction = library.makeFunction(name: "mandelbrotFragment")
        else {
            NSLog("FractalForge: mandelbrotVertex/mandelbrotFragment not found in Metal library.")
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("FractalForge: render pipeline failed: \(error)")
        }
    }
}

private struct FrameUniforms {
    var resolution: SIMD2<Float>
    var centerHi: SIMD2<Float>
    var centerLo: SIMD2<Float>
    var juliaConstant: SIMD2<Float>
    var backgroundColor: SIMD4<Float>
    var scaleHi: Float
    var scaleLo: Float
    var time: Float
    var bailoutRadius: Float
    var rotation: Float
    var multibrotPower: Float
    var mandelbulbPower: Float
    var cameraPitch: Float
    var cameraDistance: Float
    var surfaceDetail: Float
    var contrast: Float
    var exposure: Float
    var maxIter: Int32
    var fractalType: Int32
    var precisionMode: Int32
    var colorPalette: Int32
    var antialiasingMode: Int32
    var smoothColoring: Int32
    var rayMarchSteps: Int32

    mutating func applyDoublePrecision(center: SIMD2<Double>, scale: Double) {
        let cx = Self.split(center.x)
        let cy = Self.split(center.y)
        let sc = Self.split(scale)
        centerHi = SIMD2(cx.hi, cy.hi)
        centerLo = SIMD2(cx.lo, cy.lo)
        scaleHi = sc.hi
        scaleLo = sc.lo
    }

    private static func split(_ value: Double) -> (hi: Float, lo: Float) {
        let hi = Float(value)
        let lo = Float(value - Double(hi))
        return (hi, lo)
    }
}
