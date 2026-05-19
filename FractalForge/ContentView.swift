import AppKit
import SwiftUI

struct ContentView: View {
    @SceneStorage("ContentView.showsAlgorithmSidebar") private var showsAlgorithmSidebar = true
    @SceneStorage("ContentView.showsParameterInspector") private var showsParameterInspector = true
    @State private var fpsMonitor = FPSMonitor()
    @State private var viewport = FractalViewport()
    @State private var showsPerformance = true

    var body: some View {
        @Bindable var viewport = viewport

        VStack(spacing: 0) {
            FractalToolbar(
                viewport: viewport,
                showsPerformance: $showsPerformance
            )

            Divider()

            HStack(spacing: 0) {
                if showsAlgorithmSidebar {
                    AlgorithmSidebar(viewport: viewport)
                        .frame(width: 220)

                    Divider()
                }

                FractalCanvas(fpsMonitor: fpsMonitor, viewport: viewport)
                    .frame(minWidth: 520, minHeight: 360)

                if showsParameterInspector {
                    Divider()

                    ParameterInspector(viewport: viewport)
                        .frame(width: 300)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showsAlgorithmSidebar)
            .animation(.easeInOut(duration: 0.18), value: showsParameterInspector)

            Divider()

            StatusBar(
                fpsMonitor: fpsMonitor,
                viewport: viewport,
                showsPerformance: showsPerformance
            )
        }
        .frame(minWidth: minimumWindowWidth, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showsAlgorithmSidebar.toggle()
                } label: {
                    Label("切换算法库", systemImage: "sidebar.leading")
                }
                .labelStyle(.iconOnly)
                .help(showsAlgorithmSidebar ? "隐藏算法库" : "显示算法库")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsParameterInspector.toggle()
                } label: {
                    Label("切换参数面板", systemImage: "sidebar.trailing")
                }
                .labelStyle(.iconOnly)
                .help(showsParameterInspector ? "隐藏参数面板" : "显示参数面板")
            }
        }
    }

    private var minimumWindowWidth: CGFloat {
        var width: CGFloat = 520

        if showsAlgorithmSidebar {
            width += 220
        }

        if showsParameterInspector {
            width += 300
        }

        return max(width, 720)
    }
}

private struct FractalToolbar: View {
    @Bindable var viewport: FractalViewport
    @Binding var showsPerformance: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                viewport.reset()
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
            }
            .help("重置视图")

            Button {
            } label: {
                Label("保存预设", systemImage: "bookmark")
            }
            .disabled(true)

            Button {
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(true)

            Spacer()

            Toggle(isOn: $showsPerformance) {
                Label("性能", systemImage: "gauge.with.dots.needle.67percent")
            }
            .toggleStyle(.button)
            .help("显示性能状态")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct AlgorithmSidebar: View {
    @Bindable var viewport: FractalViewport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("算法库")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    AlgorithmSection(
                        title: "2D",
                        kinds: FractalKind.twoDimensionalCases,
                        viewport: viewport,
                        selectionBackground: selectionBackground
                    )

                    AlgorithmSection(
                        title: "3D",
                        kinds: FractalKind.threeDimensionalCases,
                        viewport: viewport,
                        selectionBackground: selectionBackground
                    )
                }
            }

            Spacer()
        }
        .background(.bar)
    }

    private func selectionBackground(for kind: FractalKind) -> Color {
        viewport.kind == kind ? Color.accentColor.opacity(0.22) : Color.clear
    }
}

private struct AlgorithmSection: View {
    let title: String
    let kinds: [FractalKind]
    @Bindable var viewport: FractalViewport
    let selectionBackground: (FractalKind) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 2)

            ForEach(kinds) { kind in
                Button {
                    viewport.kind = kind
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kind.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text(kind.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(selectionBackground(kind), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
    }
}

private struct FractalCanvas: View {
    var fpsMonitor: FPSMonitor
    var viewport: FractalViewport

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MetalView(fpsMonitor: fpsMonitor, viewport: viewport)

            Text(viewport.kind.title)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                .padding(12)
        }
        .background(.black)
    }
}

private struct ParameterInspector: View {
    @Bindable var viewport: FractalViewport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("参数面板")
                    .font(.headline)

                InspectorSection("视口") {
                    NumberField("中心 X", value: centerX, digits: 8)
                    NumberField("中心 Y", value: centerY, digits: 8)
                    NumberField("缩放", value: $viewport.scale, digits: 8)
                    SliderRow(viewport.is3D ? "水平旋转" : "旋转", value: $viewport.rotationDegrees, range: -180...180, suffix: "°")
                    SliderRow("缩放速度", value: $viewport.zoomSpeed, range: 0.02...0.18)
                }

                if viewport.is3D {
                    InspectorSection("3D 相机") {
                        SliderRow("俯仰角", value: $viewport.cameraPitch, range: -55...55, suffix: "°")
                        SliderRow("相机距离", value: $viewport.cameraDistance, range: 1.4...8.0)
                    }
                }

