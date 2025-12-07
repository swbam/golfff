import AVFoundation
import Vision
import CoreImage

/// Live Shot Detector - Detects golf swings and tracks balls in real-time
/// Uses: Person segmentation + Pose detection + Ball tracking
@available(iOS 15.0, *)
final class LiveShotDetector {
    
    // MARK: - Types
    enum SwingPhase {
        case setup      // Player at address
        case backswing  // Club going back
        case downswing  // Club coming down
        case impact     // Club hits ball
        case followThru // After impact
        case idle       // No swing detected
    }
    
    struct DetectionResult {
        let personMask: CIImage?
        let swingPhase: SwingPhase
        let ballPosition: CGPoint?  // Normalized 0-1
        let isLocked: Bool
    }
    
    // MARK: - Callbacks
    var onSwingPhaseChanged: ((SwingPhase) -> Void)?
    var onBallDetected: ((CGPoint) -> Void)?
    var onLockStatusChanged: ((Bool) -> Void)?
    var onTrajectoryUpdated: (([CGPoint]) -> Void)?
    
    // MARK: - Properties
    private let sequenceHandler = VNSequenceRequestHandler()
    
    // Person segmentation
    private lazy var segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    
    // Body pose detection
    private lazy var poseRequest: VNDetectHumanBodyPoseRequest = {
        let request = VNDetectHumanBodyPoseRequest()
        return request
    }()
    
    // State
    private var isLocked = false
    private var lockedBallPosition: CGPoint?
    private var previousWristY: CGFloat?
    private var currentPhase: SwingPhase = .idle
    private var impactDetected = false
    private var trajectoryPoints: [CGPoint] = []
    
    // Ball tracking
    private var lastKnownBallPosition: CGPoint?
    private var previousFrameBuffer: CVPixelBuffer?
    
    // Timing
    private var impactTime: Date?
    private let postImpactTrackingDuration: TimeInterval = 3.0
    
    // MARK: - Public API
    
    /// Lock in the current position (called when alignment is confirmed)
    func lockPosition(ballPosition: CGPoint) {
        isLocked = true
        lockedBallPosition = ballPosition
        lastKnownBallPosition = ballPosition
        impactDetected = false
        trajectoryPoints.removeAll()
        
        print("🔒 Position LOCKED - Ball at: (\(String(format: "%.3f", ballPosition.x)), \(String(format: "%.3f", ballPosition.y)))")
        
        // Trigger haptic feedback
        onLockStatusChanged?(true)
    }
    
    /// Unlock and reset
    func unlock() {
        isLocked = false
        lockedBallPosition = nil
        impactDetected = false
        trajectoryPoints.removeAll()
        currentPhase = .idle
        
        onLockStatusChanged?(false)
    }
    
    /// Process a live camera frame
    func processFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> DetectionResult {
        var personMask: CIImage?
        var detectedBallPosition: CGPoint?
        
        // 1. Person Segmentation (for silhouette overlay)
        do {
            try sequenceHandler.perform([segmentationRequest], on: pixelBuffer, orientation: orientation)
            if let maskBuffer = segmentationRequest.results?.first?.pixelBuffer {
                personMask = CIImage(cvPixelBuffer: maskBuffer)
            }
        } catch {
            // Non-fatal
        }
        
        // 2. Body Pose Detection (for swing phase)
        do {
            try sequenceHandler.perform([poseRequest], on: pixelBuffer, orientation: orientation)
            if let pose = poseRequest.results?.first {
                detectSwingPhase(from: pose)
            }
        } catch {
            // Non-fatal
        }
        
        // 3. Ball Tracking (after impact)
        if isLocked && impactDetected {
            detectedBallPosition = trackBall(in: pixelBuffer, orientation: orientation)
        }
        
        previousFrameBuffer = pixelBuffer
        
        return DetectionResult(
            personMask: personMask,
            swingPhase: currentPhase,
            ballPosition: detectedBallPosition,
            isLocked: isLocked
        )
    }
    
    /// Get current trajectory
    func getTrajectory() -> [CGPoint] {
        return trajectoryPoints
    }
    
    /// Build final trajectory
    func buildTrajectory() -> Trajectory? {
        guard trajectoryPoints.count >= 3 else { return nil }
        
        let points = trajectoryPoints.enumerated().map { index, point in
            TrajectoryPoint(
                time: CMTime(seconds: Double(index) * 0.033, preferredTimescale: 600), // ~30fps
                normalized: point
            )
        }
        
        return Trajectory(id: UUID(), points: points, confidence: 0.9)
    }
    
    // MARK: - Swing Phase Detection
    
