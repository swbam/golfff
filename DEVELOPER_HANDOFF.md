# Golf Shot Tracer App - Developer Handoff

## ⚠️ CRITICAL: Current Status - NOT WORKING

**The shot tracer detection DOES NOT WORK.** The tracer line never appears on exported videos. This document explains what exists, what's broken, and what needs to be built.

---

## 🎯 The Goal: Build SmoothSwing

**SmoothSwing** (iOS App Store) is the reference app. Key features:

1. **Real-time shot tracing** - Ball trajectory appears LIVE while recording
2. **Silhouette alignment** - User aligns themselves with a golfer outline before recording
3. **Haptic lock-in** - Phone vibrates when properly aligned
4. **Works with white golf balls** - Optimized for white ball against sky
5. **Requires iOS 16+** and newer iPhones (A12+ chip)
6. **No ML models** - Uses native iOS frameworks only

### How SmoothSwing Actually Works (Observed Behavior)

1. User positions phone on tripod pointing at tee area
2. Golfer silhouette overlay appears on screen
3. User aligns themselves within the silhouette
4. User taps "Lock In" → phone vibrates
5. User swings
6. **Ball trajectory appears INSTANTLY during the swing**
7. Exported video has tracer burned in

---

## 📁 Current Codebase Structure

```
/IdentifyingBallTrajectoriesinVideo/
├── ShotTracer/
│   ├── CameraManager.swift          ✅ Works - captures video
│   ├── TrajectoryDetector.swift     ❌ BROKEN - VNDetectTrajectoriesRequest not detecting golf balls
│   ├── TrajectoryModel.swift        ✅ Works - data model
│   ├── BallTracker.swift            ❌ BROKEN - simplistic white pixel search fails
│   ├── GolfBallDetector.swift       ❌ BROKEN - Core Image approach doesn't work
│   ├── LiveShotDetector.swift       ❌ UNTESTED - pose detection for swing phases
│   ├── AssetTrajectoryProcessor.swift  ❌ BROKEN - processes imported video, no detections
│   ├── ShotExporter.swift           ✅ Works IF given trajectory points
│   ├── ShotSessionController.swift  ✅ Works - state machine
│   └── UI/
│       ├── PremiumShotViewController.swift    ✅ Works - main camera UI
│       ├── PremiumAlignmentViewController.swift  ⚠️ Cosmetic only - doesn't help detection
│       ├── GolferSilhouetteView.swift         ⚠️ Cosmetic only - just draws shapes
│       ├── BallLocatorViewController.swift    ❌ UNTESTED
│       └── ... other UI files
```

---

## ❌ What's Broken and Why

### 1. VNDetectTrajectoriesRequest (TrajectoryDetector.swift)

**The Issue:** Apple's Vision framework `VNDetectTrajectoriesRequest` is designed to detect objects following parabolic trajectories. It works in Apple's demos with tennis balls, baseballs, etc. **But it's not detecting golf balls.**

**Possible Reasons:**
- Golf balls are TINY (4.27cm diameter) - at 10m distance, they're ~15 pixels
- Golf balls move FAST (driver: 150+ mph)  
- Current parameters may be wrong
- ROI (Region of Interest) may not be set correctly

**Current Parameters (line 92-93):**
```swift
request.objectMinimumNormalizedRadius = 0.004  // 0.4% of frame
request.objectMaximumNormalizedRadius = 0.08   // 8% of frame
```

**What Needs to Be Done:**
- Test with various `objectMinimumNormalizedRadius` and `objectMaximumNormalizedRadius` values
- Try different `trajectoryLength` values (currently 5)
- Ensure proper `frameAnalysisSpacing` for the video frame rate
- Verify the `regionOfInterest` is correctly set
- Add extensive logging to see if ANY observations are returned

---

### 2. BallTracker.swift - Custom Detection Approach

**The Issue:** This attempts to track a white ball by searching for bright pixels. It's too simplistic.

**Why It Fails:**
- Clouds are also white
- Sunlight reflections are white  
- The search area is too small after initial position
- Threshold values are arbitrary
- No motion prediction (ball accelerates/decelerates)

**What Needs to Be Done:**
- Implement proper blob detection (OpenCV or Metal)
- Use motion prediction based on physics (parabolic arc)
- Combine color + motion + shape analysis
- Track across multiple frames with Kalman filter

---

### 3. Silhouette Alignment - Cosmetic Only

**The Issue:** The `GolferSilhouetteView` and `AlignmentOverlayView` just draw shapes. They don't actually help with detection.

**What SmoothSwing Does (Speculation):**
- The silhouette helps user position consistently
- The "ball zone" circle tells the app WHERE THE BALL IS before the swing
- Once locked, the app knows EXACTLY where to look for ball launch
- This makes detection vastly easier

**What Needs to Be Done:**
- The alignment MUST capture the ball's initial position
- This position should be passed to the detector
- Detection should start from this known position
- Track the ball as it leaves that position at high velocity

---

## 🔧 Apple Frameworks Available (No ML)

### Vision Framework
```swift
import Vision

// Trajectory detection (the main approach)
VNDetectTrajectoriesRequest

// Person segmentation (for silhouette)  
VNGeneratePersonSegmentationRequest  // iOS 15+

// Human pose detection (for swing phase)
VNDetectHumanBodyPoseRequest

// Object tracking
VNTrackObjectRequest
VNSequenceRequestHandler
```

