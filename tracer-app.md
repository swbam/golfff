Here’s a new spec you can give straight to an AI dev, this time **explicitly built around the Mizuno GitHub project** as the starting point.

---

## 0. Task description (give this paragraph to the dev)

You are tasked with building an iOS app in Swift that replicates the **shot‑tracer behavior of SmoothSwing**, but without GPS or course features. The app must record a golf swing, show a **live tracer** of the ball’s flight while recording, and then export a video where the tracer is **identical** to what the user saw live. You must **start from the open‑source Mizuno repository “IdentifyingBallTrajectoriesinVideo”** (which already implements real‑time ball trajectory detection with Vision’s `VNDetectTrajectoriesRequest`) ([GitHub][1]) and adapt/extend it into a production‑style app with: a clean camera UI, a simple golfer alignment step, real‑time tracing while recording, and an export pipeline that burns the tracer into the saved video.

---

## 1. Base template: Mizuno project

### 1.1 Get and understand the template

1. Clone the repo: **MIZUNO‑CORPORATION / IdentifyingBallTrajectoriesinVideo** (MIT licensed). ([GitHub][1])
2. Open `IdentifyingBallTrajectoriesinVideo.xcodeproj` in Xcode.
3. Build & run on a real device (A12 or newer).
4. Read the README’s “Flow of the trajectory detection” section, which explains:

   * How they configure `VNDetectTrajectoriesRequest`.
   * How they feed frames using `VNImageRequestHandler` in `captureOutput`.
   * How they convert Vision’s normalized coordinates to UIView coordinates and use an ROI. ([GitHub][1])

### 1.2 Pieces we will reuse

From Mizuno’s project, conceptually reuse:

* **Preview layer wrapper**
  A `UIView` subclass `PreviewView` whose backing layer is `AVCaptureVideoPreviewLayer`. ([GitHub][1])
* **Capture output → Vision pipeline**
  Their `captureOutput(_:didOutput:from:)` method that:

  * Wraps each `CMSampleBuffer` in a `VNImageRequestHandler`.
  * Calls `perform([request])` on a `VNDetectTrajectoriesRequest`. ([GitHub][1])
* **Request configuration**
  Code creating a `VNDetectTrajectoriesRequest` with:

  * `frameAnalysisSpacing`
  * `trajectoryLength`
  * `objectMinimumNormalizedRadius` / `objectMaximumNormalizedRadius`
  * `regionOfInterest` ([GitHub][1])
* **Result processing**
  Their `completionHandler(request:error:)` implementation that:

  * Casts results to `[VNTrajectoryObservation]`.
  * Converts Vision coordinates (origin bottom‑left) to UIKit’s (origin top‑left).
  * Shows how to get `detectedPoints`, `projectedPoints`, `equationCoefficients`, `uuid`, `timeRange`, and `confidence`. ([GitHub][1])
* **Normalized → view coordinate mapping**
  The function that maps normalized [0–1] points to the preview’s rect or to an ROI rect. ([GitHub][1])

These are the **core algorithms**; we’ll refactor them into our own modules instead of keeping everything in one ViewController.

---

## 2. High‑level architecture of the new app

We will create a new app (new Xcode project) and then copy/adapt Mizuno code into it.

### 2.1 Modules

1. **CameraModule**

   * `CameraManager` (AVCaptureSession + recording).
   * `PreviewView` (from Mizuno, lightly edited).

2. **TrajectoryModule** (refactored from Mizuno logic)

   * `TrajectoryDetector` – wraps `VNDetectTrajectoriesRequest`.
   * `TrajectoryModel` – struct for storing normalized points and timing.
   * `TrajectoryOverlayView` – draws live tracer using CAShapeLayers.

3. **AlignmentModule**

   * `AlignmentViewController` – golfer outline overlay, ROI definition.

4. **ExportModule**

   * `ShotExporter` – replays stored trajectory onto recorded video using AVComposition + CoreAnimation.

5. **ShotFlowModule**

   * `ShotSessionController` – state machine: alignment → ready → recording → tracking → exporting → finished.

---

## 3. Detailed build plan, step‑by‑step

