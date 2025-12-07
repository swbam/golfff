import CoreMedia
import CoreGraphics
import Vision
import simd

// MARK: - Trajectory Point

struct TrajectoryPoint: Equatable {
    let time: CMTime
    let normalized: CGPoint  // Normalized 0-1, UIKit coordinates (top-left origin)
    
    static func == (lhs: TrajectoryPoint, rhs: TrajectoryPoint) -> Bool {
        lhs.normalized == rhs.normalized
    }
}

// MARK: - Trajectory

struct Trajectory {
    var id: UUID
    
    /// Points where ball was ACTUALLY detected by Vision
    var detectedPoints: [TrajectoryPoint]
    
    /// Points PREDICTED by Vision's parabola fit - THIS IS THE FULL ARC!
    /// Use this for rendering the smooth trajectory
    var projectedPoints: [TrajectoryPoint]
    
    /// Parabola equation coefficients: y = ax² + bx + c
    /// coefficients.x = a, coefficients.y = b, coefficients.z = c
    var equationCoefficients: simd_float3
    
    /// Detection confidence (0-1)
    var confidence: VNConfidence
    
    /// Time range of the trajectory
    var timeRange: CMTimeRange?
    
    /// Convenience: all points for backward compatibility
    var points: [TrajectoryPoint] {
        // Prefer projectedPoints (smoother, complete arc), fall back to detected
        projectedPoints.isEmpty ? detectedPoints : projectedPoints
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID,
        detectedPoints: [TrajectoryPoint] = [],
        projectedPoints: [TrajectoryPoint] = [],
        equationCoefficients: simd_float3 = simd_float3(0, 0, 0),
        confidence: VNConfidence = 0,
        timeRange: CMTimeRange? = nil
    ) {
        self.id = id
        self.detectedPoints = detectedPoints
        self.projectedPoints = projectedPoints
        self.equationCoefficients = equationCoefficients
        self.confidence = confidence
        self.timeRange = timeRange
    }
    
    /// Legacy initializer for backward compatibility
    init(id: UUID, points: [TrajectoryPoint], confidence: VNConfidence) {
        self.id = id
        self.detectedPoints = points
        self.projectedPoints = points
        self.equationCoefficients = simd_float3(0, 0, 0)
        self.confidence = confidence
        self.timeRange = nil
    }
    
    // MARK: - Parabola Utilities
    
    /// Calculate Y position at given X using parabola equation
    /// y = ax² + bx + c
    func calculateY(atX x: CGFloat) -> CGFloat {
        let a = CGFloat(equationCoefficients.x)
        let b = CGFloat(equationCoefficients.y)
        let c = CGFloat(equationCoefficients.z)
        return a * x * x + b * x + c
    }
    
    /// Generate smooth trajectory points from the parabola equation
    /// - Parameter density: Number of points to generate
    /// - Returns: Array of interpolated points along the parabola
    func generateSmoothTrajectory(density: Int = 60) -> [CGPoint] {
        guard !projectedPoints.isEmpty else { return [] }
        
        // Get X range from projected points
        let xValues = projectedPoints.map { $0.normalized.x }
        guard let minX = xValues.min(), let maxX = xValues.max() else { return [] }
        
        let step = (maxX - minX) / CGFloat(density - 1)
        var smoothPoints: [CGPoint] = []
        
        for i in 0..<density {
            let x = minX + step * CGFloat(i)
            let y = calculateY(atX: x)
            smoothPoints.append(CGPoint(x: x, y: y))
        }
        
        return smoothPoints
    }
    
    /// Check if trajectory represents valid golf ball flight
    var isValidGolfTrajectory: Bool {
        guard projectedPoints.count >= 5 else { return false }
        
        // Golf ball trajectory characteristics:
        // 1. Moves generally in one horizontal direction
        // 2. Goes UP then DOWN (parabola)
        // 3. Coefficient 'a' should be positive (opens upward in Vision coords = downward in screen)
        
        let a = equationCoefficients.x
        
        // For UIKit coordinates (Y increases downward), parabola should open upward (a > 0)
        // This means ball goes up then comes down
        guard a > 0 else { return false }
        
        // Check horizontal movement
        if let first = projectedPoints.first, let last = projectedPoints.last {
            let dx = abs(last.normalized.x - first.normalized.x)
            guard dx > 0.05 else { return false }  // Must move horizontally
        }
        
        return confidence > 0.3
    }
}

// MARK: - Trajectory Storage for Live + Export Matching

/// Stores trajectory data that can be used for BOTH live rendering AND video export
/// This ensures live tracer EXACTLY matches exported tracer
final class TrajectoryStore {
    /// In test/instant modes we may want to accept any trajectory without golf-shape validation
    var allowAnyTrajectory = false
    /// Expected ball launch position in UIKit-normalized coords (from alignment overlay)
    var expectedStartNormalized: CGPoint?
    
    /// All detected trajectories keyed by UUID
    private var trajectories: [UUID: Trajectory] = [:]
    
    /// The "best" trajectory for the current shot
    private(set) var primaryTrajectory: Trajectory?
    