### AVFoundation
```swift
import AVFoundation

// Camera capture
AVCaptureSession
AVCaptureVideoDataOutput  // Frames for Vision
AVCaptureMovieFileOutput  // Recording

// Video processing
AVAssetReader
AVAssetReaderTrackOutput

// Export with overlay
AVMutableComposition
AVVideoCompositionCoreAnimationTool
```

### Core Image
```swift
import CoreImage

// Image processing
CIFilter
CIDetector
CIContext
```

### Accelerate / Metal
```swift
import Accelerate
import Metal

// Fast image processing
vImage
Metal compute shaders
```

---

## 🎯 Recommended Approach to Fix

### Option A: Fix VNDetectTrajectoriesRequest

1. Create a test harness that processes a known golf video frame-by-frame
2. Log ALL parameters and results from VNDetectTrajectoriesRequest
3. Systematically vary parameters until detection works
4. Key parameters to test:
   - `objectMinimumNormalizedRadius`: 0.001 to 0.05
   - `objectMaximumNormalizedRadius`: 0.02 to 0.2
   - `trajectoryLength`: 3 to 15
   - `frameAnalysisSpacing`: CMTime.zero vs various intervals

### Option B: Custom Ball Detection

1. Use the alignment to get EXACT ball position before swing
2. When recording starts, track that specific region
3. Detect motion (frame differencing) in that region
4. Once ball launches, use predictive tracking:
   - Ball follows parabolic path
   - Predict next position based on velocity
   - Search in predicted area
   - Use Kalman filter for smooth tracking

### Option C: Hybrid Approach

1. Use VNDetectTrajectoriesRequest as primary
2. Fall back to custom tracking if Vision fails
3. Combine results for best trajectory

---

## 📋 Files That Work

| File | Status | Notes |
|------|--------|-------|
| `CameraManager.swift` | ✅ Works | Captures video, outputs frames |
| `PreviewView.swift` | ✅ Works | Shows camera preview |
| `ShotExporter.swift` | ✅ Works | Burns tracer into video IF given points |
| `TrajectoryModel.swift` | ✅ Works | Data structures |
| `ShotSessionController.swift` | ✅ Works | State management |
| `PremiumShotViewController.swift` | ✅ Works | UI |
| `DesignSystem.swift` | ✅ Works | Colors, fonts |

---

## 📋 Files That Need Fixing

| File | Issue | Priority |
|------|-------|----------|
| `TrajectoryDetector.swift` | VNDetectTrajectoriesRequest not detecting | 🔴 HIGH |
| `AssetTrajectoryProcessor.swift` | No trajectory returned | 🔴 HIGH |
| `BallTracker.swift` | White pixel search too simplistic | 🔴 HIGH |
| `GolfBallDetector.swift` | Core Image approach fails | 🟡 MED |
| `LiveShotDetector.swift` | Untested, may not work | 🟡 MED |
| `GolferSilhouetteView.swift` | Cosmetic only, needs to capture ball pos | 🟡 MED |

---

## 🧪 How to Test

### Test Imported Video Detection

1. Run app on real iPhone (not simulator)
2. Import a golf swing video with:
   - White golf ball
   - Clear blue sky background  
   - Ball visible throughout flight
3. Tap on ball when prompted
4. Check Xcode console for:
   ```
   ═══════════════════════════════════════
   🔍 BALL TRACKING STARTING
   ═══════════════════════════════════════
   ✅ Initial ball position: (x, y)
   📹 Video Properties:
   ...
   📊 TRACKING COMPLETE
      Frames processed: XXX
      Ball detections: XXX    <-- THIS SHOULD BE > 0
   ```

### Test Live Recording

1. Run app on real iPhone
2. Set up tripod
3. Go through alignment
4. Record a swing
5. Check if trajectory appears during recording
6. Check exported video for tracer

---

## 📞 Key Questions for Next Developer

1. **Have you successfully used VNDetectTrajectoriesRequest before?**
   - What parameters worked?
   - What object sizes did you detect?

2. **Do you have experience with real-time object tracking?**
   - Kalman filters?
   - Predictive tracking?

3. **Have you worked with Metal/GPU compute for image processing?**
   - Custom blob detection?
   - Real-time frame analysis?

---

## 🔗 Resources

- [Apple Vision Framework](https://developer.apple.com/documentation/vision)
- [VNDetectTrajectoriesRequest](https://developer.apple.com/documentation/vision/vndetecttrajectoriesrequest)
- [Apple Sample: Identifying Trajectories in Video](https://developer.apple.com/documentation/vision/identifying_trajectories_in_video)
- [SmoothSwing on App Store](https://apps.apple.com/us/app/smoothswing/id1514586439)

---

## 💡 Final Notes

The UI, export pipeline, and state management all work. **The core problem is ball detection.** 

SmoothSwing proves this is possible on iOS without ML. The key insight is likely:
1. **Know where the ball IS before the swing** (alignment/lock-in)
2. **Track from that known position** (not searching entire frame)
3. **Use physics** (ball follows predictable parabolic arc)

Good luck!