### 3.1 Create new Xcode project & import core Mizuno pieces

1. Create a new iOS App project in Xcode (Swift, UIKit, iOS 16+).

2. Add a new group `Camera` and create `PreviewView.swift`:

   * Copy the pattern from Mizuno:

     * Override `layerClass` to return `AVCaptureVideoPreviewLayer`.
     * Provide `var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }`. ([GitHub][1])

   * This is your camera preview view.

3. Add a new group `Trajectory` and copy the concepts from Mizuno into:

   * `TrajectoryDetector.swift`
   * `TrajectoryModel.swift`
   * `TrajectoryOverlayView.swift`

We won’t literally copy their entire ViewController; we’ll re‑organize into clean classes but using the **same Vision patterns**.

---

## 4. CameraModule – using Mizuno’s capture & preview patterns

### 4.1 CameraManager

Create `CameraManager` that encapsulates:

* `AVCaptureSession`
* `AVCaptureDeviceInput` (.builtInWideAngleCamera, .back)
* `AVCaptureVideoDataOutput` (frames for Vision)
* `AVCaptureMovieFileOutput` (for recording video)

**API:**

```swift
protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager,
                       didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager,
                       didFinishRecordingTo url: URL)
    func cameraManager(_ manager: CameraManager,
                       didFail error: Error)
}

final class CameraManager: NSObject {
    weak var delegate: CameraManagerDelegate?

    let previewView: PreviewView   // injected or created inside

    func configureSession()
    func startSession()
    func stopSession()

    func startRecording()
    func stopRecording()
}
```

**Implementation hints (reuse from Mizuno + AVFoundation docs)**

* Session preset: `.hd1920x1080` (or `.hd1280x720` if you need lighter compute).
* Add `AVCaptureVideoDataOutput`:

  * Set sampleBufferDelegate to `self`.
  * Use a serial queue (e.g., `"shottracer.vision.queue"`).
  * Set `alwaysDiscardsLateVideoFrames = true`.
* In `captureOutput(_:didOutput:from:)`, simply forward to the delegate (we’ll send it to `TrajectoryDetector`).

Mizuno’s README shows how they used `captureOutput` to create a `VNImageRequestHandler` for each frame; we’ll move that into `TrajectoryDetector`. ([GitHub][1])

### 4.2 Recording

For simplicity, use `AVCaptureMovieFileOutput`:

* Attach it to the same session.
* Start/stop recording tied to the main UI button:

  * `movieOutput.startRecording(to: outputURL, recordingDelegate: self)`
  * On delegate callback `fileOutput(_:didFinishRecordingTo:from:error:)`, call `cameraManager(_:didFinishRecordingTo:)`.

We’ll then pass that URL into `ShotExporter`.

---

## 5. TrajectoryModule – refactoring Mizuno’s Vision logic

### 5.1 TrajectoryModel

Define a small set of structs:

```swift
struct TrajectoryPoint {
    let time: CMTime            // capture timestamp
    let normalized: CGPoint     // (0–1, origin top-left) for video space
}

struct Trajectory {
    var id: UUID
    var points: [TrajectoryPoint]
    var confidence: VNConfidence
}
```

We store **normalized** coordinates because they are resolution‑ and layout‑independent and match how Mizuno processes them. ([GitHub][1])

### 5.2 TrajectoryDetector (rewrap Mizuno logic)

Create `TrajectoryDetector`:

```swift
protocol TrajectoryDetectorDelegate: AnyObject {
    func trajectoryDetector(_ detector: TrajectoryDetector,
                            didUpdate trajectory: Trajectory)
    func trajectoryDetectorDidFinish(_ detector: TrajectoryDetector,
                                     finalTrajectory: Trajectory?)
}

final class TrajectoryDetector {
    weak var delegate: TrajectoryDetectorDelegate?

    var regionOfInterest: CGRect?   // set from AlignmentModule, normalized Vision coords

    func start()
    func stop()
    func process(sampleBuffer: CMSampleBuffer)
}
```

**Internal properties:**

* `private let requestHandler = VNSequenceRequestHandler()`
* `private var request: VNDetectTrajectoriesRequest`
* `private var currentTrajectory: Trajectory?`
* `private var isRunning = false`

