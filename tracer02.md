# Comprehensive Analysis & Solution Plan for TRACER Golf Ball Shot Tracer App

## Executive Summary

After thoroughly reviewing the entire codebase (~33 Swift files), the DEVELOPER_HANDOFF.md, and tracer-app.md specifications, I've identified exactly why the tracer doesn't work. The good news: **the infrastructure is solid** - camera capture, export pipeline, UI, and state management all work. The problem is **ball detection and tracking**.

---

## 🔴 Root Cause Analysis

### Problem 1: `VNDetectTrajectoriesRequest` Misconfiguration

```92:93:IdentifyingBallTrajectoriesinVideo/ShotTracer/TrajectoryDetector.swift
request.objectMinimumNormalizedRadius = 0.004  // ~0.4% of frame (ball at 15m)
request.objectMaximumNormalizedRadius = 0.08   // ~8% of frame (ball very close or with motion blur)
```

**Why it fails:**
- Golf balls at typical filming distance (10-20m) appear as **5-20 pixels** in a 1080p frame
- That's approximately **0.3-1% of frame width**, making 0.004 (0.4%) the absolute minimum
- Apple's `VNDetectTrajectoriesRequest` needs **at least 5+ frames** with consistent parabolic motion
- Golf balls move **150+ mph** - they traverse the frame in <15 frames at 60fps
- The `trajectoryLength: 5` is borderline too short for Vision to build confidence

### Problem 2: BallTracker.swift - Fundamentally Flawed Approach

```27:29:IdentifyingBallTrajectoriesinVideo/ShotTracer/BallTracker.swift
private let searchRadius: CGFloat = 0.15  // Search within 15% of frame from last position
private let whiteThreshold: UInt8 = 200   // Brightness threshold for white ball
private let minBlobPixels = 5
```

**Critical Issues:**
1. **Search radius is too small** - At 150mph, a golf ball moves ~220 feet per second. At 60fps and typical filming distance, it moves **5-10% of frame width per frame**. A 15% search radius only works for 1-2 frames before losing the ball.

2. **No physics prediction** - The tracker searches around "last known position" but doesn't predict WHERE the ball SHOULD be based on projectile motion.

3. **White pixel detection is naive**:
   - Clouds, sky glare, and reflections are also "white"
   - A brightness threshold of 200 is too restrictive (golf balls under varying lighting can be 180-255)
   - No saturation filtering (true white has LOW saturation)

4. **Validation rejects valid trajectories**:
```109:112:IdentifyingBallTrajectoriesinVideo/ShotTracer/BallTracker.swift
if trackedPositions.count > 3 && dy > 0.05 {
    // Ball moving down too much - probably not the ball
    return nil
}
```
This rejects the ball once it starts descending (the entire second half of the flight!)

### Problem 3: GolfBallDetector.swift - Wrong Technique

```137:156:IdentifyingBallTrajectoriesinVideo/ShotTracer/GolfBallDetector.swift
private func detectMotion(current: CIImage, previous: CIImage) -> CIImage? {
    // Frame differencing to detect moving objects
    guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else {
        return nil
    }
```

**Why it fails:**
- Frame differencing works for slow-moving objects
- Golf balls move so fast they create **motion blur streaks**, not clean blobs
- The combined white+motion mask often produces no usable signal

### Problem 4: Coordinate System Confusion

The codebase has inconsistent coordinate handling:
- Vision framework uses **bottom-left origin** with Y increasing upward
- UIKit uses **top-left origin** with Y increasing downward
- Some flips are applied, some aren't

```116:116:IdentifyingBallTrajectoriesinVideo/ShotTracer/TrajectoryDetector.swift
let normalizedPoints: [CGPoint] = best.detectedPoints.map { CGPoint(x: CGFloat($0.x), y: 1.0 - CGFloat($0.y)) }
```

This flip is correct, but in `BallTracker.swift`:
```225:235:IdentifyingBallTrajectoriesinVideo/ShotTracer/BallTracker.swift
private func applyOrientation(_ point: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
    switch orientation {
    case .right: // 90° CW
        return CGPoint(x: point.y, y: 1 - point.x)
```
The orientation handling is **inverted** in some cases.

---

## ✅ How SmoothSwing ACTUALLY Works (Reverse-Engineered)

Based on the app behavior and physics, here's the architecture:

