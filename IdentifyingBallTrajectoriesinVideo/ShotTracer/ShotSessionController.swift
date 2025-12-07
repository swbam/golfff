import AVFoundation
import UIKit

// MARK: - Shot State

enum ShotState {
    case idle
    case aligning
    case ready
    case recording
    case tracking
    case importing  // Kept for compatibility but unused
    case exporting
    case finished(videoURL: URL)
}

// MARK: - Shot Session Delegate

protocol ShotSessionControllerDelegate: AnyObject {
    func shotSession(_ controller: ShotSessionController, didUpdateState state: ShotState)
    func shotSession(_ controller: ShotSessionController, didUpdateTrajectory trajectory: Trajectory)
    func shotSession(_ controller: ShotSessionController, didUpdateMetrics metrics: ShotMetrics)
    func shotSession(_ controller: ShotSessionController, didFinishExportedVideo url: URL)
    func shotSession(_ controller: ShotSessionController, didFail error: Error)
}

// MARK: - Shot Session Controller
/// Main controller for live golf shot recording and tracing
///
/// Flow:
/// 1. User aligns with silhouette (ball position is FIXED - no tap needed)
/// 2. Records at HIGH FRAME RATE (240fps if available)
/// 3. Detects impact via pose detection
/// 4. Tracks ball at high frame rate (easy at 240fps!)
/// 5. Exports at 30fps with tracer overlay

