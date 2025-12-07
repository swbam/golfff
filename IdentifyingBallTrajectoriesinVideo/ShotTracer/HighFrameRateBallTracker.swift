import AVFoundation
import CoreImage
import Accelerate

/// High Frame Rate Ball Tracker
/// 
/// KEY INSIGHT: At 240fps, golf ball tracking becomes EASY:
/// - Ball moves only ~1 foot per frame (vs 4 feet at 60fps)
/// - Search window can be tiny
/// - Simple white blob detection works!
/// 
/// The silhouette provides the KNOWN starting position.
/// No user tap required - it's built into the alignment.
final class HighFrameRateBallTracker {
    
    // MARK: - Types
    
    struct TrackedPoint {
        let position: CGPoint      // Normalized 0-1
        let timestamp: CMTime
        let confidence: Float
    }
    
    struct TrackingResult {
        let currentPosition: CGPoint?
        let trajectoryPoints: [TrackedPoint]
        let isTracking: Bool
    }
    
    // MARK: - Configuration
    
    /// Expected frame rate (affects search window size)
    var frameRate: Double = 240 {
        didSet { updateSearchWindowSize() }
    }
    
    /// Debug logging
    var debugLogging = false
    
    // MARK: - State
    
    /// Ball position from silhouette alignment (KNOWN before tracking starts)
    private var initialBallPosition: CGPoint?
    
    /// Last detected position
    private var lastPosition: CGPoint?
    
    /// All tracked points with timestamps
    private var trajectoryPoints: [TrackedPoint] = []
    
    /// Is tracking active (after impact)
    private var isTracking = false
    
    /// Frames since last detection
    private var framesSinceDetection = 0
    
    /// Maximum frames without detection before stopping
    private let maxMissingFrames = 30  // ~0.125 seconds at 240fps
    
    // MARK: - Search Parameters (tuned for 240fps)
    
    /// Search window size as fraction of frame
    /// At 240fps with ball moving ~1 foot/frame and 10ft viewing width:
    /// Ball moves ~10% of frame per frame max
    private var searchWindowSize: CGFloat = 0.15
    
    /// Minimum brightness for white ball (0-255)
    private let minBrightness: UInt8 = 180
    
    /// Maximum saturation for white (0-255)
    private let maxSaturation: UInt8 = 70
    
    /// Minimum blob size in pixels
    private let minBlobPixels = 3
    
    /// Maximum blob size in pixels
    private let maxBlobPixels = 400
    
    // MARK: - Initialization
    
    init() {
        updateSearchWindowSize()
    }
    
    private func updateSearchWindowSize() {
        // At higher frame rates, ball moves less per frame = smaller search window
        // 240fps: ~0.10 of frame per frame
        // 120fps: ~0.20 of frame per frame
        // 60fps:  ~0.40 of frame per frame
        searchWindowSize = CGFloat(0.15 * (60.0 / frameRate) * 2)
    }
    
    // MARK: - Public API
    
    /// Set the initial ball position from silhouette alignment
    /// This is called when user "locks in" - NO TAP REQUIRED
    func setInitialBallPosition(_ position: CGPoint) {
        initialBallPosition = position
        lastPosition = position
        trajectoryPoints.removeAll()
        isTracking = false
        framesSinceDetection = 0
        
        if debugLogging {
            print("🎯 Ball position set from silhouette: (\(String(format: "%.3f", position.x)), \(String(format: "%.3f", position.y)))")
        }
    }
    
    /// Start tracking (called when impact is detected)
    func startTracking() {
        guard initialBallPosition != nil else {
            print("❌ Cannot start tracking - no initial position set")
            return
        }
        
        isTracking = true
        framesSinceDetection = 0
        
        // Add initial position as first trajectory point
        if let pos = initialBallPosition {
            trajectoryPoints.append(TrackedPoint(
                position: pos,
                timestamp: .zero,
                confidence: 1.0
            ))
        }
        
        if debugLogging {
            print("💥 Ball tracking started from silhouette position")
        }
    }
    
    /// Stop tracking
    func stopTracking() {
        isTracking = false
        
        if debugLogging {
            print("🛑 Ball tracking stopped - \(trajectoryPoints.count) points")
        }
    }
    