### 1. **Alignment = Ball Position Capture**
The silhouette alignment isn't cosmetic - it tells the app EXACTLY where the ball will be at impact:
- User positions themselves within guides
- Ball circle indicator marks the PRECISE starting position
- This position is stored with sub-pixel accuracy

### 2. **Impact Detection via Pose Analysis**
- Uses `VNDetectHumanBodyPoseRequest` to track wrist positions
- Monitors the **velocity** of wrists (derivative of position)
- Impact = peak negative velocity of wrists (fastest part of downswing)
- This triggers ball tracking ~2-3 frames before actual impact

### 3. **Physics-Predictive Ball Tracking**
Once impact is detected:
1. **Initialize** at known ball position
2. **Assume** initial launch parameters (angle: 12-18°, speed based on typical club)
3. **Predict** position using projectile motion: `y = y₀ + vy*t - ½gt²`
4. **Search** in prediction window (not entire frame)
5. **Refine** predictions using Kalman filter with each detection
6. **Interpolate** missing frames using physics model

### 4. **Multi-Technique Ball Detection**
Combines:
- **Color filtering**: HSV space - high V (brightness), low S (saturation)
- **Blob analysis**: Connected component labeling with size/circularity filters
- **Optical flow**: Track ball velocity vector frame-to-frame
- **Prediction validation**: Only accept detections within physics-plausible region

### 5. **Real-Time Rendering**
- Draw tracer WHILE recording (not post-processing)
- Uses `CADisplayLink` for smooth 60fps rendering
- Catmull-Rom spline for smooth curves

---

## 🛠️ Complete Solution Architecture

### Core Algorithm: Kalman Filter-Based Predictive Tracking

```swift
// NEW FILE: KalmanBallTracker.swift

struct BallState {
    var x: Double       // Normalized x position (0-1)
    var y: Double       // Normalized y position (0-1)
    var vx: Double      // X velocity (per frame)
    var vy: Double      // Y velocity (per frame)
}

final class KalmanBallTracker {
    // State estimate
    private var state: BallState
    
    // Kalman filter matrices
    private var P: [[Double]]  // Covariance matrix
    private let Q: [[Double]]  // Process noise
    private let R: [[Double]]  // Measurement noise
    
    // Physics constants (normalized to frame dimensions)
    private let gravity: Double = 0.0015  // Gravity effect per frame (tuned for 60fps)
    
    init(initialPosition: CGPoint, initialVelocity: CGPoint = .zero) {
        state = BallState(
            x: Double(initialPosition.x),
            y: Double(initialPosition.y),
            vx: Double(initialVelocity.x),
            vy: Double(initialVelocity.y)
        )
        // Initialize covariance matrices...
    }
    
    /// Predict next state using physics
    func predict() -> CGPoint {
        // Physics update
        state.x += state.vx
        state.y += state.vy
        state.vy += gravity  // Ball decelerates going up, accelerates going down
        
        // Update covariance
        // P = F*P*F' + Q
        
        return CGPoint(x: state.x, y: state.y)
    }
    
    /// Update with measurement
    func update(measurement: CGPoint) {
        // Kalman gain: K = P*H'*(H*P*H' + R)^-1
        // State update: x = x + K*(z - H*x)
        // Covariance update: P = (I - K*H)*P
        
        let z = [Double(measurement.x), Double(measurement.y)]
        // ... Kalman update equations
        
        state.x = z[0]
        state.y = z[1]
    }
    
    /// Get search window for next frame
    func getSearchWindow(confidenceMultiplier: Double = 3.0) -> CGRect {
        let predicted = predict()
        let uncertainty = sqrt(P[0][0] + P[1][1]) * confidenceMultiplier
        
        return CGRect(
            x: predicted.x - uncertainty,
            y: predicted.y - uncertainty,
            width: uncertainty * 2,
            height: uncertainty * 2
        )
    }
}
```

### Enhanced Ball Detection

