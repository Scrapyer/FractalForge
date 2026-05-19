import Foundation
import Observation
import simd

enum FractalKind: Int32, CaseIterable, Identifiable {
    case mandelbrot = 0
    case julia = 1
    case burningShip = 2
    case newton = 3
    case multibrot = 4
    case mandelbox = 5
    case mandelbulb3D = 6
    case monster = 7
    case remnantX = 8
    case oceanic = 9
    case simplicityGalaxy = 10
    case galaxyOfUniverses = 11
    case fractalExplorerDOF = 12
    case basicMonteCarlo = 13
    case mysteryMountains = 14
    case valueNoise2D = 15
    case fluxCore = 16
    case apollonian = 17
    case mandelbulbIQ = 18
    case syntopiaIFS = 19
    case fractalExplorer = 20
    case lightAndMotion = 21
    case mandelboxSweeper = 22
    case shaderF3BGzW = 23
    case cosmicPearl = 24

    var id: Self { self }

    static let twoDimensionalCases: [FractalKind] = [
        .mandelbrot,
        .julia,
        .burningShip,
        .newton,
        .multibrot,
        .mandelbox,
        .oceanic,
        .simplicityGalaxy,
        .galaxyOfUniverses,
        .fractalExplorerDOF,
        .basicMonteCarlo,
        .mysteryMountains,
        .valueNoise2D,
        .fluxCore,
        .apollonian,
        .lightAndMotion,
        .shaderF3BGzW
    ]

    static let threeDimensionalCases: [FractalKind] = [
        .mandelbulb3D,
        .monster,
        .remnantX,
        .mandelbulbIQ,
        .syntopiaIFS,
        .fractalExplorer,
        .mandelboxSweeper,
        .cosmicPearl
    ]

    var title: String {
        switch self {
        case .mandelbrot: "Mandelbrot"
        case .julia: "Julia"
        case .burningShip: "Burning Ship"
        case .newton: "Newton"
        case .multibrot: "Multibrot"
        case .mandelbox: "Mandelbox"
        case .mandelbulb3D: "Mandelbulb 3D"
        case .monster: "Monster"
        case .remnantX: "Remnant X"
        case .oceanic: "Oceanic"
        case .simplicityGalaxy: "Simplicity Galaxy"
        case .galaxyOfUniverses: "Galaxy of Universes"
        case .fractalExplorerDOF: "Fractal Explorer DOF"
        case .basicMonteCarlo: "Basic Montecarlo"
        case .mysteryMountains: "Mystery Mountains"
        case .valueNoise2D: "Noise - value - 2D"
        case .fluxCore: "Flux Core"
        case .apollonian: "Apollonian"
        case .mandelbulbIQ: "Mandelbulb IQ"
        case .syntopiaIFS: "Syntopia IFS"
        case .fractalExplorer: "Fractal Explorer"
        case .lightAndMotion: "Light & Motion"
        case .mandelboxSweeper: "Mandelbox Sweeper"
        case .shaderF3BGzW: "Shader f3BGzW"
        case .cosmicPearl: "Cosmic Pearl"
        }
    }

    var detail: String {
        switch self {
        case .mandelbrot: "经典复平面探索"
        case .julia: "由复数常量驱动"
        case .burningShip: "绝对值折叠变体"
        case .newton: "根吸引域可视化"
        case .multibrot: "幂次推广 Mandelbrot"
        case .mandelbox: "折叠盒式轨道"
        case .mandelbulb3D: "三维距离场分形"
        case .monster: "Shadertoy 3D 折叠怪兽"
        case .remnantX: "Mandelbox 残骸隧道"
        case .oceanic: "分形噪声海面"
        case .simplicityGalaxy: "螺旋星云分形"
        case .galaxyOfUniverses: "多尺度星系场"
        case .fractalExplorerDOF: "景深折叠空间"
        case .basicMonteCarlo: "随机采样纹理"
        case .mysteryMountains: "分形山脉地形"
        case .valueNoise2D: "二维值噪声"
        case .fluxCore: "极坐标能量核心"
        case .apollonian: "圆反演填隙"
        case .mandelbulbIQ: "IQ 多项式 Mandelbulb"
        case .syntopiaIFS: "KIFS 折叠距离场"
        case .fractalExplorer: "Dave Hoskins 3D 探索"
        case .lightAndMotion: "光线运动纹理"
        case .mandelboxSweeper: "Mandelbox 扫掠结构"
        case .shaderF3BGzW: "URL 分形纹理"
        case .cosmicPearl: "宇宙珍珠距离场"
        }
    }

