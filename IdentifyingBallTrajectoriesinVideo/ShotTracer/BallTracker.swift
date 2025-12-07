import AVFoundation
import CoreImage
import Accelerate

/// Ball Tracker - Tracks a golf ball from a KNOWN starting position
/// This is how SmoothSwing works - user identifies ball, then we track it
final class BallTracker {
    
    struct TrackedBall {
        let position: CGPoint  // Normalized 0-1
        let confidence: Float
        let frameTime: CMTime
    }
    
    // MARK: - Properties
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Initial ball position (set by user)
    private var initialBallPosition: CGPoint?
    private var lastKnownPosition: CGPoint?
    private var trackedPositions: [TrackedBall] = []
    
    // Previous frame for motion detection
    private var previousPixelBuffer: CVPixelBuffer?
    
    // Search parameters
    private let searchRadius: CGFloat = 0.15  // Search within 15% of frame from last position
    private let whiteThreshold: UInt8 = 200   // Brightness threshold for white ball
    private let minBlobPixels = 5
    private let maxBlobPixels = 200
    
    // MARK: - Public API
    
    /// Set the initial ball position (user taps on ball)
    func setInitialBallPosition(_ position: CGPoint) {
        initialBallPosition = position
        lastKnownPosition = position
        trackedPositions.removeAll()
        previousPixelBuffer = nil
        
        print("🎯 Initial ball position set: (\(String(format: "%.3f", position.x)), \(String(format: "%.3f", position.y)))")
    }
    