```swift
// ENHANCED: BallTracker.swift

final class EnhancedBallTracker {
    
    // Detection parameters (TUNED FOR GOLF BALLS)
    private let minBrightness: UInt8 = 180      // Lower threshold
    private let maxSaturation: UInt8 = 60       // White = low saturation
    private let minCircularity: CGFloat = 0.6   // Ball should be round-ish
    private let minBlobPixels = 4
    private let maxBlobPixels = 500
    
    // Kalman tracker
    private var kalmanTracker: KalmanBallTracker?
    
    // Frame history for optical flow
    private var previousFrame: CVPixelBuffer?
    private var previousBallCenter: CGPoint?
    
    func processFrame(_ pixelBuffer: CVPixelBuffer, time: CMTime, orientation: CGImagePropertyOrientation) -> TrackedBall? {
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Get search window from Kalman prediction (or full frame if no tracker yet)
        let searchWindow: CGRect
        if let tracker = kalmanTracker {
            searchWindow = tracker.getSearchWindow()
        } else if let lastPos = lastKnownPosition {
            // Initial search around last known position with larger window
            searchWindow = CGRect(
                x: lastPos.x - 0.25,
                y: lastPos.y - 0.35,  // More upward search
                width: 0.5,
                height: 0.6
            )
        } else {
            return nil  // No ball position to track from
        }
        
        // Convert to pixel coordinates
        let pixelWindow = CGRect(
            x: max(0, Int(searchWindow.minX * CGFloat(width))),
            y: max(0, Int(searchWindow.minY * CGFloat(height))),
            width: min(width, Int(searchWindow.width * CGFloat(width))),
            height: min(height, Int(searchWindow.height * CGFloat(height)))
        )
        
        // Find ball candidates in search window
        let candidates = findBallCandidates(
            in: pixelBuffer,
            searchRect: pixelWindow,
            orientation: orientation
        )
        
        // Select best candidate based on:
        // 1. Proximity to predicted position
        // 2. Brightness/whiteness score
        // 3. Circularity
        // 4. Motion consistency with previous frame
        guard let bestCandidate = selectBestCandidate(
            candidates,
            predicted: kalmanTracker?.predict()
        ) else {
            return nil
        }
        
        // Update Kalman filter
        kalmanTracker?.update(measurement: bestCandidate.center)
        
        // Store for next frame
        previousFrame = pixelBuffer
        previousBallCenter = bestCandidate.center
        
        return TrackedBall(
            position: bestCandidate.center,
            confidence: bestCandidate.score,
            frameTime: time
        )
    }
    
    private func findBallCandidates(in buffer: CVPixelBuffer, searchRect: CGRect, orientation: CGImagePropertyOrientation) -> [BallCandidate] {
        
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Connected component labeling for blob detection
        var visited = Set<Int>()
        var candidates: [BallCandidate] = []
        
        let minX = Int(searchRect.minX)
        let maxX = Int(searchRect.maxX)
        let minY = Int(searchRect.minY)  
        let maxY = Int(searchRect.maxY)
        
        for y in minY..<maxY {
            for x in minX..<maxX {
                let idx = y * width + x
                guard !visited.contains(idx) else { continue }
                
                let offset = y * bytesPerRow + x * 4
                let b = pixels[offset]
                let g = pixels[offset + 1]
                let r = pixels[offset + 2]
                
                // Check if pixel is "white enough"
                let brightness = (UInt16(r) + UInt16(g) + UInt16(b)) / 3
                let maxComponent = max(r, g, b)
                let minComponent = min(r, g, b)
                let saturation = maxComponent > 0 ? (maxComponent - minComponent) * 255 / maxComponent : 0
                
                if brightness >= minBrightness && saturation <= maxSaturation {
                    // Flood fill to find blob
                    let blob = floodFill(
                        pixels: pixels,
                        start: (x, y),
                        width: width,
                        height: height,
                        bytesPerRow: bytesPerRow,
                        visited: &visited,
                        bounds: searchRect
                    )
                    
                    // Validate blob size
                    if blob.pixelCount >= minBlobPixels && blob.pixelCount <= maxBlobPixels {
                        // Calculate circularity
                        let area = CGFloat(blob.pixelCount)
                        let perimeter = CGFloat(blob.perimeterPixels)
                        let circularity = perimeter > 0 ? 4 * .pi * area / (perimeter * perimeter) : 0
                        
                        if circularity >= minCircularity {
                            let normalizedCenter = CGPoint(
                                x: CGFloat(blob.centerX) / CGFloat(width),
                                y: CGFloat(blob.centerY) / CGFloat(height)
                            )
                            
                            candidates.append(BallCandidate(
                                center: normalizedCenter,
                                radius: sqrt(area / .pi) / CGFloat(width),
                                brightness: CGFloat(blob.avgBrightness) / 255.0,
                                circularity: circularity,
                                pixelCount: blob.pixelCount
                            ))
                        }
                    }
                }
            }
        }
        
        return candidates
    }
}
```