final class ShotSessionController: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: ShotSessionControllerDelegate?
    
    /// Camera manager for live capture (HIGH FRAME RATE!)
    let cameraManager: CameraManager
    
    /// Vision-based trajectory detector
    let trajectoryDetector: TrajectoryDetector
    
    /// HIGH FRAME RATE ball tracker - the key to reliable detection!
    private var highFrameRateTracker: HighFrameRateBallTracker?
    
    /// Video exporter
    private let exporter = ShotExporter()
    
    /// Distance estimator
    private let distanceEstimator = DistanceEstimator()
    
    /// Coordinate converter
    private let coordinateConverter = CoordinateConverter()
    
    // Live shot detector for real-time swing detection (iOS 15+)
    private var _liveShotDetector: Any?
    
    @available(iOS 15.0, *)
    var liveShotDetector: LiveShotDetector {
        if _liveShotDetector == nil {
            _liveShotDetector = LiveShotDetector()
        }
        return _liveShotDetector as! LiveShotDetector
    }
    
    /// Ball position from silhouette alignment (NO TAP REQUIRED!)
    /// The silhouette defines where the ball is - user just aligns themselves
    private var silhouetteBallPosition: CGPoint?
    
    /// Region of interest for detection
    private var regionOfInterest: CGRect?
    
    /// Recording state
    private var recordedURL: URL?
    private var finalTrajectory: Trajectory?
    private var finalMetrics: ShotMetrics?
    private(set) var tracerColor: UIColor = ShotTracerDesign.Colors.tracerGold
    
    /// Debug logging
    var debugLogging = true
    
    /// Current state
    var state: ShotState = .idle {
        didSet {
            if debugLogging {
                print("🔄 State changed: \(state)")
            }
            delegate?.shotSession(self, didUpdateState: state)
        }
    }
    
    /// Frame counter for subsampling display updates
    private var frameCounter = 0
    
    // MARK: - Initialization
    
    init(cameraManager: CameraManager, trajectoryDetector: TrajectoryDetector) {
        self.cameraManager = cameraManager
        self.trajectoryDetector = trajectoryDetector
        super.init()
        
        self.cameraManager.delegate = self
        self.trajectoryDetector.delegate = self
        self.trajectoryDetector.debugLogging = debugLogging
        
        // Setup live detector callbacks (iOS 15+)
        if #available(iOS 15.0, *) {
            setupLiveShotDetector()
        }
        
        // Monitor thermal state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        applyThermalSpacing()
        
        state = .ready
    }
    
    // MARK: - Setup
    
    @available(iOS 15.0, *)
    private func setupLiveShotDetector() {
        liveShotDetector.debugLogging = debugLogging
        
        liveShotDetector.onSwingPhaseChanged = { [weak self] phase in
            guard let self = self else { return }
            
            if self.debugLogging {
                print("🏌️ Swing phase: \(phase.rawValue)")
            }
            
            if case .impact = phase {
                // Start high frame rate tracking
                self.highFrameRateTracker?.startTracking()
                
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
            }
        }
        
        liveShotDetector.onImpactDetected = { [weak self] in
            guard let self = self else { return }
            self.highFrameRateTracker?.startTracking()
            
            if self.debugLogging {
                print("💥 Impact detected - starting high frame rate tracking")
            }
        }
    }
    
    // MARK: - Public API
    
    /// Lock in position for live recording
    /// The ball position comes from the SILHOUETTE - no user tap required!
    func lockPosition(ballPosition: CGPoint) {
        silhouetteBallPosition = ballPosition
        
        // Initialize HIGH FRAME RATE tracker with ball position from silhouette
        highFrameRateTracker = HighFrameRateBallTracker()
        highFrameRateTracker?.frameRate = cameraManager.currentFrameRate
        highFrameRateTracker?.debugLogging = debugLogging
        highFrameRateTracker?.setInitialBallPosition(ballPosition)
        
        if #available(iOS 15.0, *) {
            liveShotDetector.lockPosition(ballPosition: ballPosition)
        }
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        if debugLogging {
            print("═══════════════════════════════════════")
            print("🔒 LOCKED IN - SILHOUETTE BALL POSITION")
            print("═══════════════════════════════════════")
            print("   Position: (\(String(format: "%.3f", ballPosition.x)), \(String(format: "%.3f", ballPosition.y)))")
            print("   Frame rate: \(cameraManager.currentFrameRate) fps")
            print("   NO TAP REQUIRED - silhouette defines ball location!")
            print("═══════════════════════════════════════")
        }
    }
    
    /// Set region of interest for detection
    func setRegionOfInterest(_ rect: CGRect) {
        regionOfInterest = rect
        trajectoryDetector.regionOfInterest = rect
    }
    
    /// Set tracer color
    func setTracerColor(_ color: UIColor) {
        tracerColor = color
    }
    
    /// Start camera session
    func startSession() {
        cameraManager.configureSession()
    }
    
    /// Start recording at HIGH FRAME RATE
    func startRecording() {
        guard case .ready = state else { return }
        
        state = .recording
        finalTrajectory = nil
        finalMetrics = nil
        recordedURL = nil
        frameCounter = 0
        distanceEstimator.reset()
        
        // Ensure ball position is set
        if let ballPos = silhouetteBallPosition {
            highFrameRateTracker?.setInitialBallPosition(ballPos)
        }
        
        // Start Vision detector
        trajectoryDetector.start()
        
        // Start camera recording
        cameraManager.startRecording()
        
        if debugLogging {
            print("═══════════════════════════════════════")
            print("🎬 RECORDING STARTED @ \(cameraManager.currentFrameRate) fps")
            print("═══════════════════════════════════════")
        }
    }
    
    /// Stop recording and begin export
    func stopRecording() {
        guard case .recording = state else { return }
        
        state = .tracking
        
        // Stop high frame rate tracker
        highFrameRateTracker?.stopTracking()
        
        cameraManager.stopRecording()
        trajectoryDetector.stop()
        
        // Unlock live detector
        if #available(iOS 15.0, *) {
            liveShotDetector.unlock()
        }
        
        if debugLogging {
            print("🛑 Recording stopped")
        }
    }
    
    // MARK: - Export
    
    private func exportWithTrajectory(url: URL, trajectory: Trajectory?) {
        self.finalTrajectory = trajectory
        self.recordedURL = url
        self.state = .exporting
        
        self.exporter.export(
            videoURL: url,
            trajectory: trajectory,
            tracerColor: self.tracerColor
        ) { [weak self] exportResult in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch exportResult {
                case .success(let exportedURL):
                    self.state = .finished(videoURL: exportedURL)
                    self.delegate?.shotSession(self, didFinishExportedVideo: exportedURL)
                    
                case .failure(let error):
                    self.state = .ready
                    self.delegate?.shotSession(self, didFail: error)
                }
            }
        }
    }
    
    // MARK: - Thermal Management
    
    @objc private func thermalStateChanged() {
        applyThermalSpacing()
    }
    
    private func applyThermalSpacing() {
        let spacing = desiredFrameSpacing()
        trajectoryDetector.update(frameSpacingSeconds: spacing)
        
        if debugLogging && spacing > 0 {
            print("🌡️ Thermal adjustment: frame spacing = \(spacing)s")
        }
    }
    
    private func desiredFrameSpacing() -> Double {
        switch ProcessInfo.processInfo.thermalState {
        case .critical:
            return 0.08  // Analyze every 5th frame at 60fps
        case .serious:
            return 0.04  // Every 2-3 frames
        case .fair:
            return 0.02  // Every other frame
        default:
            return 0.0   // Every frame
        }
    }
    
    // MARK: - Helpers
    
    private func attemptExportIfReady() {
        switch state {
        case .tracking, .exporting:
            break
        default:
            return
        }
        
        guard let url = recordedURL else { return }
        
        // Get best trajectory from available sources
        let trajectory = getBestTrajectory()
        
        state = .exporting
        
        exporter.export(
            videoURL: url,
            trajectory: trajectory,
            tracerColor: tracerColor
        ) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let exportedURL):
                    self.state = .finished(videoURL: exportedURL)
                    self.delegate?.shotSession(self, didFinishExportedVideo: exportedURL)
                    
                case .failure(let error):
                    self.state = .ready
                    self.delegate?.shotSession(self, didFail: error)
                }
            }
        }
    }
    
    private func getBestTrajectory() -> Trajectory? {
        // Priority:
        // 1. HIGH FRAME RATE tracker (most reliable at 240fps!)
        // 2. Vision detector result
        // 3. Live shot detector result (iOS 15+)
        // 4. Final trajectory (if any)
        
        // HIGH FRAME RATE tracker is primary
        if let hfrTraj = highFrameRateTracker?.buildTrajectory(), hfrTraj.points.count >= 5 {
            if debugLogging {
                print("═══════════════════════════════════════")
                print("📍 Using HIGH FRAME RATE trajectory")
                print("   Points: \(hfrTraj.points.count)")
                print("   Confidence: \(String(format: "%.2f", hfrTraj.confidence))")
                print("═══════════════════════════════════════")
            }
            return hfrTraj
        }
        
        // Vision detector trajectory
        if let visionTraj = trajectoryDetector.currentTrajectory, visionTraj.points.count >= 5 {
            if debugLogging {
                print("📍 Using Vision detector trajectory (\(visionTraj.points.count) points)")
            }
            return visionTraj
        }
        
        // LiveShotDetector no longer has ball tracking - we use HighFrameRateBallTracker instead
        
        if let final = finalTrajectory, final.points.count >= 3 {
            if debugLogging {
                print("📍 Using final trajectory (\(final.points.count) points)")
            }
            return final
        }
        
        if debugLogging {
            print("⚠️ No trajectory available for export")
        }
        return nil
    }
    
    /// Reset session to ready state
    func resetSession() {
        state = .ready
        finalTrajectory = nil
        finalMetrics = nil
        recordedURL = nil
        silhouetteBallPosition = nil
        frameCounter = 0
        
        // Reset trackers
        highFrameRateTracker?.reset()
        highFrameRateTracker = nil
        distanceEstimator.reset()
        
        if #available(iOS 15.0, *) {
            liveShotDetector.unlock()
        }
    }
}