**Configure the request (adapt from Mizuno README):** ([GitHub][1])

* `frameAnalysisSpacing: .zero` to start (analyze each frame; we can adjust later).
* `trajectoryLength: 10` (Mizuno uses this for golf).
* Set `objectMinimumNormalizedRadius` and `objectMaximumNormalizedRadius` to roughly match golf ball size (their example sets `.1` and `.5`; tune for your camera distance).
* Set `regionOfInterest` from `AlignmentModule` if provided.

Pseudo‑init:

```swift
private func makeRequest() -> VNDetectTrajectoriesRequest {
    let req = VNDetectTrajectoriesRequest(frameAnalysisSpacing: .zero,
                                          trajectoryLength: 10,
                                          completionHandler: handleRequest)
    req.objectMaximumNormalizedRadius = 0.5
    req.objectMinimumNormalizedRadius = 0.1
    if let roi = regionOfInterest {
        req.regionOfInterest = roi
    }
    return req
}
```

**Processing frames (based on Mizuno’s `captureOutput`):** ([GitHub][1])

```swift
func process(sampleBuffer: CMSampleBuffer) {
    guard isRunning else { return }

    let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

    do {
        try requestHandler.perform(
            [request],
            on: sampleBuffer,
            orientation: .right   // portrait, same as Mizuno
        )
    } catch {
        // log error
    }

    // The completion handler will be called asynchronously;
    // we need to capture `ts` if we want per-point timing:
    lastTimestamp = ts
}
```

*Implementation detail*: Vision’s completion handler doesn’t directly give you per‑frame timestamps, only a `timeRange` per trajectory. Mizuno’s README shows how to use `timeRange`; you can:

* Use `timeRange` to know when the trajectory starts/ends relative to video. ([GitHub][1])
* Optionally track your own timeline (e.g., `lastTimestamp`) to approximate per‑point times.

**Completion handler (adapt from Mizuno’s `completionHandler`):** ([GitHub][1])

1. Cast `request.results` to `[VNTrajectoryObservation]`.
2. For each observation:

   * Get `detectedPoints` & `projectedPoints`.
   * Convert from Vision to UIKit coordinates by flipping y: `y' = 1 - y`.
3. Choose one “best” observation:

   * Highest `confidence`.
   * Plausible direction (up then down).
   * In ROI near expected launch area.
4. Convert points to `TrajectoryPoint` using normalized coordinates and approximate times (e.g. distribute times evenly over `timeRange` or around `lastTimestamp`).
5. Merge new points into `currentTrajectory` (or create a new one).
6. Call delegate with updated trajectory.

Pseudo:

```swift
private func handleRequest(request: VNRequest, error: Error?) {
    guard error == nil,
          let observations = request.results as? [VNTrajectoryObservation]
    else { return }

    guard let bestObs = chooseBestObservation(from: observations) else { return }

    let normalizedPoints: [CGPoint] = bestObs.detectedPoints.map {
        CGPoint(x: CGFloat($0.x), y: 1.0 - CGFloat($0.y))
    }

    var traj = currentTrajectory ?? Trajectory(
        id: bestObs.uuid,
        points: [],
        confidence: bestObs.confidence
    )

    let timeRange = bestObs.timeRange
    let dt = timeRange.duration.seconds / Double(max(normalizedPoints.count - 1, 1))
    var t = timeRange.start.seconds

    for p in normalizedPoints {
        let pointTime = CMTime(seconds: t, preferredTimescale: 600)
        traj.points.append(TrajectoryPoint(time: pointTime,
                                           normalized: p))
        t += dt
    }

    traj.confidence = max(traj.confidence, bestObs.confidence)
    currentTrajectory = traj

    DispatchQueue.main.async {
        self.delegate?.trajectoryDetector(self, didUpdate: traj)
    }
}
```

When you detect that the ball has completed its trajectory (e.g., no observations for N frames, or timeRange ends), call:

```swift
delegate?.trajectoryDetectorDidFinish(self, finalTrajectory: currentTrajectory)
isRunning = false
```

---

## 6. TrajectoryOverlayView – live tracer drawing