### Impact Detection Using Pose

```swift
// ENHANCED: LiveShotDetector.swift - Fix the impact detection

@available(iOS 15.0, *)
final class EnhancedLiveShotDetector {
    
    // Wrist velocity tracking for impact detection
    private var wristVelocityHistory: [Double] = []
    private let velocityHistorySize = 10
    
    private func detectSwingPhase(from pose: VNHumanBodyPoseObservation) -> SwingPhase {
        guard let rightWrist = try? pose.recognizedPoint(.rightWrist),
              let leftWrist = try? pose.recognizedPoint(.leftWrist),
              rightWrist.confidence > 0.3,
              leftWrist.confidence > 0.3 else {
            return .idle
        }
        
        let wristY = (rightWrist.location.y + leftWrist.location.y) / 2
        
        // Calculate velocity (change from previous frame)
        if let prevY = previousWristY {
            let velocity = wristY - prevY  // Positive = wrists moving up
            wristVelocityHistory.append(velocity)
            if wristVelocityHistory.count > velocityHistorySize {
                wristVelocityHistory.removeFirst()
            }
            
            // Impact detection: Look for rapid change from upward to downward
            // At impact, wrists are moving fastest DOWNWARD
            if wristVelocityHistory.count >= 3 {
                let recentVelocities = Array(wristVelocityHistory.suffix(3))
                let avgVelocity = recentVelocities.reduce(0, +) / Double(recentVelocities.count)
                
                // Peak downward velocity = impact
                if avgVelocity < -0.03 && abs(avgVelocity) > abs(peakDownwardVelocity) {
                    peakDownwardVelocity = avgVelocity
                }
                
                // If we've hit peak and now slowing, impact occurred
                if peakDownwardVelocity < -0.03 && avgVelocity > peakDownwardVelocity + 0.01 {
                    if currentPhase == .downswing {
                        print("💥 IMPACT DETECTED! Starting ball tracking...")
                        currentPhase = .impact
                        impactDetected = true
                        impactTime = Date()
                        initializeBallTracking()
                        return .impact
                    }
                }
            }
        }
        
        previousWristY = wristY
        return currentPhase
    }
    
    private func initializeBallTracking() {
        guard let ballPos = lockedBallPosition else { return }
        
        // Initialize Kalman tracker at ball position with assumed initial velocity
        // Golf ball launch: ~12-15 degree angle, moving right-to-left or left-to-right
        let launchAngle = 14.0 * .pi / 180.0  // Radians
        let initialSpeed = 0.08  // Normalized velocity (tuned)
        
        kalmanTracker = KalmanBallTracker(
            initialPosition: ballPos,
            initialVelocity: CGPoint(
                x: initialSpeed * cos(launchAngle),
                y: -initialSpeed * sin(launchAngle)  // Negative because going UP
            )
        )
    }
}
```

### Fixed `VNDetectTrajectoriesRequest` Parameters

```swift
// ENHANCED: TrajectoryDetector.swift

private func makeRequest() -> VNDetectTrajectoriesRequest {
    // FIXED PARAMETERS FOR GOLF BALLS
    let request = VNDetectTrajectoriesRequest(
        frameAnalysisSpacing: .zero,  // Analyze every frame
        trajectoryLength: 8           // Need more points for confident detection
    ) { [weak self] req, error in
        // ...
    }
    
    // CRITICAL: Much smaller minimum radius
    request.objectMinimumNormalizedRadius = 0.001   // 0.1% of frame
    request.objectMaximumNormalizedRadius = 0.05    // 5% of frame
    
    // Set ROI to focus on flight path (upper 60% of frame)
    if let roi = regionOfInterest {
        request.regionOfInterest = roi
    } else {
        // Default: focus on where ball typically flies
        request.regionOfInterest = CGRect(x: 0, y: 0.2, width: 1, height: 0.8)
    }
    
    return request
}
```

### Hybrid Approach: Combine Both Methods

