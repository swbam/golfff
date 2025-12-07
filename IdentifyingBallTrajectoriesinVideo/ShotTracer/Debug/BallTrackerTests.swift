import Foundation
import AVFoundation
import Photos
import UIKit

/// Automated tests for the ball tracking system
/// Run these to verify the shot tracer actually works!

#if DEBUG

final class BallTrackerTests {
    
    static let shared = BallTrackerTests()
    
    // Test results
    var testResults: [String: TestResult] = [:]
    
    struct TestResult {
        let name: String
        let passed: Bool
        let message: String
        let duration: TimeInterval
    }
    
    // MARK: - Run All Tests
    
    func runAllTests(completion: @escaping ([TestResult]) -> Void) {
        print("═══════════════════════════════════════════════════════")
        print("🧪 RUNNING BALL TRACKER TESTS")
        print("═══════════════════════════════════════════════════════")
        
        var results: [TestResult] = []
        let group = DispatchGroup()
        
        // Test 1: High Frame Rate Tracker Initialization
        results.append(testTrackerInitialization())
        
        // Test 2: Ball Position Setting
        results.append(testBallPositionSetting())
        
        // Test 3: White Pixel Detection (synthetic)
        results.append(testWhitePixelDetection())
        
        // Test 4: Trajectory Building
        results.append(testTrajectoryBuilding())
        
        // Test 5: Video Processing (async)
        group.enter()
        testVideoProcessing { result in
            results.append(result)
            group.leave()
        }
        
        group.notify(queue: .main) {
            self.printTestSummary(results)
            completion(results)
        }
    }
    
    // MARK: - Individual Tests
    
    func testTrackerInitialization() -> TestResult {
        let start = Date()
        let tracker = HighFrameRateBallTracker()
        
        // Verify defaults
        let hasCorrectFrameRate = tracker.frameRate == 240
        let duration = Date().timeIntervalSince(start)
        
        if hasCorrectFrameRate {
            return TestResult(
                name: "Tracker Initialization",
                passed: true,
                message: "Tracker initialized with correct defaults",
                duration: duration
            )
        } else {
            return TestResult(
                name: "Tracker Initialization",
                passed: false,
                message: "Frame rate should be 240, got \(tracker.frameRate)",
                duration: duration
            )
        }
    }
    
    func testBallPositionSetting() -> TestResult {
        let start = Date()
        let tracker = HighFrameRateBallTracker()
        
        // Set position like silhouette would
        let testPosition = CGPoint(x: 0.42, y: 0.92)  // Typical ball position
        tracker.setInitialBallPosition(testPosition)
        
        // Start tracking
        tracker.startTracking()
        
        // Build initial trajectory
        let trajectory = tracker.buildTrajectory()
        let duration = Date().timeIntervalSince(start)
        
        if let traj = trajectory, traj.points.count >= 1 {
            let firstPoint = traj.points[0]
            let positionMatch = abs(firstPoint.normalized.x - testPosition.x) < 0.01 &&
                               abs(firstPoint.normalized.y - testPosition.y) < 0.01
            
            if positionMatch {
                return TestResult(
                    name: "Ball Position Setting",
                    passed: true,
                    message: "Initial position correctly set at (\(String(format: "%.2f", testPosition.x)), \(String(format: "%.2f", testPosition.y)))",
                    duration: duration
                )
            }
        }
        
        return TestResult(
            name: "Ball Position Setting",
            passed: false,
            message: "Failed to set initial ball position from silhouette",
            duration: duration
        )
    }
    
