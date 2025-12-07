import CoreMedia
import CoreGraphics
import Vision

struct TrajectoryPoint {
    let time: CMTime
    let normalized: CGPoint
}

struct Trajectory {
    var id: UUID
    var points: [TrajectoryPoint]
    var confidence: VNConfidence
}