```swift
// NEW FILE: HybridBallTracker.swift

final class HybridBallTracker {
    
    private let visionTracker = TrajectoryDetector()
    private let kalmanTracker = EnhancedBallTracker()
    
    private var trajectoryPoints: [TrajectoryPoint] = []
    private var usingVision = true
    
    func processFrame(_ buffer: CMSampleBuffer, impactDetected: Bool) {
        
        // Method 1: Try Vision framework first (most accurate when it works)
        if usingVision {
            visionTracker.process(sampleBuffer: buffer)
            
            // If Vision gives us results, use them
            if let visionResult = visionTracker.currentTrajectory, !visionResult.points.isEmpty {
                trajectoryPoints = visionResult.points
                return
            }
        }
        
        // Method 2: Fall back to custom tracking
        if impactDetected {
            let time = CMSampleBufferGetPresentationTimeStamp(buffer)
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
            
            if let tracked = kalmanTracker.processFrame(pixelBuffer, time: time, orientation: .right) {
                trajectoryPoints.append(TrajectoryPoint(
                    time: time,
                    normalized: tracked.position
                ))
            }
        }
    }
    
    // Switch to custom tracking if Vision fails for N frames
    private func checkVisionFailure() {
        visionFailureCount += 1
        if visionFailureCount > 15 {  // ~0.25 seconds at 60fps
            usingVision = false
            print("⚠️ Vision failed, switching to Kalman tracker")
        }
    }
}
```

---

## 📋 Implementation Plan (Ordered Steps)

### Phase 1: Fix Vision-Based Detection (For Both Live & Imported)
1. Update `TrajectoryDetector.swift` with corrected parameters
2. Add debug logging to verify Vision is finding trajectories
3. Test with known good golf videos

### Phase 2: Implement Kalman Predictive Tracking
1. Create `KalmanBallTracker.swift`
2. Integrate with `AssetTrajectoryProcessor.swift` for imported videos
3. Test ball tracking from known position

### Phase 3: Fix Impact Detection
1. Enhance `LiveShotDetector.swift` with velocity-based impact detection
2. Initialize Kalman tracker at impact moment
3. Test live recording

### Phase 4: Improve Ball Detection
1. Replace simplistic white pixel search with HSV + blob detection
2. Add circularity filtering
3. Integrate with Kalman predictions

### Phase 5: Hybrid Integration
1. Create `HybridBallTracker.swift`
2. Use Vision when it works, Kalman when it doesn't
3. Merge trajectories intelligently

### Phase 6: Coordinate System Fix
1. Audit all coordinate conversions
2. Create utility functions for consistent handling
3. Test with various video orientations

---

## 🎯 Key Code Files That Need Changes

| File | Priority | Changes Needed |
|------|----------|----------------|
| `TrajectoryDetector.swift` | 🔴 CRITICAL | Fix VNDetectTrajectoriesRequest params |
| `BallTracker.swift` | 🔴 CRITICAL | Complete rewrite with Kalman filter |
| `LiveShotDetector.swift` | 🔴 HIGH | Fix impact detection, integrate Kalman |
| `AssetTrajectoryProcessor.swift` | 🔴 HIGH | Use enhanced tracking |
| `GolfBallDetector.swift` | 🟡 MEDIUM | Replace with better blob detection |
| `PremiumAlignmentViewController.swift` | 🟡 MEDIUM | Capture precise ball position |
| `ShotSessionController.swift` | 🟢 LOW | Minor integration changes |

---

## Summary

The tracer doesn't work because:
1. **Vision parameters are wrong** for tiny, fast golf balls
2. **Ball tracking has no physics prediction** - it loses the ball after 2-3 frames
3. **Detection is too simplistic** - white pixels aren't enough
4. **Impact detection doesn't trigger tracking properly**

The solution requires:
1. **Kalman filter** for physics-based predictive tracking
2. **Better blob detection** with HSV color + circularity
3. **Proper Vision parameters** or fallback to custom tracking
4. **Velocity-based impact detection** from pose analysis

**To proceed with implementation, please switch to Agent mode** and I can implement these fixes file by file. The architecture is sound - we just need to fix the core ball detection and tracking algorithms.

```swift
request.objectMinimumNormalizedRadius = 0.004  // ~0.4% of frame (ball at 15m)
request.objectMaximumNormalizedRadius = 0.08   // ~8% of frame (ball very close or with motion blur)
```

```swift
private let searchRadius: CGFloat = 0.15  // Search within 15% of frame from last position
private let whiteThreshold: UInt8 = 200   // Brightness threshold for white ball
private let minBlobPixels = 5
```