    func testWhitePixelDetection() -> TestResult {
        let start = Date()
        
        // Create a synthetic pixel buffer with a white blob
        guard let pixelBuffer = createTestPixelBuffer(withWhiteBallAt: CGPoint(x: 0.5, y: 0.5)) else {
            return TestResult(
                name: "White Pixel Detection",
                passed: false,
                message: "Could not create test pixel buffer",
                duration: Date().timeIntervalSince(start)
            )
        }
        
        let tracker = HighFrameRateBallTracker()
        tracker.debugLogging = true
        
        // Set initial position near the white blob
        tracker.setInitialBallPosition(CGPoint(x: 0.45, y: 0.45))
        tracker.startTracking()
        
        // Process frame
        let result = tracker.processFrame(pixelBuffer, timestamp: .zero, orientation: .up)
        let duration = Date().timeIntervalSince(start)
        
        if result.isTracking && result.currentPosition != nil {
            let pos = result.currentPosition!
            // Check if detected position is close to where we put the ball
            if abs(pos.x - 0.5) < 0.15 && abs(pos.y - 0.5) < 0.15 {
                return TestResult(
                    name: "White Pixel Detection",
                    passed: true,
                    message: "Successfully detected white ball at (\(String(format: "%.2f", pos.x)), \(String(format: "%.2f", pos.y)))",
                    duration: duration
                )
            }
        }
        
        return TestResult(
            name: "White Pixel Detection", 
            passed: false,
            message: "Failed to detect white ball in synthetic image",
            duration: duration
        )
    }
    
    func testTrajectoryBuilding() -> TestResult {
        let start = Date()
        let tracker = HighFrameRateBallTracker()
        
        // Simulate a realistic golf ball trajectory
        tracker.setInitialBallPosition(CGPoint(x: 0.5, y: 0.9))
        tracker.startTracking()
        
        // Create synthetic frames with ball moving in parabolic arc
        let trajectoryPoints: [CGPoint] = [
            CGPoint(x: 0.50, y: 0.90),
            CGPoint(x: 0.52, y: 0.80),
            CGPoint(x: 0.54, y: 0.70),
            CGPoint(x: 0.56, y: 0.62),
            CGPoint(x: 0.58, y: 0.56),
            CGPoint(x: 0.60, y: 0.52),
            CGPoint(x: 0.62, y: 0.50),  // Apex
            CGPoint(x: 0.64, y: 0.52),
            CGPoint(x: 0.66, y: 0.56),
            CGPoint(x: 0.68, y: 0.62)
        ]
        
        for (index, point) in trajectoryPoints.enumerated() {
            if let buffer = createTestPixelBuffer(withWhiteBallAt: point) {
                let time = CMTime(seconds: Double(index) * 0.033, preferredTimescale: 600)
                _ = tracker.processFrame(buffer, timestamp: time, orientation: .up)
            }
        }
        
        tracker.stopTracking()
        
        let trajectory = tracker.buildTrajectory()
        let duration = Date().timeIntervalSince(start)
        
        if let traj = trajectory, traj.points.count >= 5 {
            return TestResult(
                name: "Trajectory Building",
                passed: true,
                message: "Built trajectory with \(traj.points.count) points",
                duration: duration
            )
        }
        
        return TestResult(
            name: "Trajectory Building",
            passed: false,
            message: "Failed to build trajectory (got \(trajectory?.points.count ?? 0) points)",
            duration: duration
        )
    }
    