    /// Frame count since last detection (for cleanup)
    private var missingFrameCounts: [UUID: Int] = [:]
    private let maxMissingFrames = 10
    
    // MARK: - Updates from Vision
    
    /// Update with new Vision observation
    func update(with observation: VNTrajectoryObservation) {
        let uuid = observation.uuid
        
        // Reset missing count
        missingFrameCounts[uuid] = 0
        
        // Convert detected points (Vision bottom-left → UIKit top-left)
        let detected = convert(observation.detectedPoints, timeRange: observation.timeRange)
        let projected = convert(observation.projectedPoints, timeRange: observation.timeRange)
        
        if var existing = trajectories[uuid] {
            // Merge with existing trajectory (dedupe + sort by time)
            existing.detectedPoints = merge(existing.detectedPoints, with: detected)
            // Always keep the latest projected curve from Vision
            existing.projectedPoints = merge(existing.projectedPoints, with: projected, replaceExisting: true)
            existing.equationCoefficients = observation.equationCoefficients
            existing.confidence = max(existing.confidence, observation.confidence)
            existing.timeRange = observation.timeRange
            trajectories[uuid] = existing
        } else {
            // New trajectory
            let trajectory = Trajectory(
                id: uuid,
                detectedPoints: detected,
                projectedPoints: projected,
                equationCoefficients: observation.equationCoefficients,
                confidence: observation.confidence,
                timeRange: observation.timeRange
            )
            trajectories[uuid] = trajectory
        }
        
        // Update primary trajectory (highest confidence)
        updatePrimaryTrajectory()
    }
    
    /// Called each frame - ages out stale trajectories
    func tick() {
        for uuid in trajectories.keys {
            missingFrameCounts[uuid] = (missingFrameCounts[uuid] ?? 0) + 1
            
            if (missingFrameCounts[uuid] ?? 0) > maxMissingFrames {
                trajectories.removeValue(forKey: uuid)
                missingFrameCounts.removeValue(forKey: uuid)
            }
        }
        updatePrimaryTrajectory()
    }
    
    private func updatePrimaryTrajectory() {
        // Select trajectory with highest confidence and most points
        primaryTrajectory = trajectories.values
            .filter { trajectory in
                if allowAnyTrajectory { return true }
                guard trajectory.isValidGolfTrajectory else { return false }
                // If we know the expected start, drop wildly off-target trajectories early
                if let expected = expectedStartNormalized,
                   let start = trajectory.detectedPoints.first?.normalized ?? trajectory.projectedPoints.first?.normalized {
                    return start.distance(to: expected) <= 0.45
                }
                return true
            }
            .max { a, b in
                score(for: a) < score(for: b)
            }
    }
    
    /// Get the trajectory for rendering (live or export)
    /// Returns the SAME data for both use cases!
    func getTrajectoryForRendering() -> Trajectory? {
        return primaryTrajectory
    }
    
    /// Clear all trajectories
    func reset() {
        trajectories.removeAll()
        missingFrameCounts.removeAll()
        primaryTrajectory = nil
    }
    
    /// Get all active trajectories
    var allTrajectories: [Trajectory] {
        Array(trajectories.values)
    }

    // MARK: - Helpers

    /// Convert Vision-normalized points to UIKit-normalized points and spread timestamps across the observation's timeRange.
    private func convert(_ points: [VNPoint], timeRange: CMTimeRange) -> [TrajectoryPoint] {
        guard !points.isEmpty else { return [] }

        let duration = timeRange.duration.seconds
        let step = (points.count > 1 && duration > 0) ? duration / Double(points.count - 1) : 0

        return points.enumerated().map { index, point in
            let time = CMTime(seconds: timeRange.start.seconds + (Double(index) * step), preferredTimescale: 600)
            let uiPoint = CGPoint(x: CGFloat(point.x), y: 1.0 - CGFloat(point.y))
            return TrajectoryPoint(time: time, normalized: uiPoint)
        }
    }

    /// Merge point arrays while keeping them time-sorted and de-duplicated.
    private func merge(_ existing: [TrajectoryPoint], with newPoints: [TrajectoryPoint], replaceExisting: Bool = false) -> [TrajectoryPoint] {
        var combined = replaceExisting ? [] : existing
        for point in newPoints {
            if !combined.contains(where: { abs($0.time.seconds - point.time.seconds) < 0.0005 && $0.normalized == point.normalized }) {
                combined.append(point)
            }
        }
        return combined.sorted { $0.time < $1.time }
    }

    private func score(for trajectory: Trajectory) -> Float {
        let base = trajectory.confidence
        let volume = Float(trajectory.detectedPoints.count) * 0.08 + Float(trajectory.projectedPoints.count) * 0.02

        var startBoost: Float = 0
        if let expected = expectedStartNormalized,
           let start = trajectory.detectedPoints.first?.normalized ?? trajectory.projectedPoints.first?.normalized {
            let distance = start.distance(to: expected)
            // Favor trajectories that start close to expected ball location
            startBoost = max(0, 1 - Float(distance * 2.2)) // distance 0 → 1, ~0.45 → 0
        }

        return base + volume + startBoost
    }
}