    /// Process a frame and track the ball
    func processFrame(_ pixelBuffer: CVPixelBuffer, time: CMTime, orientation: CGImagePropertyOrientation) -> TrackedBall? {
        guard let searchCenter = lastKnownPosition ?? initialBallPosition else {
            print("⚠️ No initial ball position set")
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Lock the pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Apply orientation correction to search center
        let correctedCenter = applyOrientation(searchCenter, orientation: orientation)
        
        // Define search area (expanded from last known position)
        let searchMinX = max(0, Int((correctedCenter.x - searchRadius) * CGFloat(width)))
        let searchMaxX = min(width - 1, Int((correctedCenter.x + searchRadius) * CGFloat(width)))
        let searchMinY = max(0, Int((correctedCenter.y - searchRadius) * CGFloat(height)))
        let searchMaxY = min(height - 1, Int((correctedCenter.y + searchRadius) * CGFloat(height)))
        
        // Find white pixels in search area
        var whitePixels: [(x: Int, y: Int, brightness: Int)] = []
        
        for y in searchMinY...searchMaxY {
            for x in searchMinX...searchMaxX {
                let offset = y * bytesPerRow + x * 4
                let b = buffer[offset]
                let g = buffer[offset + 1]
                let r = buffer[offset + 2]
                
                // Check if pixel is bright (white ball)
                let brightness = (Int(r) + Int(g) + Int(b)) / 3
                if brightness > Int(whiteThreshold) {
                    whitePixels.append((x, y, brightness))
                }
            }
        }
        
        // Find the brightest cluster (ball)
        guard whitePixels.count >= minBlobPixels else {
            // Ball not found in search area - expand search for next frame
            return nil
        }
        
        // Cluster the white pixels and find the most ball-like cluster
        if let ballCluster = findBallCluster(whitePixels, width: width, height: height) {
            let normalizedX = CGFloat(ballCluster.centerX) / CGFloat(width)
            let normalizedY = CGFloat(ballCluster.centerY) / CGFloat(height)
            
            // Correct for orientation back to standard coordinates
            let finalPosition = reverseOrientation(CGPoint(x: normalizedX, y: normalizedY), orientation: orientation)
            
            // Validate the detection - ball should be moving upward/outward from start
            if let initial = initialBallPosition {
                let dy = finalPosition.y - initial.y
                // Ball should be going UP (negative y in UIKit) after impact
                // Allow some tolerance for the initial frames
                if trackedPositions.count > 3 && dy > 0.05 {
                    // Ball moving down too much - probably not the ball
                    return nil
                }
            }
            
            let tracked = TrackedBall(
                position: finalPosition,
                confidence: Float(ballCluster.brightness) / 255.0,
                frameTime: time
            )
            
            lastKnownPosition = finalPosition
            trackedPositions.append(tracked)
            
            return tracked
        }
        
        return nil
    }
    
    /// Build trajectory from tracked positions
    func buildTrajectory() -> Trajectory? {
        guard trackedPositions.count >= 3 else {
            print("⚠️ Not enough tracked positions: \(trackedPositions.count)")
            return nil
        }
        
        // Filter for smooth trajectory
        let smoothed = smoothTrajectory(trackedPositions)
        
        guard smoothed.count >= 3 else { return nil }
        
        let points = smoothed.map { tracked in
            TrajectoryPoint(time: tracked.frameTime, normalized: tracked.position)
        }
        
        let avgConfidence = smoothed.reduce(0) { $0 + $1.confidence } / Float(smoothed.count)
        
        print("✅ Built trajectory with \(points.count) points")
        
        return Trajectory(
            id: UUID(),
            points: points,
            confidence: avgConfidence
        )
    }
    
    /// Reset tracker
    func reset() {
        initialBallPosition = nil
        lastKnownPosition = nil
        trackedPositions.removeAll()
        previousPixelBuffer = nil
    }
    
    // MARK: - Private Helpers
    
    private struct BallCluster {
        let centerX: Int
        let centerY: Int
        let pixelCount: Int
        let brightness: Int
    }
    
    private func findBallCluster(_ pixels: [(x: Int, y: Int, brightness: Int)], width: Int, height: Int) -> BallCluster? {
        guard !pixels.isEmpty else { return nil }
        
        // Simple centroid calculation for the brightest pixels
        // In a real implementation, you'd do proper clustering
        
        let sortedByBrightness = pixels.sorted { $0.brightness > $1.brightness }
        let topPixels = Array(sortedByBrightness.prefix(maxBlobPixels))
        
        guard topPixels.count >= minBlobPixels else { return nil }
        
        let totalX = topPixels.reduce(0) { $0 + $1.x }
        let totalY = topPixels.reduce(0) { $0 + $1.y }
        let avgBrightness = topPixels.reduce(0) { $0 + $1.brightness } / topPixels.count
        
        return BallCluster(
            centerX: totalX / topPixels.count,
            centerY: totalY / topPixels.count,
            pixelCount: topPixels.count,
            brightness: avgBrightness
        )
    }
    
    private func smoothTrajectory(_ positions: [TrackedBall]) -> [TrackedBall] {
        guard positions.count >= 3 else { return positions }
        
        var smoothed: [TrackedBall] = []
        
        for i in 0..<positions.count {
            if i == 0 || i == positions.count - 1 {
                smoothed.append(positions[i])
            } else {
                // Simple moving average
                let prev = positions[i - 1]
                let curr = positions[i]
                let next = positions[i + 1]
                
                let smoothX = (prev.position.x + curr.position.x + next.position.x) / 3
                let smoothY = (prev.position.y + curr.position.y + next.position.y) / 3
                
                smoothed.append(TrackedBall(
                    position: CGPoint(x: smoothX, y: smoothY),
                    confidence: curr.confidence,
                    frameTime: curr.frameTime
                ))
            }
        }
        
        return smoothed
    }
    
    private func applyOrientation(_ point: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
        switch orientation {
        case .right: // 90° CW
            return CGPoint(x: point.y, y: 1 - point.x)
        case .left: // 90° CCW
            return CGPoint(x: 1 - point.y, y: point.x)
        case .down: // 180°
            return CGPoint(x: 1 - point.x, y: 1 - point.y)
        default:
            return point
        }
    }
    
    private func reverseOrientation(_ point: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
        switch orientation {
        case .right:
            return CGPoint(x: 1 - point.y, y: point.x)
        case .left:
            return CGPoint(x: point.y, y: 1 - point.x)
        case .down:
            return CGPoint(x: 1 - point.x, y: 1 - point.y)
        default:
            return point
        }
    }
}