    func testVideoProcessing(completion: @escaping (TestResult) -> Void) {
        let start = Date()
        
        // Get first video from Photos library
        TestVideoProcessor.loadFirstVideoFromLibrary { asset in
            guard let asset = asset else {
                completion(TestResult(
                    name: "Video Processing",
                    passed: false,
                    message: "No video found in Photos library - add one first!",
                    duration: Date().timeIntervalSince(start)
                ))
                return
            }
            
            // Process the video
            let processor = TestVideoProcessor()
            processor.debugLogging = true
            
            // Use typical ball position
            let ballPosition = CGPoint(x: 0.5, y: 0.85)
            
            var framesProcessed = 0
            
            // Keep strong reference to delegate
            let delegate = TestProcessorDelegate(
                onFrame: { _, _ in framesProcessed += 1 },
                onTrajectory: { _ in /* trajectory updated */ },
                onComplete: { trajectory, _ in
                    let duration = Date().timeIntervalSince(start)
                    
                    let message: String
                    let passed: Bool
                    
                    if framesProcessed > 0 {
                        passed = true
                        if let traj = trajectory {
                            message = "Processed \(framesProcessed) frames, trajectory: \(traj.points.count) points"
                        } else {
                            message = "Processed \(framesProcessed) frames (no ball detected - expected for non-golf video)"
                        }
                    } else {
                        passed = false
                        message = "Failed to process any frames"
                    }
                    
                    completion(TestResult(
                        name: "Video Processing",
                        passed: passed,
                        message: message,
                        duration: duration
                    ))
                },
                onError: { error in
                    completion(TestResult(
                        name: "Video Processing",
                        passed: false,
                        message: "Error: \(error.localizedDescription)",
                        duration: Date().timeIntervalSince(start)
                    ))
                }
            )
            
            processor.delegate = delegate
            processor.processVideo(asset, initialBallPosition: ballPosition)
            
            // Keep delegate alive during processing
            _ = delegate
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestPixelBuffer(withWhiteBallAt position: CGPoint) -> CVPixelBuffer? {
        let width = 640
        let height = 480
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let data = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Fill with dark background
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                data[offset] = 30      // B
                data[offset + 1] = 50  // G
                data[offset + 2] = 30  // R
                data[offset + 3] = 255 // A
            }
        }
        
        // Draw white ball at specified position
        let ballCenterX = Int(position.x * CGFloat(width))
        let ballCenterY = Int(position.y * CGFloat(height))
        let ballRadius = 15
        
        for y in (ballCenterY - ballRadius)...(ballCenterY + ballRadius) {
            for x in (ballCenterX - ballRadius)...(ballCenterX + ballRadius) {
                guard x >= 0 && x < width && y >= 0 && y < height else { continue }
                
                let dx = x - ballCenterX
                let dy = y - ballCenterY
                let distance = sqrt(Double(dx * dx + dy * dy))
                
                if distance <= Double(ballRadius) {
                    let offset = y * bytesPerRow + x * 4
                    data[offset] = 255     // B - White
                    data[offset + 1] = 255 // G
                    data[offset + 2] = 255 // R
                    data[offset + 3] = 255 // A
                }
            }
        }
        
        return buffer
    }
    
    private func printTestSummary(_ results: [TestResult]) {
        print("\n═══════════════════════════════════════════════════════")
        print("📊 TEST SUMMARY")
        print("═══════════════════════════════════════════════════════\n")
        
        let passed = results.filter { $0.passed }.count
        let failed = results.filter { !$0.passed }.count
        
        for result in results {
            let icon = result.passed ? "✅" : "❌"
            print("\(icon) \(result.name)")
            print("   \(result.message)")
            print("   Duration: \(String(format: "%.3f", result.duration))s\n")
        }
        
        print("═══════════════════════════════════════════════════════")
        print("PASSED: \(passed)  FAILED: \(failed)")
        print("═══════════════════════════════════════════════════════\n")
    }
}

// MARK: - Test Delegate

private class TestProcessorDelegate: TestVideoProcessorDelegate {
    let onFrame: (Int, Int) -> Void
    let onTrajectory: (Trajectory) -> Void
    let onComplete: (Trajectory?, URL) -> Void
    let onError: (Error) -> Void
    
    init(onFrame: @escaping (Int, Int) -> Void,
         onTrajectory: @escaping (Trajectory) -> Void,
         onComplete: @escaping (Trajectory?, URL) -> Void,
         onError: @escaping (Error) -> Void) {
        self.onFrame = onFrame
        self.onTrajectory = onTrajectory
        self.onComplete = onComplete
        self.onError = onError
    }
    
    func testProcessor(_ processor: TestVideoProcessor, didStartProcessing asset: AVAsset) {}
    
    func testProcessor(_ processor: TestVideoProcessor, didProcessFrame frameNumber: Int, total: Int) {
        onFrame(frameNumber, total)
    }
    
    func testProcessor(_ processor: TestVideoProcessor, didDetectBall at: CGPoint, confidence: Float) {}
    
    func testProcessor(_ processor: TestVideoProcessor, didUpdateTrajectory trajectory: Trajectory) {
        onTrajectory(trajectory)
    }
    
    func testProcessor(_ processor: TestVideoProcessor, didFinishWithTrajectory trajectory: Trajectory?, videoURL: URL) {
        onComplete(trajectory, videoURL)
    }
    
    func testProcessor(_ processor: TestVideoProcessor, didFail error: Error) {
        onError(error)
    }
}

#endif