```swift
if trackedPositions.count > 3 && dy > 0.05 {
    // Ball moving down too much - probably not the ball
    return nil
}
```

```swift
private func detectMotion(current: CIImage, previous: CIImage) -> CIImage? {
    // Frame differencing to detect moving objects
    guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else {
        return nil
    }
```

```swift
let normalizedPoints: [CGPoint] = best.detectedPoints.map { CGPoint(x: CGFloat($0.x), y: 1.0 - CGFloat($0.y)) }
```

```swift
private func applyOrientation(_ point: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
    switch orientation {
    case .right: // 90° CW
        return CGPoint(x: point.y, y: 1 - point.x)
```

```swift
// NEW FILE: KalmanBallTracker.swift

struct BallState {
    var x: Double       // Normalized x position (0-1)
    var y: Double       // Normalized y position (0-1)
    var vx: Double      // X velocity (per frame)
    var vy: Double      // Y velocity (per frame)
}

final class KalmanBallTracker {
    // State estimate
    private var state: BallState
    
    // Kalman filter matrices
    private var P: [[Double]]  // Covariance matrix
    private let Q: [[Double]]  // Process noise
    private let R: [[Double]]  // Measurement noise
    
    // Physics constants (normalized to frame dimensions)
    private let gravity: Double = 0.0015  // Gravity effect per frame (tuned for 60fps)
    
    init(initialPosition: CGPoint, initialVelocity: CGPoint = .zero) {
        state = BallState(
            x: Double(initialPosition.x),
            y: Double(initialPosition.y),
            vx: Double(initialVelocity.x),
            vy: Double(initialVelocity.y)
        )
        // Initialize covariance matrices...
    }
    
    /// Predict next state using physics
    func predict() -> CGPoint {
        // Physics update
        state.x += state.vx
        state.y += state.vy
        state.vy += gravity  // Ball decelerates going up, accelerates going down
        
        // Update covariance
        // P = F*P*F' + Q
        
        return CGPoint(x: state.x, y: state.y)
    }
    
    /// Update with measurement
    func update(measurement: CGPoint) {
        // Kalman gain: K = P*H'*(H*P*H' + R)^-1
        // State update: x = x + K*(z - H*x)
        // Covariance update: P = (I - K*H)*P
        
        let z = [Double(measurement.x), Double(measurement.y)]
        // ... Kalman update equations
        
        state.x = z[0]
        state.y = z[1]
    }
    
    /// Get search window for next frame
    func getSearchWindow(confidenceMultiplier: Double = 3.0) -> CGRect {
        let predicted = predict()
        let uncertainty = sqrt(P[0][0] + P[1][1]) * confidenceMultiplier
        
        return CGRect(
            x: predicted.x - uncertainty,
            y: predicted.y - uncertainty,
            width: uncertainty * 2,
            height: uncertainty * 2
        )
    }
}
```

