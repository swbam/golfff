import AVFoundation
import Vision

protocol TrajectoryDetectorDelegate: AnyObject {
    func trajectoryDetector(_ detector: TrajectoryDetector, didUpdate trajectory: Trajectory)
    func trajectoryDetectorDidFinish(_ detector: TrajectoryDetector, finalTrajectory: Trajectory?)
}

/// Golf Ball Trajectory Detector using Apple's Vision Framework
/// 
/// KEY INSIGHT: Vision's VNDetectTrajectoriesRequest provides:
/// - detectedPoints: Where ball was actually observed
/// - projectedPoints: FULL predicted arc based on parabola fit ← USE THIS FOR RENDERING!
/// - equationCoefficients: The parabola equation (ax² + bx + c)
///
/// This is how SmoothSwing achieves live = export: both use the same projectedPoints!
final class TrajectoryDetector {
    weak var delegate: TrajectoryDetectorDelegate?

    /// Region of interest for detection (Vision coordinates: origin bottom-left)
    var regionOfInterest: CGRect?
    
    /// Expected launch point in UIKit-normalized coords (from alignment)
    var expectedBallStartNormalized: CGPoint? {
        didSet { trajectoryStore.expectedStartNormalized = expectedBallStartNormalized }
    }
    
    /// Video orientation
    var orientation: CGImagePropertyOrientation = .right
    
    /// Frame analysis spacing (0 = every frame)
    var frameAnalysisSpacing: CMTime = .zero
    
    /// Debug logging
    var debugLogging = true

    private var isRunning = false
    private let trajectoryStore = TrajectoryStore()
    private let requestHandler = VNSequenceRequestHandler()
    private var request: VNDetectTrajectoriesRequest!
    private let syncQueue = DispatchQueue(label: "com.shottracer.trajectory", qos: .userInteractive)
    
    // Frame counting for debug
    private var frameCount = 0
    private var detectionCount = 0

    init() {
        request = makeRequest()
    }