This sits on top of the camera preview and renders the shot tracer as the trajectory updates.

Create `TrajectoryOverlayView: UIView`:

* Two `CAShapeLayer`s:

  * `shadowLayer` (black, slightly offset).
  * `tracerLayer` (red or user‑selected color).

**Key method:**

```swift
func update(with normalizedPoints: [CGPoint]) {
    guard !normalizedPoints.isEmpty else {
        shadowLayer.path = nil
        tracerLayer.path = nil
        return
    }

    let path = UIBezierPath()
    let shadowPath = UIBezierPath()

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * bounds.width,
                y: p.y * bounds.height)
    }

    let start = toView(normalizedPoints[0])
    path.move(to: start)
    shadowPath.move(to: CGPoint(x: start.x + 2, y: start.y + 2))

    for p in normalizedPoints.dropFirst() {
        let v = toView(p)
        path.addLine(to: v)
        shadowPath.addLine(to: CGPoint(x: v.x + 2, y: v.y + 2))
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    tracerLayer.path = path.cgPath
    shadowLayer.path = shadowPath.cgPath
    CATransaction.commit()
}
```

Tie this to `TrajectoryDetectorDelegate`:

```swift
func trajectoryDetector(_ detector: TrajectoryDetector,
                        didUpdate trajectory: Trajectory) {
    overlayView.update(with: trajectory.points.map { $0.normalized })
}
```

Because both `TrajectoryDetector` and `TrajectoryOverlayView` use the same normalized coordinates (like Mizuno’s `convertPointToUIViewCoordinates` but simplified), the live overlay matches the captured frames. ([GitHub][1])

---

## 7. AlignmentModule – simple golfer outline and ROI

We’ll keep this **simple and robust** (no Vision pose detection in v1).

### 7.1 AlignmentViewController

Create a `UIViewController` with:

* `PreviewView` (camera).
* Overlay image of a golfer outline + club (PNG with transparency).
* A circle marker where the ball should sit (e.g., bottom center).
* “Lock In” button.

Flow:

1. User points camera & positions themselves so they roughly fit the outline and ball sits over the marker.
2. When satisfied, they tap **Lock In**:

   * Play `UINotificationFeedbackGenerator().notificationOccurred(.success)`.
   * Compute a **regionOfInterest** for Vision:

     * A rectangle from slightly above the ball marker to the top of the frame, centered horizontally.
   * Save ROI in normalized Vision coordinates and feed it to `TrajectoryDetector.regionOfInterest`.
   * Dismiss Alignment screen and go to main shot screen.

**Computing ROI:**

Assume ball marker view frame is `markerFrame` in overlay coordinates:

```swift
// markerFrame is in overlayView (full screen) coordinates
let overlayBounds = overlayView.bounds

let roiX: CGFloat = 0.15
let roiWidth: CGFloat = 0.7
// Vision's coord origin is bottom-left; convert
let roiY: CGFloat = 0.15
let roiHeight: CGFloat = 0.8

let roi = CGRect(x: roiX, y: roiY,
                 width: roiWidth, height: roiHeight)
trajectoryDetector.regionOfInterest = roi
```

You can refine this so the ROI vertically starts at the ball marker’s y and extends upward; just make sure to convert between UIKit and Vision coordinate systems as Mizuno describes. ([GitHub][1])

---

## 8. ExportModule – burn tracer into final video

After recording, we use normalized trajectory points to draw into the final file.

### 8.1 ShotExporter

Signature:

```swift
final class ShotExporter {
    func export(videoURL: URL,
                trajectory: Trajectory?,
                tracerColor: UIColor,
                completion: @escaping (Result<URL, Error>) -> Void)
}
```

Steps:

1. **Set up AVComposition**

   * Create `AVAsset` from `videoURL`.
   * Create `AVMutableComposition` and add a video track (and audio if present).
   * Insert the entire timeRange of the original track at time `.zero`.

2. **Create AVMutableVideoComposition**

   * `renderSize = asset.tracks(withMediaType: .video).first!.naturalSize`
   * `frameDuration` from track’s nominalFrameRate.
   * Add a single `AVMutableVideoCompositionInstruction` covering the whole duration with a `AVMutableVideoCompositionLayerInstruction` for the video track.