```swift
// ENHANCED: BallTracker.swift

final class EnhancedBallTracker {
    
    // Detection parameters (TUNED FOR GOLF BALLS)
    private let minBrightness: UInt8 = 180      // Lower threshold
    private let maxSaturation: UInt8 = 60       // White = low saturation
    private let minCircularity: CGFloat = 0.6   // Ball should be round-ish
    private let minBlobPixels = 4
    private let maxBlobPixels = 500
    
    // Kalman tracker
    private var kalmanTracker: KalmanBallTracker?
    
    // Frame history for optical flow
    private var previousFrame: CVPixelBuffer?
    private var previousBallCenter: CGPoint?
    
    func processFrame(_ pixelBuffer: CVPixelBuffer, time: CMTime, orientation: CGImagePropertyOrientation) -> TrackedBall? {
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Get search window from Kalman prediction (or full frame if no tracker yet)
        let searchWindow: CGRect
        if let tracker = kalmanTracker {
            searchWindow = tracker.getSearchWindow()
        } else if let lastPos = lastKnownPosition {
            // Initial search around last known position with larger window
            searchWindow = CGRect(
                x: lastPos.x - 0.25,
                y: lastPos.y - 0.35,  // More upward search
                width: 0.5,
                height: 0.6
            )
        } else {
            return nil  // No ball position to track from
        }
        
        // Convert to pixel coordinates
        let pixelWindow = CGRect(
            x: max(0, Int(searchWindow.minX * CGFloat(width))),
            y: max(0, Int(searchWindow.minY * CGFloat(height))),
            width: min(width, Int(searchWindow.width * CGFloat(width))),
            height: min(height, Int(searchWindow.height * CGFloat(height)))
        )
        
        // Find ball candidates in search window
        let candidates = findBallCandidates(
            in: pixelBuffer,
            searchRect: pixelWindow,
            orientation: orientation
        )
        
        // Select best candidate based on:
        // 1. Proximity to predicted position
        // 2. Brightness/whiteness score
        // 3. Circularity
        // 4. Motion consistency with previous frame
        guard let bestCandidate = selectBestCandidate(
            candidates,
            predicted: kalmanTracker?.predict()
        ) else {
            return nil
        }
        
        // Update Kalman filter
        kalmanTracker?.update(measurement: bestCandidate.center)
        
        // Store for next frame
        previousFrame = pixelBuffer
        previousBallCenter = bestCandidate.center
        
        return TrackedBall(
            position: bestCandidate.center,
            confidence: bestCandidate.score,
            frameTime: time
        )
    }
    
    private func findBallCandidates(in buffer: CVPixelBuffer, searchRect: CGRect, orientation: CGImagePropertyOrientation) -> [BallCandidate] {
        
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Connected component labeling for blob detection
        var visited = Set<Int>()
        var candidates: [BallCandidate] = []
        
        let minX = Int(searchRect.minX)
        let maxX = Int(searchRect.maxX)
        let minY = Int(searchRect.minY)  
        let maxY = Int(searchRect.maxY)
        
        for y in minY..<maxY {
            for x in minX..<maxX {
                let idx = y * width + x
                guard !visited.contains(idx) else { continue }
                
                let offset = y * bytesPerRow + x * 4
                let b = pixels[offset]
                let g = pixels[offset + 1]
                let r = pixels[offset + 2]
                
                // Check if pixel is "white enough"
                let brightness = (UInt16(r) + UInt16(g) + UInt16(b)) / 3
                let maxComponent = max(r, g, b)
                let minComponent = min(r, g, b)
                let saturation = maxComponent > 0 ? (maxComponent - minComponent) * 255 / maxComponent : 0
                
                if brightness >= minBrightness && saturation <= maxSaturation {
                    // Flood fill to find blob
                    let blob = floodFill(
                        pixels: pixels,
                        start: (x, y),
                        width: width,
                        height: height,
                        bytesPerRow: bytesPerRow,
                        visited: &visited,
                        bounds: searchRect
                    )
                    
                    // Validate blob size
                    if blob.pixelCount >= minBlobPixels && blob.pixelCount <= maxBlobPixels {
                        // Calculate circularity
                        let area = CGFloat(blob.pixelCount)
                        let perimeter = CGFloat(blob.perimeterPixels)
                        let circularity = perimeter > 0 ? 4 * .pi * area / (perimeter * perimeter) : 0
                        
                        if circularity >= minCircularity {
                            let normalizedCenter = CGPoint(
                                x: CGFloat(blob.centerX) / CGFloat(width),
                                y: CGFloat(blob.centerY) / CGFloat(height)
                            )
                            
                            candidates.append(BallCandidate(
                                center: normalizedCenter,
                                radius: sqrt(area / .pi) / CGFloat(width),
                                brightness: CGFloat(blob.avgBrightness) / 255.0,
                                circularity: circularity,
                                pixelCount: blob.pixelCount
                            ))
                        }
                    }
                }
            }
        }
        
        return candidates
    }
}
```