    /// Process a frame (call for every frame at high frame rate!)
    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime, orientation: CGImagePropertyOrientation) -> TrackingResult {
        
        guard isTracking else {
            return TrackingResult(
                currentPosition: lastPosition,
                trajectoryPoints: trajectoryPoints,
                isTracking: false
            )
        }
        
        // Get search window centered on last known position
        guard let searchCenter = lastPosition else {
            return TrackingResult(
                currentPosition: nil,
                trajectoryPoints: trajectoryPoints,
                isTracking: isTracking
            )
        }
        
        // Search window - small at 240fps!
        let searchWindow = CGRect(
            x: max(0, searchCenter.x - searchWindowSize / 2),
            y: max(0, searchCenter.y - searchWindowSize),  // More upward (ball goes up)
            width: min(1, searchWindowSize),
            height: min(1, searchWindowSize * 1.5)  // Taller than wide
        )
        
        // Find ball in search window
        if let detected = findBall(in: pixelBuffer, searchWindow: searchWindow, orientation: orientation) {
            // Found the ball!
            lastPosition = detected.position
            framesSinceDetection = 0
            
            trajectoryPoints.append(TrackedPoint(
                position: detected.position,
                timestamp: timestamp,
                confidence: detected.confidence
            ))
            
            if debugLogging && trajectoryPoints.count % 20 == 0 {
                print("🎾 Frame \(trajectoryPoints.count): (\(String(format: "%.3f", detected.position.x)), \(String(format: "%.3f", detected.position.y)))")
            }
            
            return TrackingResult(
                currentPosition: detected.position,
                trajectoryPoints: trajectoryPoints,
                isTracking: true
            )
        } else {
            // Didn't find ball - use prediction
            framesSinceDetection += 1
            
            // Predict position using simple physics (ball continues in parabolic arc)
            if let predicted = predictNextPosition() {
                lastPosition = predicted
            }
            
            // Stop tracking if lost for too long
            if framesSinceDetection >= maxMissingFrames {
                stopTracking()
            }
            
            return TrackingResult(
                currentPosition: lastPosition,
                trajectoryPoints: trajectoryPoints,
                isTracking: isTracking
            )
        }
    }
    
    /// Build trajectory from tracked points
    func buildTrajectory() -> Trajectory? {
        guard trajectoryPoints.count >= 3 else {
            if debugLogging {
                print("⚠️ Not enough points for trajectory: \(trajectoryPoints.count)")
            }
            return nil
        }
        
        // Convert to TrajectoryPoint format
        let points = trajectoryPoints.map { tracked in
            TrajectoryPoint(time: tracked.timestamp, normalized: tracked.position)
        }
        
        // Smooth the trajectory
        let smoothed = smoothTrajectory(points)
        
        if debugLogging {
            print("✅ Built trajectory: \(smoothed.count) points")
        }
        
        return Trajectory(
            id: UUID(),
            detectedPoints: points,
            projectedPoints: smoothed,  // Smoothed version for rendering
            equationCoefficients: simd_float3(0, 0, 0),
            confidence: 0.9
        )
    }
    
    /// Reset tracker
    func reset() {
        initialBallPosition = nil
        lastPosition = nil
        trajectoryPoints.removeAll()
        isTracking = false
        framesSinceDetection = 0
    }
    
    // MARK: - Ball Detection (Simple at 240fps!)
    
    private struct BallDetection {
        let position: CGPoint
        let confidence: Float
    }
    
    private func findBall(in pixelBuffer: CVPixelBuffer, searchWindow: CGRect, orientation: CGImagePropertyOrientation) -> BallDetection? {
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Convert normalized search window to pixels
        var pixelWindow = CGRect(
            x: CGFloat(width) * searchWindow.minX,
            y: CGFloat(height) * searchWindow.minY,
            width: CGFloat(width) * searchWindow.width,
            height: CGFloat(height) * searchWindow.height
        )
        
        // Apply orientation transform
        pixelWindow = applyOrientation(pixelWindow, width: width, height: height, orientation: orientation)
        
        let minX = max(0, Int(pixelWindow.minX))
        let maxX = min(width - 1, Int(pixelWindow.maxX))
        let minY = max(0, Int(pixelWindow.minY))
        let maxY = min(height - 1, Int(pixelWindow.maxY))
        
        // Find brightest white blob in search window
        var bestCandidate: (x: Int, y: Int, brightness: Int, count: Int)?
        var visited = Set<Int>()
        
        for y in stride(from: minY, to: maxY, by: 2) {  // Skip pixels for speed
            for x in stride(from: minX, to: maxX, by: 2) {
                let idx = y * width + x
                guard !visited.contains(idx) else { continue }
                
                let offset = y * bytesPerRow + x * 4
                let b = buffer[offset]
                let g = buffer[offset + 1]
                let r = buffer[offset + 2]
                
                // Check if pixel is white enough
                if isWhiteBallPixel(r: r, g: g, b: b) {
                    // Found white pixel - do quick blob size estimate
                    let blobInfo = estimateBlobSize(buffer: buffer, startX: x, startY: y,
                                                    width: width, height: height, bytesPerRow: bytesPerRow,
                                                    minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                                                    visited: &visited)
                    
                    if blobInfo.count >= minBlobPixels && blobInfo.count <= maxBlobPixels {
                        let brightness = Int(r) + Int(g) + Int(b)
                        
                        if bestCandidate == nil || brightness > bestCandidate!.brightness {
                            bestCandidate = (blobInfo.centerX, blobInfo.centerY, brightness, blobInfo.count)
                        }
                    }
                }
            }
        }
        
        guard let candidate = bestCandidate else { return nil }
        
        // Convert back to normalized coordinates
        var normalizedPos = CGPoint(
            x: CGFloat(candidate.x) / CGFloat(width),
            y: CGFloat(candidate.y) / CGFloat(height)
        )
        
        // Reverse orientation transform
        normalizedPos = reverseOrientation(normalizedPos, orientation: orientation)
        
        let confidence = Float(candidate.brightness) / (255.0 * 3)
        
        return BallDetection(position: normalizedPos, confidence: confidence)
    }
    
    private func isWhiteBallPixel(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        
        // Brightness check
        guard maxC >= minBrightness else { return false }
        
        // Saturation check (white = low saturation)
        let saturation: UInt8
        if maxC == 0 {
            saturation = 0
        } else {
            saturation = UInt8(((Int(maxC) - Int(minC)) * 255) / Int(maxC))
        }
        
        return saturation <= maxSaturation
    }
    
    private func estimateBlobSize(buffer: UnsafePointer<UInt8>, startX: Int, startY: Int,
                                   width: Int, height: Int, bytesPerRow: Int,
                                   minX: Int, maxX: Int, minY: Int, maxY: Int,
                                   visited: inout Set<Int>) -> (centerX: Int, centerY: Int, count: Int) {
        
        var queue = [(startX, startY)]
        var sumX = 0, sumY = 0, count = 0
        
        while !queue.isEmpty && count < maxBlobPixels {
            let (x, y) = queue.removeFirst()
            let idx = y * width + x
            
            guard !visited.contains(idx) else { continue }
            guard x >= minX && x <= maxX && y >= minY && y <= maxY else { continue }
            
            visited.insert(idx)
            
            let offset = y * bytesPerRow + x * 4
            let b = buffer[offset]
            let g = buffer[offset + 1]
            let r = buffer[offset + 2]
            
            guard isWhiteBallPixel(r: r, g: g, b: b) else { continue }
            
            sumX += x
            sumY += y
            count += 1
            
            // Add neighbors (4-connected, skip for speed)
            queue.append((x + 1, y))
            queue.append((x - 1, y))
            queue.append((x, y + 1))
            queue.append((x, y - 1))
        }
        
        guard count > 0 else { return (startX, startY, 0) }
        
        return (sumX / count, sumY / count, count)
    }
    
    // MARK: - Prediction
    
    private func predictNextPosition() -> CGPoint? {
        guard trajectoryPoints.count >= 2 else { return lastPosition }
        
        let recent = Array(trajectoryPoints.suffix(3))
        guard recent.count >= 2 else { return lastPosition }
        
        // Simple linear prediction based on last two points
        let p1 = recent[recent.count - 2].position
        let p2 = recent[recent.count - 1].position
        
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        
        // Add gravity effect (ball curves downward)
        let gravity: CGFloat = 0.001  // Small at 240fps
        
        return CGPoint(
            x: p2.x + dx,
            y: p2.y + dy + gravity
        )
    }
    
    // MARK: - Coordinate Transforms
    
    private func applyOrientation(_ rect: CGRect, width: Int, height: Int, orientation: CGImagePropertyOrientation) -> CGRect {
        switch orientation {
        case .right:  // 90° CW (portrait)
            return CGRect(
                x: rect.minY * CGFloat(width),
                y: (1 - rect.maxX) * CGFloat(height),
                width: rect.height * CGFloat(width),
                height: rect.width * CGFloat(height)
            )
        case .left:  // 90° CCW
            return CGRect(
                x: (1 - rect.maxY) * CGFloat(width),
                y: rect.minX * CGFloat(height),
                width: rect.height * CGFloat(width),
                height: rect.width * CGFloat(height)
            )
        default:
            return CGRect(
                x: rect.minX * CGFloat(width),
                y: rect.minY * CGFloat(height),
                width: rect.width * CGFloat(width),
                height: rect.height * CGFloat(height)
            )
        }
    }
    
    private func reverseOrientation(_ point: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
        switch orientation {
        case .right:
            return CGPoint(x: 1 - point.y, y: point.x)
        case .left:
            return CGPoint(x: point.y, y: 1 - point.x)
        default:
            return point
        }
    }
    
    // MARK: - Smoothing
    
    private func smoothTrajectory(_ points: [TrajectoryPoint]) -> [TrajectoryPoint] {
        guard points.count >= 3 else { return points }
        
        var smoothed: [TrajectoryPoint] = []
        
        for i in 0..<points.count {
            if i == 0 || i == points.count - 1 {
                smoothed.append(points[i])
            } else {
                let prev = points[i - 1]
                let curr = points[i]
                let next = points[i + 1]
                
                let smoothX = (prev.normalized.x + curr.normalized.x * 2 + next.normalized.x) / 4
                let smoothY = (prev.normalized.y + curr.normalized.y * 2 + next.normalized.y) / 4
                
                smoothed.append(TrajectoryPoint(
                    time: curr.time,
                    normalized: CGPoint(x: smoothX, y: smoothY)
                ))
            }
        }
        
        return smoothed
    }
}


