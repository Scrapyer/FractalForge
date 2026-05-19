import Foundation
import Observation

@Observable
@MainActor
final class FPSMonitor {
    var fps: Double = 0

    func record(measuredFPS: Double) {
        guard measuredFPS.isFinite, measuredFPS > 0 else { return }
        fps = fps == 0 ? measuredFPS : fps * 0.8 + measuredFPS * 0.2
    }
}