    var sourceURL: String? {
        switch self {
        case .monster: "https://www.shadertoy.com/view/4sX3R2"
        case .remnantX: "https://www.shadertoy.com/view/4sjSW1"
        case .galaxyOfUniverses: "https://www.shadertoy.com/view/MdXSzS"
        case .apollonian: "https://www.shadertoy.com/view/4ds3zn"
        case .mandelbulbIQ: "https://www.shadertoy.com/view/ltfSWn"
        case .syntopiaIFS: "https://www.shadertoy.com/view/Mdf3z7"
        case .fractalExplorer: "https://www.shadertoy.com/view/4s3GW2"
        case .lightAndMotion: "https://www.shadertoy.com/view/4stBzr"
        case .mandelboxSweeper: "https://www.shadertoy.com/view/3lyXDm"
        case .shaderF3BGzW: "https://www.shadertoy.com/view/f3BGzW"
        case .cosmicPearl: "https://www.shadertoy.com/view/NcS3Wz"
        default: nil
        }
    }

    var systemImage: String {
        switch self {
        case .mandelbrot: "circle.grid.3x3"
        case .julia: "sparkles"
        case .burningShip: "flame"
        case .newton: "function"
        case .multibrot: "number"
        case .mandelbox: "cube"
        case .mandelbulb3D: "cube.transparent"
        case .monster: "ladybug"
        case .remnantX: "tornado"
        case .oceanic: "water.waves"
        case .simplicityGalaxy: "sparkle.magnifyingglass"
        case .galaxyOfUniverses: "sparkles"
        case .fractalExplorerDOF: "viewfinder"
        case .basicMonteCarlo: "die.face.5"
        case .mysteryMountains: "mountain.2"
        case .valueNoise2D: "checkerboard.rectangle"
        case .fluxCore: "bolt.circle"
        case .apollonian: "circle.hexagongrid"
        case .mandelbulbIQ: "cube.transparent"
        case .syntopiaIFS: "pyramid"
        case .fractalExplorer: "viewfinder.circle"
        case .lightAndMotion: "lightbulb"
        case .mandelboxSweeper: "rectangle.3.group"
        case .shaderF3BGzW: "waveform.path.ecg.rectangle"
        case .cosmicPearl: "circle.dotted"
        }
    }