                InspectorSection("迭代") {
                    SliderRow("最大迭代", value: $viewport.maxIterationsLimit, range: 64...4096, step: 64)
                    SliderRow("逃逸半径", value: $viewport.bailoutRadius, range: 2...512, step: 2)
                    if viewport.is3D {
                        SliderRow("射线步数", value: $viewport.rayMarchSteps, range: 32...192, step: 8)
                        SliderRow("表面精度", value: $viewport.surfaceDetail, range: 0.0004...0.006, step: 0.0002)
                    }
                    Picker("精度模式", selection: $viewport.precisionMode) {
                        ForEach(PrecisionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                InspectorSection("公式参数") {
                    if viewport.kind == .julia {
                        NumberField("Julia c 实部", value: juliaX, digits: 5)
                        NumberField("Julia c 虚部", value: juliaY, digits: 5)
                    }

                    if viewport.kind == .multibrot {
                        SliderRow("Multibrot 幂次", value: $viewport.multibrotPower, range: 2...8, step: 0.1)
                    }

                    if viewport.kind == .mandelbulb3D {
                        SliderRow("Mandelbulb 幂次", value: $viewport.mandelbulbPower, range: 2...12, step: 0.1)
                    }

                    if viewport.kind == .newton {
                        LabeledContent("Newton 根模式", value: "z³ - 1")
                    }

                    if viewport.kind != .julia && viewport.kind != .multibrot && viewport.kind != .newton && viewport.kind != .mandelbulb3D {
                        LabeledContent("当前公式", value: viewport.kind.title)
                    }

                    if let sourceURL = viewport.kind.sourceURL {
                        LabeledContent("来源 URL", value: sourceURL)
                    } else if viewport.kind.rawValue >= FractalKind.oceanic.rawValue {
                        LabeledContent("来源页", value: "Shadertoy Fractal 第 2 页")
                    }
                }

                InspectorSection("颜色") {
                    Picker("调色板", selection: $viewport.colorPalette) {
                        ForEach(ColorPalette.allCases) { palette in
                            Text(palette.title).tag(palette)
                        }
                    }
                    SliderRow("对比度", value: $viewport.contrast, range: 0.4...2.4)
                    SliderRow("曝光", value: $viewport.exposure, range: 0.3...2.0)
                    Toggle("平滑着色", isOn: $viewport.smoothColoring)
                }

                InspectorSection("背景") {
                    Picker("背景预设", selection: $viewport.backgroundPreset) {
                        ForEach(RenderBackgroundPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    ColorPicker("自定义颜色", selection: backgroundColor, supportsOpacity: false)
                }

                InspectorSection("渲染") {
                    SliderRow("分辨率比例", value: $viewport.resolutionScale, range: 0.35...1.25)
                    Picker("抗锯齿", selection: $viewport.antialiasingMode) {
                        ForEach(AntialiasingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    SliderRow("FPS 上限", value: $viewport.fpsCap, range: 15...120, step: 15)
                    Toggle("实时预览", isOn: $viewport.livePreview)
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var centerX: Binding<Double> {
        Binding {
            viewport.center.x
        } set: {
            viewport.center.x = $0
        }
    }

    private var centerY: Binding<Double> {
        Binding {
            viewport.center.y
        } set: {
            viewport.center.y = $0
        }
    }

    private var juliaX: Binding<Double> {
        Binding {
            viewport.juliaConstant.x
        } set: {
            viewport.juliaConstant.x = $0
        }
    }

    private var juliaY: Binding<Double> {
        Binding {
            viewport.juliaConstant.y
        } set: {
            viewport.juliaConstant.y = $0
        }
    }

    private var backgroundColor: Binding<Color> {
        Binding {
            let color = viewport.customBackgroundColor
            return Color(red: color.x, green: color.y, blue: color.z)
        } set: { newValue in
            guard let color = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            viewport.backgroundPreset = .custom
            viewport.customBackgroundColor = SIMD3(
                Double(color.redComponent),
                Double(color.greenComponent),
                Double(color.blueComponent)
            )
        }
    }
}

private struct InspectorSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

private struct NumberField: View {
    let title: String
    @Binding var value: Double
    var digits: Int

    init(_ title: String, value: Binding<Double>, digits: Int) {
        self.title = title
        self._value = value
        self.digits = digits
    }

    var body: some View {
        LabeledContent(title) {
            TextField(
                title,
                value: $value,
                format: .number.precision(.fractionLength(0...digits))
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 112)
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var suffix: String = ""

    init(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 0.01,
        suffix: String = ""
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.suffix = suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(formattedValue)\(suffix)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range, step: step)
        }
    }

    private var formattedValue: String {
        if step >= 1 {
            return String(format: "%.0f", value)
        }
        if step >= 0.1 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }
}

private struct StatusBar: View {
    var fpsMonitor: FPSMonitor
    var viewport: FractalViewport
    var showsPerformance: Bool

    var body: some View {
        HStack(spacing: 14) {
            MetricLabel("FPS", value: String(format: "%.0f", fpsMonitor.fps))
            MetricLabel("迭代", value: "\(viewport.iterationCount)")
            MetricLabel("精度", value: viewport.precisionMode.title)
            MetricLabel("缩放", value: String(format: "%.2e", viewport.scale))

            if showsPerformance {
                MetricLabel("GPU 内存", value: "Drawable x2")
                MetricLabel("渲染耗时", value: renderTime)
            }

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var renderTime: String {
        guard fpsMonitor.fps > 0 else { return "-- ms" }
        return String(format: "%.1f ms", 1000 / fpsMonitor.fps)
    }
}

private struct MetricLabel: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
        }
    }
}

#Preview {
    ContentView()
}