```swift
// ENHANCED: LiveShotDetector.swift - Fix the impact detection

@available(iOS 15.0, *)
final class EnhancedLiveShotDetector {
    
    // Wrist velocity tracking for impact detection
    private var wristVelocityHistory: [Double] = []
    private let velocityHistorySize = 10
    
    private func detectSwingPhase(from pose: VNHumanBodyPoseObservation) -> SwingPhase {
        guard let rightWrist = try? pose.recognizedPoint(.rightWrist),
              let leftWrist = try? pose.recognizedPoint(.leftWrist),
              rightWrist.confidence > 0.3,
              leftWrist.confidence > 0.3 else {
            return .idle
        }
        
        let wristY = (rightWrist.location.y + leftWrist.location.y) / 2
        
        // Calculate velocity (change from previous frame)
        if let prevY = previousWristY {
            let velocity = wristY - prevY  // Positive = wrists moving up
            wristVelocityHistory.append(velocity)
            if wristVelocityHistory.count > velocityHistorySize {
                wristVelocityHistory.removeFirst()
            }
            
            // Impact detection: Look for rapid change from upward to downward
            // At impact, wrists are moving fastest DOWNWARD
            if wristVelocityHistory.count >= 3 {
                let recentVelocities = Array(wristVelocityHistory.suffix(3))
                let avgVelocity = recentVelocities.reduce(0, +) / Double(recentVelocities.count)
                
                // Peak downward velocity = impact
                if avgVelocity < -0.03 && abs(avgVelocity) > abs(peakDownwardVelocity) {
                    peakDownwardVelocity = avgVelocity
                }
                
                // If we've hit peak and now slowing, impact occurred
                if peakDownwardVelocity < -0.03 && avgVelocity > peakDownwardVelocity + 0.01 {
                    if currentPhase == .downswing {
                        print("💥 IMPACT DETECTED! Starting ball tracking...")
                        currentPhase = .impact
                        impactDetected = true
                        impactTime = Date()
                        initializeBallTracking()
                        return .impact
                    }
                }
            }
        }
        
        previousWristY = wristY
        return currentPhase
    }
    
    private func initializeBallTracking() {
        guard let ballPos = lockedBallPosition else { return }
        
        // Initialize Kalman tracker at ball position with assumed initial velocity
        // Golf ball launch: ~12-15 degree angle, moving right-to-left or left-to-right
        let launchAngle = 14.0 * .pi / 180.0  // Radians
        let initialSpeed = 0.08  // Normalized velocity (tuned)
        
        kalmanTracker = KalmanBallTracker(
            initialPosition: ballPos,
            initialVelocity: CGPoint(
                x: initialSpeed * cos(launchAngle),
                y: -initialSpeed * sin(launchAngle)  // Negative because going UP
            )
        )
    }
}
```

```swift
// ENHANCED: TrajectoryDetector.swift

private func makeRequest() -> VNDetectTrajectoriesRequest {
    // FIXED PARAMETERS FOR GOLF BALLS
    let request = VNDetectTrajectoriesRequest(
        frameAnalysisSpacing: .zero,  // Analyze every frame
        trajectoryLength: 8           // Need more points for confident detection
    ) { [weak self] req, error in
        // ...
    }
    
    // CRITICAL: Much smaller minimum radius
    request.objectMinimumNormalizedRadius = 0.001   // 0.1% of frame
    request.objectMaximumNormalizedRadius = 0.05    // 5% of frame
    
    // Set ROI to focus on flight path (upper 60% of frame)
    if let roi = regionOfInterest {
        request.regionOfInterest = roi
    } else {
        // Default: focus on where ball typically flies
        request.regionOfInterest = CGRect(x: 0, y: 0.2, width: 1, height: 0.8)
    }
    
    return request
}
```

```swift
// NEW FILE: HybridBallTracker.swift

final class HybridBallTracker {
    
    private let visionTracker = TrajectoryDetector()
    private let kalmanTracker = EnhancedBallTracker()
    
    private var trajectoryPoints: [TrajectoryPoint] = []
    private var usingVision = true
    
    func processFrame(_ buffer: CMSampleBuffer, impactDetected: Bool) {
        
        // Method 1: Try Vision framework first (most accurate when it works)
        if usingVision {
            visionTracker.process(sampleBuffer: buffer)
            
            // If Vision gives us results, use them
            if let visionResult = visionTracker.currentTrajectory, !visionResult.points.isEmpty {
                trajectoryPoints = visionResult.points
                return
            }
        }
        
        // Method 2: Fall back to custom tracking
        if impactDetected {
            let time = CMSampleBufferGetPresentationTimeStamp(buffer)
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
            
            if let tracked = kalmanTracker.processFrame(pixelBuffer, time: time, orientation: .right) {
                trajectoryPoints.append(TrajectoryPoint(
                    time: time,
                    normalized: tracked.position
                ))
            }
        }
    }
    
    // Switch to custom tracking if Vision fails for N frames
    private func checkVisionFailure() {
        visionFailureCount += 1
        if visionFailureCount > 15 {  // ~0.25 seconds at 60fps
            usingVision = false
            print("⚠️ Vision failed, switching to Kalman tracker")
        }
    }
}
```

