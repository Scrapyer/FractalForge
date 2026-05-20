import MetalKit
import simd

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private weak var fpsMonitor: FPSMonitor?
    private let viewport: FractalViewport
    private var pipelineState: MTLRenderPipelineState?
    private var shadertoyBasePipelineState: MTLRenderPipelineState?
    private var shadertoyBloomMipPipelineState: MTLRenderPipelineState?
    private var shadertoyBloomBlurHPipelineState: MTLRenderPipelineState?
    private var shadertoyBloomBlurVPipelineState: MTLRenderPipelineState?
    private var shadertoyCompositePipelineState: MTLRenderPipelineState?
    private var multipassTextures: MultipassTextures?
    private var lastMultipassSignature: MultipassSignature?
    private var startTime = CFAbsoluteTimeGetCurrent()
    private var lastDrawTime = CFAbsoluteTimeGetCurrent()
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
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let size = view.drawableSize
        guard size.width >= 1, size.height >= 1 else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let elapsedTime = Float(now - startTime)
        let deltaTime = Float(max(0, min(now - lastDrawTime, 1.0 / 12.0)))
        lastDrawTime = now

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
            time: elapsedTime,
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
            rayMarchSteps: Int32(viewport.rayMarchSteps),
            quaternionConstantZW: SIMD2(Float(viewport.quaternionConstantZW.x), Float(viewport.quaternionConstantZW.y)),
            fourDSlice: Float(viewport.fourDSlice),
            timeDelta: deltaTime,
            frameIndex: Int32(frameCount),
            shadertoyMouse: SIMD4(
                Float(viewport.shadertoyMouse.x),
                Float(viewport.shadertoyMouse.y),
                Float(viewport.shadertoyMouse.z),
                Float(viewport.shadertoyMouse.w)
            ),
            shadertoyKeyMask: viewport.shadertoyKeyMask
        )
        uniforms.applyDoublePrecision(center: viewport.center, scale: viewport.scale)

        let usesShadertoyMultipass = viewport.kind == .kerrNewmanBlackHole || viewport.kind == .gargantuaBlackHole
        if usesShadertoyMultipass {
            guard renderShadertoyMultipass(drawableTexture: drawable.texture, commandBuffer: commandBuffer, uniforms: &uniforms) else {
                return
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            recordFrame()
            return
        }

        guard let pipelineState else { return }
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

        recordFrame()
    }

    private func recordFrame() {
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
              let fragmentFunction = library.makeFunction(name: "mandelbrotFragment"),
              let shadertoyBaseFunction = library.makeFunction(name: "shadertoyBlackHoleBaseFragment"),
              let shadertoyBloomMipFunction = library.makeFunction(name: "shadertoyBloomMipFragment"),
              let shadertoyBloomBlurHFunction = library.makeFunction(name: "shadertoyBloomBlurHFragment"),
              let shadertoyBloomBlurVFunction = library.makeFunction(name: "shadertoyBloomBlurVFragment"),
              let shadertoyCompositeFunction = library.makeFunction(name: "shadertoyBlackHoleCompositeFragment")
        else {
            NSLog("FractalForge: required Metal shader functions not found in Metal library.")
            return
        }

        pipelineState = makePipelineState(vertexFunction: vertexFunction, fragmentFunction: fragmentFunction, pixelFormat: pixelFormat)
        shadertoyBasePipelineState = makePipelineState(vertexFunction: vertexFunction, fragmentFunction: shadertoyBaseFunction, pixelFormat: .rgba16Float)
        shadertoyBloomMipPipelineState = makePipelineState(vertexFunction: vertexFunction, fragmentFunction: shadertoyBloomMipFunction, pixelFormat: .rgba16Float)
        shadertoyBloomBlurHPipelineState = makePipelineState(vertexFunction: vertexFunction, fragmentFunction: shadertoyBloomBlurHFunction, pixelFormat: .rgba16Float)
        shadertoyBloomBlurVPipelineState = makePipelineState(vertexFunction: vertexFunction, fragmentFunction: shadertoyBloomBlurVFunction, pixelFormat: .rgba16Float)
        shadertoyCompositePipelineState = makePipelineState(vertexFunction: vertexFunction, fragmentFunction: shadertoyCompositeFunction, pixelFormat: pixelFormat)
    }

    private func makePipelineState(
        vertexFunction: MTLFunction,
        fragmentFunction: MTLFunction,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("FractalForge: render pipeline failed for \(pixelFormat): \(error)")
            return nil
        }
    }

    private func renderShadertoyMultipass(
        drawableTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        uniforms: inout FrameUniforms
    ) -> Bool {
        guard let shadertoyBasePipelineState,
              let shadertoyBloomMipPipelineState,
              let shadertoyBloomBlurHPipelineState,
              let shadertoyBloomBlurVPipelineState,
              let shadertoyCompositePipelineState
        else {
            return false
        }

        guard let textures = ensureMultipassTextures(width: drawableTexture.width, height: drawableTexture.height) else {
            return false
        }

        let signature = MultipassSignature(uniforms: uniforms, width: drawableTexture.width, height: drawableTexture.height)
        if signature != lastMultipassSignature {
            textures.historyIsValid = false
            lastMultipassSignature = signature
        }

        if !textures.historyIsValid {
            uniforms.frameIndex = 0
            guard clearTexture(commandBuffer: commandBuffer, target: textures.history) else {
                return false
            }
            guard clearTexture(commandBuffer: commandBuffer, target: textures.bufferB) else {
                return false
            }
            guard clearTexture(commandBuffer: commandBuffer, target: textures.bufferBHistory) else {
                return false
            }
            textures.historyIsValid = true
        }

        guard encodeFullscreenPass(
            commandBuffer: commandBuffer,
            target: textures.base,
            pipelineState: shadertoyBasePipelineState,
            uniforms: &uniforms,
            sourceTextures: [textures.history, textures.bufferBHistory]
        ) else { return false }

        guard encodeFullscreenPass(
            commandBuffer: commandBuffer,
            target: textures.bufferB,
            pipelineState: shadertoyBloomMipPipelineState,
            uniforms: &uniforms,
            sourceTextures: [textures.base, textures.bufferBHistory]
        ) else { return false }

        guard encodeFullscreenPass(
            commandBuffer: commandBuffer,
            target: textures.bufferC,
            pipelineState: shadertoyBloomBlurHPipelineState,
            uniforms: &uniforms,
            sourceTextures: [textures.bufferB]
        ) else { return false }

        guard encodeFullscreenPass(
            commandBuffer: commandBuffer,
            target: textures.bufferD,
            pipelineState: shadertoyBloomBlurVPipelineState,
            uniforms: &uniforms,
            sourceTextures: [textures.bufferC]
        ) else { return false }

        guard encodeFullscreenPass(
            commandBuffer: commandBuffer,
            target: drawableTexture,
            pipelineState: shadertoyCompositePipelineState,
            uniforms: &uniforms,
            sourceTextures: [textures.base, textures.bufferD],
            clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        ) else { return false }

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return false
        }
        blitEncoder.copy(
            from: textures.base,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: textures.width, height: textures.height, depth: 1),
            to: textures.history,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.copy(
            from: textures.bufferB,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: textures.width, height: textures.height, depth: 1),
            to: textures.bufferBHistory,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()
        return true
    }

    private func clearTexture(commandBuffer: MTLCommandBuffer, target: MTLTexture) -> Bool {
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = target
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return false
        }
        renderEncoder.endEncoding()
        return true
    }

    private func encodeFullscreenPass(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        pipelineState: MTLRenderPipelineState,
        uniforms: inout FrameUniforms,
        sourceTextures: [MTLTexture] = [],
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    ) -> Bool {
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = target
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = clearColor
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return false
        }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        for (index, texture) in sourceTextures.enumerated() {
            renderEncoder.setFragmentTexture(texture, index: index)
        }
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renderEncoder.endEncoding()
        return true
    }

    private func ensureMultipassTextures(width: Int, height: Int) -> MultipassTextures? {
        if let multipassTextures,
           multipassTextures.width == width,
           multipassTextures.height == height {
            return multipassTextures
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: max(width, 1),
            height: max(height, 1),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        guard let base = device.makeTexture(descriptor: descriptor),
              let bufferB = device.makeTexture(descriptor: descriptor),
              let bufferBHistory = device.makeTexture(descriptor: descriptor),
              let bufferC = device.makeTexture(descriptor: descriptor),
              let bufferD = device.makeTexture(descriptor: descriptor),
              let history = device.makeTexture(descriptor: descriptor)
        else {
            return nil
        }

        let textures = MultipassTextures(width: width, height: height, base: base, bufferB: bufferB, bufferBHistory: bufferBHistory, bufferC: bufferC, bufferD: bufferD, history: history)
        multipassTextures = textures
        return textures
    }
}