3. **Create CoreAnimation overlay**

   * Parent layer & video layer:

     ```swift
     let videoSize = videoTrack.naturalSize
     let parentLayer = CALayer()
     parentLayer.frame = CGRect(origin: .zero, size: videoSize)

     let videoLayer = CALayer()
     videoLayer.frame = parentLayer.bounds
     parentLayer.addSublayer(videoLayer)

     let overlayLayer = CALayer()
     overlayLayer.frame = parentLayer.bounds
     parentLayer.addSublayer(overlayLayer)
     ```

   * Tracer layers:

     ```swift
     let tracerLayer = CAShapeLayer()
     tracerLayer.frame = overlayLayer.bounds
     tracerLayer.strokeColor = tracerColor.cgColor
     tracerLayer.fillColor = UIColor.clear.cgColor
     tracerLayer.lineWidth = 6
     tracerLayer.lineCap = .round

     let shadowLayer = CAShapeLayer()
     shadowLayer.frame = overlayLayer.bounds
     shadowLayer.strokeColor = UIColor.black.withAlphaComponent(0.6).cgColor
     shadowLayer.fillColor = UIColor.clear.cgColor
     shadowLayer.lineWidth = 8
     shadowLayer.lineCap = .round

     overlayLayer.addSublayer(shadowLayer)
     overlayLayer.addSublayer(tracerLayer)
     ```

4. **Convert normalized trajectory → video coordinates**

   ```swift
   guard let trajectory = trajectory,
         !trajectory.points.isEmpty else {
       // export original video unchanged
   }

   let path = UIBezierPath()
   let shadowPath = UIBezierPath()

   func toVideo(_ p: CGPoint) -> CGPoint {
       CGPoint(x: p.x * videoSize.width,
               y: p.y * videoSize.height)
   }

   let first = toVideo(trajectory.points[0].normalized)
   path.move(to: first)
   shadowPath.move(to: CGPoint(x: first.x + 2, y: first.y + 2))

   for pt in trajectory.points.dropFirst() {
       let v = toVideo(pt.normalized)
       path.addLine(to: v)
       shadowPath.addLine(to: CGPoint(x: v.x + 2, y: v.y + 2))
   }

   tracerLayer.path = path.cgPath
   shadowLayer.path = shadowPath.cgPath
   ```

5. **Optional: animate tracer along timeRange**

   ```swift
   let trajDuration = trajectory.points.last!.time - trajectory.points.first!.time
   let durationSec = trajDuration.seconds

   let anim = CABasicAnimation(keyPath: "strokeEnd")
   anim.fromValue = 0
   anim.toValue = 1
   anim.duration = durationSec
   anim.timingFunction = CAMediaTimingFunction(name: .easeOut)

   tracerLayer.add(anim, forKey: "strokeEnd")
   shadowLayer.add(anim, forKey: "strokeEnd")
   ```

6. **Attach animation tool & export**

   ```swift
   videoComposition.animationTool =
       AVVideoCompositionCoreAnimationTool(
           postProcessingAsVideoLayer: videoLayer,
           in: parentLayer
       )

   let exporter = AVAssetExportSession(asset: composition,
                                       presetName: AVAssetExportPresetHighestQuality)!
   exporter.videoComposition = videoComposition
   exporter.outputURL = outputURL
   exporter.outputFileType = .mp4

   exporter.exportAsynchronously {
       switch exporter.status {
       case .completed:
           completion(.success(outputURL))
       case .failed, .cancelled:
           completion(.failure(exporter.error ?? ExportError.unknown))
       default:
           break
       }
   }
   ```

Because we’re using the **same normalized trajectory data** as the live overlay (similar to Mizuno’s coordinate conversion function, just targeting video pixels instead of the preview’s rect), the exported tracer will match exactly what the user saw live. ([GitHub][1])

---

## 9. ShotFlowModule – app‑level state machine

Implement a `ShotSessionController` (can be a ViewModel or part of main ViewController) that manages:

```swift
enum ShotState {
    case idle
    case aligning
    case ready
    case recording
    case tracking
    case exporting
    case finished(videoURL: URL)
}
```