    var definition: FractalDefinition {
        switch self {
        case .mandelbrot:
            FractalDefinition(
                kind: self,
                defaultCenter: SIMD2(-0.55, 0),
                defaultScale: 1.45,
                maxScale: 16,
                juliaConstant: SIMD2(-0.8, 0.156)
            )
        case .julia:
            FractalDefinition(
                kind: self,
                defaultCenter: SIMD2(0, 0),
                defaultScale: 1.55,
                maxScale: 8,
                juliaConstant: SIMD2(-0.8, 0.156)
            )
        case .burningShip:
            FractalDefinition(
                kind: self,
                defaultCenter: SIMD2(-0.45, -0.45),
                defaultScale: 1.7,
                maxScale: 16,
                juliaConstant: SIMD2(-0.8, 0.156)
            )
        case .newton:
            FractalDefinition(
                kind: self,
                defaultCenter: SIMD2(0, 0),
                defaultScale: 1.6,
                maxScale: 8,
                juliaConstant: SIMD2(-0.8, 0.156)
            )
        case .multibrot:
            FractalDefinition(
                kind: self,
                defaultCenter: SIMD2(0, 0),
                defaultScale: 1.55,
                maxScale: 16,
                juliaConstant: SIMD2(-0.8, 0.156)
            )
        case .mandelbox:
            FractalDefinition(
                kind: self,
                defaultCenter: SIMD2(0, 0),
                defaultScale: 1.25,
                maxScale: 10,
                juliaConstant: SIMD2(-0.8, 0.156)
            )
        case .mandelbulb3D:
            FractalDefinition(
                kind: self,
                defaultCenter: SIMD2(0, 0),
                defaultScale: 0.92,
                maxScale: 8,
                juliaConstant: SIMD2(-0.8, 0.156)
            )
        case .monster:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 0.95, maxScale: 10, juliaConstant: SIMD2(-0.8, 0.156))
        case .remnantX:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.05, maxScale: 12, juliaConstant: SIMD2(-0.8, 0.156))
        case .oceanic:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.8, maxScale: 20, juliaConstant: SIMD2(-0.8, 0.156))
        case .simplicityGalaxy:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.55, maxScale: 18, juliaConstant: SIMD2(-0.8, 0.156))
        case .galaxyOfUniverses:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 2.1, maxScale: 24, juliaConstant: SIMD2(-0.8, 0.156))
        case .fractalExplorerDOF:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.25, maxScale: 16, juliaConstant: SIMD2(-0.8, 0.156))
        case .basicMonteCarlo:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.45, maxScale: 16, juliaConstant: SIMD2(-0.8, 0.156))
        case .mysteryMountains:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0.12), defaultScale: 1.85, maxScale: 24, juliaConstant: SIMD2(-0.8, 0.156))
        case .valueNoise2D:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 2.0, maxScale: 24, juliaConstant: SIMD2(-0.8, 0.156))
        case .fluxCore:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.35, maxScale: 18, juliaConstant: SIMD2(-0.8, 0.156))
        case .apollonian:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.1, maxScale: 20, juliaConstant: SIMD2(-0.8, 0.156))
        case .mandelbulbIQ:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 0.86, maxScale: 8, juliaConstant: SIMD2(-0.8, 0.156))
        case .syntopiaIFS:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.05, maxScale: 12, juliaConstant: SIMD2(-0.8, 0.156))
        case .fractalExplorer:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.1, maxScale: 12, juliaConstant: SIMD2(-0.8, 0.156))
        case .lightAndMotion:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.8, maxScale: 20, juliaConstant: SIMD2(-0.8, 0.156))
        case .mandelboxSweeper:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.05, maxScale: 12, juliaConstant: SIMD2(-0.8, 0.156))
        case .shaderF3BGzW:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.65, maxScale: 20, juliaConstant: SIMD2(-0.8, 0.156))
        case .cosmicPearl:
            FractalDefinition(kind: self, defaultCenter: SIMD2(0, 0), defaultScale: 1.0, maxScale: 12, juliaConstant: SIMD2(-0.8, 0.156))
        }
    }
}

enum PrecisionMode: Int32, CaseIterable, Identifiable {
    case automatic = 0
    case float = 1
    case highPrecision = 2

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .float: "Float"
        case .highPrecision: "高精度"
        }
    }
}

enum ColorPalette: Int32, CaseIterable, Identifiable {
    case iqSmooth = 0
    case ember = 1
    case aurora = 2
    case electric = 3
    case monochrome = 4

    var id: Self { self }

    var title: String {
        switch self {
        case .iqSmooth: "IQ Smooth"
        case .ember: "Ember"
        case .aurora: "Aurora"
        case .electric: "Electric"
        case .monochrome: "Mono"
        }
    }
}

enum AntialiasingMode: Int32, CaseIterable, Identifiable {
    case automatic = 0
    case off = 1
    case samples2x = 2
    case samples4x = 4

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .off: "关闭"
        case .samples2x: "2x"
        case .samples4x: "4x"
        }
    }
}

enum RenderBackgroundPreset: Int32, CaseIterable, Identifiable {
    case midnight = 0
    case black = 1
    case slate = 2
    case warm = 3
    case custom = 4

    var id: Self { self }

    var title: String {
        switch self {
        case .midnight: "Midnight"
        case .black: "Black"
        case .slate: "Slate"
        case .warm: "Warm"
        case .custom: "自定义"
        }
    }

    var color: SIMD3<Double> {
        switch self {
        case .midnight: SIMD3(0.018, 0.024, 0.04)
        case .black: SIMD3(0.0, 0.0, 0.0)
        case .slate: SIMD3(0.055, 0.068, 0.085)
        case .warm: SIMD3(0.13, 0.095, 0.065)
        case .custom: SIMD3(0.018, 0.024, 0.04)
        }
    }
}