    func start() {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameCount = 0
            self.detectionCount = 0
            self.isRunning = true
            self.trajectoryStore.reset()
            self.request = self.makeRequest()
            
            if self.debugLogging {
                print("═══════════════════════════════════════")
                print("🎯 TRAJECTORY DETECTOR STARTED")
                print("   ROI: \(self.regionOfInterest?.debugDescription ?? "full frame")")
                print("   Orientation: \(self.orientation.rawValue)")
                print("═══════════════════════════════════════")
            }
        }
    }

    func stop() {
        syncQueue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.isRunning = false
            let finalTraj = self.trajectoryStore.getTrajectoryForRendering()
            
            if self.debugLogging {
                print("═══════════════════════════════════════")
                print("🛑 TRAJECTORY DETECTOR STOPPED")
                print("   Frames processed: \(self.frameCount)")
                print("   Detections: \(self.detectionCount)")
                if let traj = finalTraj {
                    print("   Final: \(traj.detectedPoints.count) detected, \(traj.projectedPoints.count) projected")
                } else {
                    print("   Final trajectory: NONE")
                }
                print("═══════════════════════════════════════")
            }
            
            DispatchQueue.main.async {
                self.delegate?.trajectoryDetectorDidFinish(self, finalTrajectory: finalTraj)
            }
        }
    }

    func process(sampleBuffer: CMSampleBuffer) {
        syncQueue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            
            self.frameCount += 1
            
            // Tick trajectory store to age out stale trajectories
            self.trajectoryStore.tick()

            // Update ROI
            if let roi = self.regionOfInterest {
                self.request.regionOfInterest = roi
            } else {
                // Default: full frame for robustness in debug/test videos
                self.request.regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
            }

            do {
                try self.requestHandler.perform([self.request], on: sampleBuffer, orientation: self.orientation)
            } catch {
                if self.debugLogging && self.frameCount % 60 == 0 {
                    print("⚠️ Vision error: \(error.localizedDescription)")
                }
            }
        }
    }

    func update(frameSpacingSeconds: Double) {
        frameAnalysisSpacing = CMTime(seconds: frameSpacingSeconds, preferredTimescale: 600)
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            if self.isRunning {
                self.request = self.makeRequest()
            }
        }
    }
    
    /// Get current trajectory for rendering
    var currentTrajectory: Trajectory? {
        trajectoryStore.getTrajectoryForRendering()
    }

    // MARK: - Vision Request Configuration
    
    private func makeRequest() -> VNDetectTrajectoriesRequest {
        // ═══════════════════════════════════════════════════════════════
        // VISION TRAJECTORY DETECTION - THE KEY TO SMOOTHSWING!
        // ═══════════════════════════════════════════════════════════════
        //
        // VNDetectTrajectoriesRequest detects objects following PARABOLIC paths
        // It provides:
        // - detectedPoints: Actual observations
        // - projectedPoints: Full predicted arc (THIS IS THE MAGIC!)
        // - equationCoefficients: Parabola equation y = ax² + bx + c
        //
        // trajectoryLength: Minimum frames needed before detection fires
        // - Higher = more confident but delayed
        // - Lower = faster but more false positives
        // - 10 is Mizuno's default, works well for golf
        //
        // ═══════════════════════════════════════════════════════════════
        
        let request = VNDetectTrajectoriesRequest(
            frameAnalysisSpacing: frameAnalysisSpacing,
            trajectoryLength: 8  // Slightly shorter to trigger sooner in low-contrast/night footage
        ) { [weak self] req, error in
            guard let self = self else { return }
            if let error = error {
                if self.debugLogging {
                    print("❌ Trajectory request error: \(error)")
                }
                return
            }
            self.handleResults(request: req)
        }
        
        // ═══════════════════════════════════════════════════════════════
        // SIZE FILTERING - DON'T OVER-CONSTRAIN!
        // ═══════════════════════════════════════════════════════════════
        //
        // The original Mizuno code does NOT set these, using Vision's defaults.
        // This lets Vision detect ANY parabolic trajectory.
        //
        // If we want to filter for golf balls specifically:
        // - At 10m distance: ball ≈ 0.4% of frame = 0.004 radius
        // - At 5m distance: ball ≈ 0.8% of frame = 0.008 radius
        // - With motion blur, apparent size increases
        //
        // Being too restrictive causes missed detections!
        // Start permissive, filter by trajectory shape instead.
        // ═══════════════════════════════════════════════════════════════
        
        // Option 1: Don't set (use Vision defaults - most permissive)
        // This is what Mizuno does and it WORKS
        
        // Option 2: Set wide range for golf balls
        // Night/low contrast needs a wider net
        request.objectMinimumNormalizedRadius = 0.001  // very small distant ball
        request.objectMaximumNormalizedRadius = 0.12   // allow larger/motion-blurred blobs
        
        // Target frame time for real-time processing (iOS 15+)
        if #available(iOS 15.0, *) {
            // Let Vision keep up with 120–240 fps feeds while still analyzing every frame
            request.targetFrameTime = CMTime(value: 1, timescale: 240)
        }
        
        if debugLogging {
            print("📐 Vision Request Configured:")
            print("   Trajectory length: 10 frames")
            print("   Frame spacing: \(frameAnalysisSpacing.seconds)s")
            print("   Size filtering: 0.003 - 0.08 (golf tuned)")
        }
        
        return request
    }

    // MARK: - Result Handling
    
    private func handleResults(request: VNRequest) {
        guard let observations = request.results as? [VNTrajectoryObservation] else {
            return
        }
        
        if observations.isEmpty {
            return
        }
        
        // Process all observations
        for observation in observations {
            detectionCount += 1
            trajectoryStore.update(with: observation)
            
            if debugLogging && detectionCount % 5 == 0 {
                print("🔍 Detection #\(detectionCount):")
                print("   UUID: \(observation.uuid.uuidString.prefix(8))...")
                print("   Confidence: \(String(format: "%.2f", observation.confidence))")
                print("   Detected points: \(observation.detectedPoints.count)")
                print("   Projected points: \(observation.projectedPoints.count)")
                print("   Equation: \(observation.equationCoefficients)")
            }
        }
        
        // Notify delegate with current best trajectory
        if let trajectory = trajectoryStore.getTrajectoryForRendering() {
            DispatchQueue.main.async {
                self.delegate?.trajectoryDetector(self, didUpdate: trajectory)
            }
        }
    }
}

// MARK: - Trajectory Validation Utilities

extension TrajectoryDetector {
    
    /// Validate that a trajectory looks like a golf shot
    static func isValidGolfShot(_ trajectory: Trajectory, startingNear expectedStart: CGPoint? = nil) -> Bool {
        // Must have enough points
        guard trajectory.projectedPoints.count >= 5 else { return false }
        
        // Confidence check
        guard trajectory.confidence > 0.3 else { return false }
        
        // If we know where ball should start, check proximity
        if let expected = expectedStart,
           let first = trajectory.detectedPoints.first {
            let dx = abs(first.normalized.x - expected.x)
            let dy = abs(first.normalized.y - expected.y)
            let distance = sqrt(dx * dx + dy * dy)
            
            // Ball should start within 20% of expected position
            if distance > 0.2 {
                return false
            }
        }
        
        // Check trajectory goes UP then DOWN (parabola shape)
        let points = trajectory.projectedPoints.map { $0.normalized }
        if let midIndex = points.indices.middle {
            let start = points.first!
            let mid = points[midIndex]
            let end = points.last!
            
            // In UIKit coords (Y down): ball goes UP (Y decreases) then DOWN (Y increases)
            let wentUp = mid.y < start.y
            let cameDown = end.y > mid.y - 0.05  // Allow small tolerance
            
            if !wentUp {
                return false  // Ball never went up
            }
        }
        
        return true
    }
}

// Helper extension
extension Collection {
    var middle: Index? {
        guard !isEmpty else { return nil }
        return index(startIndex, offsetBy: count / 2)
    }
}