    private func detectSwingPhase(from pose: VNHumanBodyPoseObservation) {
        // Get key points for swing detection
        guard let rightWrist = try? pose.recognizedPoint(.rightWrist),
              let leftWrist = try? pose.recognizedPoint(.leftWrist),
              let rightShoulder = try? pose.recognizedPoint(.rightShoulder),
              rightWrist.confidence > 0.3,
              leftWrist.confidence > 0.3 else {
            return
        }
        
        // Average wrist position (club position proxy)
        let wristY = (rightWrist.location.y + leftWrist.location.y) / 2
        _ = (rightWrist.location.x + leftWrist.location.x) / 2  // wristX for future use
        let shoulderY = rightShoulder.location.y
        
        let oldPhase = currentPhase
        
        // Detect swing phases based on wrist position relative to shoulder
        if let prevY = previousWristY {
            let wristMovement = wristY - prevY
            
            switch currentPhase {
            case .idle, .setup:
                // Wrists near waist level = setup
                if wristY < shoulderY - 0.1 {
                    currentPhase = .setup
                }
                // Wrists moving up significantly = backswing starting
                if wristMovement > 0.02 && wristY > shoulderY {
                    currentPhase = .backswing
                }
                
            case .backswing:
                // Wrists at highest point and starting to come down
                if wristMovement < -0.02 {
                    currentPhase = .downswing
                    print("⬇️ DOWNSWING detected")
                }
                
            case .downswing:
                // Wrists back at ball level with high velocity = impact
                if wristY < shoulderY - 0.05 && abs(wristMovement) > 0.03 {
                    currentPhase = .impact
                    impactDetected = true
                    impactTime = Date()
                    lastKnownBallPosition = lockedBallPosition
                    print("💥 IMPACT detected! Starting ball tracking...")
                    
                    // Add initial ball position
                    if let ballPos = lockedBallPosition {
                        trajectoryPoints.append(ballPos)
                    }
                }
                
            case .impact:
                // Transition to follow through
                currentPhase = .followThru
                
            case .followThru:
                // Check if we should stop tracking
                if let impactT = impactTime, 
                   Date().timeIntervalSince(impactT) > postImpactTrackingDuration {
                    currentPhase = .idle
                    print("✅ Shot complete - \(trajectoryPoints.count) trajectory points")
                }
            }
        }
        
        previousWristY = wristY
        
        // Notify if phase changed
        if oldPhase != currentPhase {
            onSwingPhaseChanged?(currentPhase)
        }
    }
    
    // MARK: - Ball Tracking
    
    private func trackBall(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGPoint? {
        guard let lastPos = lastKnownBallPosition else { return nil }
        
        // Don't track too long after impact
        if let impactT = impactTime,
           Date().timeIntervalSince(impactT) > postImpactTrackingDuration {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Search area - ball should be moving UP and slightly forward from last position
        // Expand search upward more than downward
        let searchRadius: CGFloat = 0.08
        let upwardBias: CGFloat = 0.05
        
        let searchMinX = max(0, Int((lastPos.x - searchRadius) * CGFloat(width)))
        let searchMaxX = min(width - 1, Int((lastPos.x + searchRadius) * CGFloat(width)))
        let searchMinY = max(0, Int((lastPos.y - searchRadius - upwardBias) * CGFloat(height)))
        let searchMaxY = min(height - 1, Int((lastPos.y + searchRadius * 0.5) * CGFloat(height)))
        
        // Find brightest cluster (white ball against sky)
        var brightPixels: [(x: Int, y: Int, brightness: Int)] = []
        let whiteThreshold: UInt8 = 220
        
        for y in searchMinY...searchMaxY {
            for x in searchMinX...searchMaxX {
                let offset = y * bytesPerRow + x * 4
                let b = buffer[offset]
                let g = buffer[offset + 1]
                let r = buffer[offset + 2]
                
                let brightness = (Int(r) + Int(g) + Int(b)) / 3
                if brightness > Int(whiteThreshold) {
                    brightPixels.append((x, y, brightness))
                }
            }
        }
        
        guard brightPixels.count >= 3 else { return nil }
        
        // Find centroid of bright pixels
        let sortedByBrightness = brightPixels.sorted { $0.brightness > $1.brightness }
        let topPixels = Array(sortedByBrightness.prefix(50))
        
        let totalX = topPixels.reduce(0) { $0 + $1.x }
        let totalY = topPixels.reduce(0) { $0 + $1.y }
        
        let centerX = CGFloat(totalX) / CGFloat(topPixels.count)
        let centerY = CGFloat(totalY) / CGFloat(topPixels.count)
        
        // Normalize
        var normalizedX = centerX / CGFloat(width)
        var normalizedY = centerY / CGFloat(height)
        
        // Apply orientation correction
        switch orientation {
        case .right:
            let temp = normalizedX
            normalizedX = 1 - normalizedY
            normalizedY = temp
        case .left:
            let temp = normalizedX
            normalizedX = normalizedY
            normalizedY = 1 - temp
        case .down:
            normalizedX = 1 - normalizedX
            normalizedY = 1 - normalizedY
        default:
            break
        }
        
        // Validate: ball should be moving upward (lower Y in Vision coords) after impact
        if let lastY = trajectoryPoints.last?.y {
            // In normalized coords, ball going UP means Y is decreasing
            if normalizedY > lastY + 0.02 {
                // Ball moving down too much - probably lost it
                return nil
            }
        }
        
        let newPosition = CGPoint(x: normalizedX, y: normalizedY)
        lastKnownBallPosition = newPosition
        trajectoryPoints.append(newPosition)
        
        onBallDetected?(newPosition)
        onTrajectoryUpdated?(trajectoryPoints)
        
        return newPosition
    }
}