struct FractalDefinition {
    let kind: FractalKind
    let defaultCenter: SIMD2<Double>
    let defaultScale: Double
    let maxScale: Double
    let juliaConstant: SIMD2<Double>
}

@Observable
final class FractalViewport {
    var kind: FractalKind = .mandelbrot {
        didSet {
            if kind != oldValue {
                reset()
            }
        }
    }

    var center: SIMD2<Double> = FractalKind.mandelbrot.definition.defaultCenter
    var scale: Double = FractalKind.mandelbrot.definition.defaultScale
    var rotationDegrees: Double = 0
    var zoomSpeed: Double = 0.08
    var maxIterationsLimit: Double = 4096
    var bailoutRadius: Double = 256
    var precisionMode: PrecisionMode = .automatic
    var juliaConstant: SIMD2<Double> = FractalKind.mandelbrot.definition.juliaConstant
    var multibrotPower: Double = 3
    var mandelbulbPower: Double = 8
    var cameraPitch: Double = 22
    var cameraDistance: Double = 3.4
    var rayMarchSteps: Double = 96
    var surfaceDetail: Double = 0.0012
    var colorPalette: ColorPalette = .iqSmooth
    var contrast: Double = 1
    var exposure: Double = 1
    var smoothColoring: Bool = true
    var backgroundPreset: RenderBackgroundPreset = .midnight
    var customBackgroundColor: SIMD3<Double> = RenderBackgroundPreset.midnight.color
    var resolutionScale: Double = 1
    var antialiasingMode: AntialiasingMode = .automatic
    var fpsCap: Double = 60
    var livePreview: Bool = true

    private let minScale: Double = 1e-14

    var definition: FractalDefinition {
        kind.definition
    }

    var is3D: Bool {
        FractalKind.threeDimensionalCases.contains(kind)
    }

    var renderBackgroundColor: SIMD3<Double> {
        backgroundPreset == .custom ? customBackgroundColor : backgroundPreset.color
    }

    /// More iterations when zoomed in (smaller scale).
    var iterationCount: Int32 {
        let ratio = definition.defaultScale / max(scale, 1e-20)
        let estimated = 260 + 96 * log2(ratio)
        return Int32(min(max(estimated, 64), maxIterationsLimit))
    }

    func reset() {
        center = definition.defaultCenter
        scale = definition.defaultScale
        rotationDegrees = 0
        juliaConstant = definition.juliaConstant
        if is3D {
            cameraPitch = 22
            cameraDistance = 3.4
            mandelbulbPower = 8
            rayMarchSteps = 96
            surfaceDetail = 0.0012
        }
    }

    func pan(screenDelta: SIMD2<Float>, viewSize: SIMD2<Float>) {
        guard viewSize.x > 0, viewSize.y > 0 else { return }

        let aspect = Double(viewSize.x / viewSize.y)
        let uvDelta = rotate(SIMD2(
            Double(screenDelta.x / viewSize.x) * 2 * aspect,
            Double(screenDelta.y / viewSize.y) * 2
        ))
        center -= uvDelta * scale
    }

    func zoom(by factor: Float, anchorScreen: SIMD2<Float>, viewSize: SIMD2<Float>) {
        guard viewSize.x > 0, viewSize.y > 0 else { return }

        let aspect = Double(viewSize.x / viewSize.y)
        let uv = screenToComplexUV(anchorScreen, viewSize: viewSize, aspect: aspect)
        let anchorBefore = center + uv * scale

        let newScale = min(max(scale * Double(factor), minScale), definition.maxScale)
        let anchorAfter = center + uv * newScale
        center += anchorBefore - anchorAfter
        scale = newScale
    }

    private func screenToComplexUV(_ screen: SIMD2<Float>, viewSize: SIMD2<Float>, aspect: Double) -> SIMD2<Double> {
        let u = Double(screen.x / viewSize.x) * 2 - 1
        let v = Double(screen.y / viewSize.y) * 2 - 1
        return rotate(SIMD2(u * aspect, v))
    }

    private func rotate(_ point: SIMD2<Double>) -> SIMD2<Double> {
        let radians = rotationDegrees * .pi / 180
        let c = cos(radians)
        let s = sin(radians)
        return SIMD2(point.x * c - point.y * s, point.x * s + point.y * c)
    }
}