private final class MultipassTextures {
    let width: Int
    let height: Int
    let base: MTLTexture
    let bufferB: MTLTexture
    let bufferBHistory: MTLTexture
    let bufferC: MTLTexture
    let bufferD: MTLTexture
    let history: MTLTexture
    var historyIsValid = false

    init(width: Int, height: Int, base: MTLTexture, bufferB: MTLTexture, bufferBHistory: MTLTexture, bufferC: MTLTexture, bufferD: MTLTexture, history: MTLTexture) {
        self.width = width
        self.height = height
        self.base = base
        self.bufferB = bufferB
        self.bufferBHistory = bufferBHistory
        self.bufferC = bufferC
        self.bufferD = bufferD
        self.history = history
    }
}

private struct MultipassSignature: Equatable {
    let width: Int
    let height: Int
    let fractalType: Int32
    let rotation: Int32
    let cameraPitch: Int32
    let cameraDistance: Int32
    let rayMarchSteps: Int32

    init(uniforms: FrameUniforms, width: Int, height: Int) {
        self.width = width
        self.height = height
        self.fractalType = uniforms.fractalType
        self.rotation = Int32((uniforms.rotation * 1000).rounded())
        self.cameraPitch = Int32((uniforms.cameraPitch * 1000).rounded())
        self.cameraDistance = Int32((uniforms.cameraDistance * 100).rounded())
        self.rayMarchSteps = uniforms.rayMarchSteps
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
    var quaternionConstantZW: SIMD2<Float>
    var fourDSlice: Float
    var timeDelta: Float
    var frameIndex: Int32
    var shadertoyMouse: SIMD4<Float>
    var shadertoyKeyMask: Int32

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