// MARK: - CameraManagerDelegate

extension ShotSessionController: CameraManagerDelegate {
    
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        frameCounter += 1
        
        // ═══════════════════════════════════════════════════════════════
        // HIGH FRAME RATE PROCESSING
        // At 240fps, process EVERY frame for tracking
        // But only update UI every 4th frame (60fps display)
        // ═══════════════════════════════════════════════════════════════
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Process with HIGH FRAME RATE tracker (primary)
        if let tracker = highFrameRateTracker, case .recording = state {
            let result = tracker.processFrame(
                pixelBuffer,
                timestamp: time,
                orientation: trajectoryDetector.orientation
            )
            
            // Update UI at display rate (every 4th frame at 240fps = 60fps UI)
            let displayUpdateInterval = max(1, Int(manager.currentFrameRate / 60))
            
            if result.isTracking && frameCounter % displayUpdateInterval == 0 {
                if let trajectory = tracker.buildTrajectory() {
                    finalTrajectory = trajectory
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.shotSession(self, didUpdateTrajectory: trajectory)
                        
                        // Update metrics
                        let metrics = self.distanceEstimator.update(with: trajectory)
                        self.finalMetrics = metrics
                        self.delegate?.shotSession(self, didUpdateMetrics: metrics)
                    }
                }
            }
        }
        
        // Also feed to Vision detector (backup)
        trajectoryDetector.process(sampleBuffer: sampleBuffer)
        
        // Feed to live shot detector for impact detection (iOS 15+)
        if #available(iOS 15.0, *), case .recording = state {
            let result = liveShotDetector.processFrame(
                pixelBuffer,
                time: time,
                orientation: trajectoryDetector.orientation
            )
            
            // If impact detected, start high frame rate tracking!
            if result.swingPhase == .impact {
                highFrameRateTracker?.startTracking()
                
                if debugLogging {
                    print("💥 IMPACT DETECTED - High frame rate tracking started!")
                }
            }
        }
    }
    
    func cameraManager(_ manager: CameraManager, didFinishRecordingTo url: URL) {
        recordedURL = url
        
        if debugLogging {
            print("📹 Recording saved to: \(url.lastPathComponent)")
        }
        
        attemptExportIfReady()
    }
    
    func cameraManager(_ manager: CameraManager, didFail error: Error) {
        if debugLogging {
            print("❌ Camera error: \(error.localizedDescription)")
        }
        delegate?.shotSession(self, didFail: error)
    }
}

// MARK: - TrajectoryDetectorDelegate

extension ShotSessionController: TrajectoryDetectorDelegate {
    
    func trajectoryDetector(_ detector: TrajectoryDetector, didUpdate trajectory: Trajectory) {
        // Store trajectory from Vision detector
        self.finalTrajectory = trajectory
        
        if debugLogging {
            print("📊 Vision Trajectory: \(trajectory.detectedPoints.count) detected, \(trajectory.projectedPoints.count) projected")
        }
        
        delegate?.shotSession(self, didUpdateTrajectory: trajectory)
        
        // Calculate and report metrics
        let metrics = distanceEstimator.update(with: trajectory)
        finalMetrics = metrics
        delegate?.shotSession(self, didUpdateMetrics: metrics)
    }
    
    func trajectoryDetectorDidFinish(_ detector: TrajectoryDetector, finalTrajectory: Trajectory?) {
        self.finalTrajectory = finalTrajectory
        
        if debugLogging {
            if let traj = finalTrajectory {
                print("✅ Final trajectory: \(traj.points.count) points")
            } else {
                print("❌ No trajectory detected")
            }
        }
        
        attemptExportIfReady()
    }
}