**Flow:**

1. **Initial launch**

   * Start camera session.
   * Present Alignment screen (state `.aligning`).

2. **After Lock In**

   * Capture ROI, set `TrajectoryDetector.regionOfInterest`.
   * Dismiss alignment, show main camera UI with:

     * Record button.
     * Tracer color picker.
   * State → `.ready`.

3. **User hits Record**

   * `CameraManager.startRecording()`.
   * `TrajectoryDetector.start()`.
   * As frames arrive from `CameraManager`, feed them into `TrajectoryDetector.process(sampleBuffer:)`.
   * State → `.recording`.

4. **Ball is hit**

   * `TrajectoryDetector` detects trajectory and calls delegate with updates.
   * `ShotSessionController` pushes these into `TrajectoryOverlayView`.
   * State → `.tracking`.

5. **User stops Record**

   * `CameraManager.stopRecording()`.
   * When file URL comes back, store it.
   * When `TrajectoryDetectorDidFinish` fires, store final `Trajectory`.
   * State → `.exporting`.
   * Pass file URL + trajectory to `ShotExporter.export(...)`.

6. **Export complete**

   * Show playback UI with share button for exported video.
   * State → `.finished(videoURL:)`.

---

## 10. UI details

* **Main camera screen**

  * Full‑screen `PreviewView`.
  * Overlaid `TrajectoryOverlayView`.
  * Top:

    * Timer label.
  * Bottom:

    * Big circular record button.
    * Tracer color picker (grid of small colored buttons; when tapped, update overlay and exporter color).

* **Alignment screen**

  * Same `PreviewView`.
  * Semi‑transparent golfer outline (image or vector).
  * Ball marker at lower center.
  * “Lock In” button at bottom.
  * Text: “Align yourself with the outline, place the ball on the marker, then tap Lock In.”

* **Review screen**

  * Simple video player (e.g., `AVPlayerViewController` embedded).
  * Share / Save buttons.

---

## 11. Performance & tuning (based on Mizuno notes)

Mizuno highlights a few key points in the README that you should respect: ([GitHub][1])

* **frameAnalysisSpacing**

  * `.zero` = analyze every frame (best accuracy, higher CPU/GPU use).
  * Larger spacing = fewer frames, lower load; use on older devices or when overheating.

* **trajectoryLength**

  * Minimum is 5; 10 works well for golf.
  * Too low → many false or short trajectories.

* **Region of interest**

  * Always set `regionOfInterest` so Vision only analyzes the part of the frame where the ball will fly.
  * ROI is specified in normalized coordinates [0–1] with origin at bottom‑left; convert carefully from your UI.

* **Object size filters**

  * `objectMinimumNormalizedRadius` / `objectMaximumNormalizedRadius` help reject noise and large moving objects.

Also:

* Monitor `ProcessInfo.processInfo.thermalState` and stop new shots if state reaches `.serious` or `.critical`.
* Consider using `.hd1280x720` preset if 1080p causes dropped frames.

---

## 12. Summary for the dev

* Use the **Mizuno project** as your reference implementation of `VNDetectTrajectoriesRequest` + coordinate conversion + ROI. ([GitHub][1])
* Build a **new app** that:

  * Reuses their preview pattern (`PreviewView`).
  * Refactors their Vision logic into `TrajectoryDetector` and `TrajectoryOverlayView`.
* Add:

  * A simple **Alignment screen** to define ROI.
  * A **CameraManager** that supports recording via `AVCaptureMovieFileOutput`.
  * A **ShotExporter** that burns the tracer into the final video using AVComposition and CoreAnimation.
* Drive everything from a **ShotSessionController** state machine so the UX is: align → record & see live tracer → export & share.

You can follow this outline step‑by‑step in an AI coding tool and implement each class one at a time, using the Mizuno repo and Apple’s Vision docs when you need the exact Vision call patterns.

[1]: https://github.com/MIZUNO-CORPORATION/IdentifyingBallTrajectoriesinVideo "GitHub - MIZUNO-CORPORATION/IdentifyingBallTrajectoriesinVideo"
