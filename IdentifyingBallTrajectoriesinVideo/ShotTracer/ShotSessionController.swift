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
/// ═══════════════════════════════════════════════════════════════════
/// REAL-TIME COMPOSITING MODE (SmoothSwing-style!)
/// ═══════════════════════════════════════════════════════════════════
///
/// Flow:
/// 1. User aligns with silhouette - AUTOMATIC lock-in with haptic!
/// 2. Records at HIGH FRAME RATE (240fps if available)
/// 3. Tracer is composited IN REAL-TIME onto video frames
/// 4. Export is INSTANT - no post-processing needed!
/// 5. Live view === Exported video
///
/// The KEY difference from traditional approach:
/// - Old: Record video → Detect trajectory → Export with overlay (slow)
/// - New: Detect trajectory → Composite onto frames → Record composited (instant!)

final class ShotSessionController: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: ShotSessionControllerDelegate?
    
    /// Camera manager for live capture (HIGH FRAME RATE!)
    let cameraManager: CameraManager
    
    /// Vision-based trajectory detector
    let trajectoryDetector: TrajectoryDetector
    
    /// HIGH FRAME RATE ball tracker - the key to reliable detection!
    private var highFrameRateTracker: HighFrameRateBallTracker?
    
    /// REAL-TIME COMPOSITING - tracer baked into recording!
    private var realTimeRecordingManager: RealTimeRecordingManager?
    private var realTimeCompositor: RealTimeCompositor?
    
    /// Video exporter (fallback for non-composited recordings)
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
    
    // Golfer alignment detector for automatic lock-in (iOS 14+)
    private var _alignmentDetector: Any?
    
    @available(iOS 14.0, *)
    var alignmentDetector: GolferAlignmentDetector {
        if _alignmentDetector == nil {
            _alignmentDetector = GolferAlignmentDetector()
        }
        return _alignmentDetector as! GolferAlignmentDetector
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
    private(set) var tracerColor: UIColor = ShotTracerDesign.Colors.tracerRed
    private(set) var tracerStyle: TracerStyle = .neon
    
    /// Debug logging
    var debugLogging = true
    
    /// Use real-time compositing (SmoothSwing-style instant export)
    var useRealTimeCompositing: Bool = true
    
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
        
        // Setup real-time compositing
        setupRealTimeCompositing()
        
        // Setup live detector callbacks (iOS 15+)
        if #available(iOS 15.0, *) {
            setupLiveShotDetector()
        }
        
        // Setup alignment detector (iOS 14+)
        if #available(iOS 14.0, *) {
            setupAlignmentDetector()
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
    
    // MARK: - Real-Time Compositing Setup
    
    private func setupRealTimeCompositing() {
        // Create compositor with Metal acceleration
        realTimeCompositor = RealTimeCompositor()
        realTimeCompositor?.debugLogging = debugLogging
        realTimeCompositor?.tracerColor = tracerColor
        realTimeCompositor?.tracerStyle = tracerStyle
        
        // Create recording manager with compositor
        realTimeRecordingManager = RealTimeRecordingManager(compositor: realTimeCompositor)
        realTimeRecordingManager?.debugLogging = debugLogging
        
        // Wire up callbacks
        realTimeRecordingManager?.onRecordingFinished = { [weak self] url in
            guard let self = self else { return }
            self.handleRealTimeRecordingFinished(url: url)
        }
        
        realTimeRecordingManager?.onRecordingFailed = { [weak self] error in
            guard let self = self else { return }
            self.state = .ready
            self.delegate?.shotSession(self, didFail: error)
        }
        
        // Configure camera manager to use real-time recording
        cameraManager.useRealTimeCompositing = useRealTimeCompositing
        cameraManager.setupRealTimeRecording(manager: realTimeRecordingManager!)
        
        if debugLogging {
            print("✅ Real-time compositing initialized")
        }
    }
    
    // MARK: - Alignment Detector Setup
    
    @available(iOS 14.0, *)
    private func setupAlignmentDetector() {
        alignmentDetector.debugLogging = debugLogging
        
        alignmentDetector.onLockedIn = { [weak self] result in
            guard let self = self else { return }
            
            // Auto-lock position when golfer is in position!
            if let ballPosition = result.ballPosition {
                self.lockPosition(ballPosition: ballPosition)
                
                if self.debugLogging {
                    print("🔒 AUTO-LOCKED via pose detection!")
                    print("   Ball position: \(ballPosition)")
                }
            }
        }
        
        alignmentDetector.onAlignmentChanged = { [weak self] result in
            // Could update UI to show alignment progress
            if self?.debugLogging == true && result.state != .searching {
                print("👤 Alignment: \(result.state.displayName) (score: \(String(format: "%.2f", result.alignmentScore)))")
            }
        }
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
        trajectoryDetector.expectedBallStartNormalized = ballPosition
        
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
        realTimeCompositor?.tracerColor = color
        realTimeRecordingManager?.setTracerColor(color)
    }
    
    /// Set tracer style
    func setTracerStyle(_ style: TracerStyle) {
        tracerStyle = style
        realTimeCompositor?.tracerStyle = style
        realTimeRecordingManager?.setTracerStyle(style)
    }
    
    /// Start camera session
    func startSession() {
        cameraManager.configureSession()
    }
    
    /// Start recording at HIGH FRAME RATE with real-time compositing
    func startRecording() {
        guard case .ready = state else { return }
        
        state = .recording
        finalTrajectory = nil
        finalMetrics = nil
        recordedURL = nil
        frameCounter = 0
        distanceEstimator.reset()
        
        // Clear compositor trajectory for new shot
        realTimeCompositor?.clearTrajectory()
        realTimeRecordingManager?.clearTrajectory()
        
        // Ensure ball position is set
        if let ballPos = silhouetteBallPosition {
            highFrameRateTracker?.setInitialBallPosition(ballPos)
        }
        
        // Start Vision detector
        trajectoryDetector.start()
        
        // Start camera recording (uses real-time compositing if enabled)
        cameraManager.startRecording()
        
        if debugLogging {
            print("═══════════════════════════════════════")
            print("🎬 RECORDING STARTED @ \(cameraManager.currentFrameRate) fps")
            if useRealTimeCompositing {
                print("   Mode: REAL-TIME COMPOSITING")
                print("   Live view === Export video ✓")
            } else {
                print("   Mode: Traditional (post-processing)")
            }
            print("═══════════════════════════════════════")
        }
    }
    
    /// Stop recording and begin export (or finish instantly with real-time compositing!)
    func stopRecording() {
        guard case .recording = state else { return }
        
        // Stop high frame rate tracker
        highFrameRateTracker?.stopTracking()
        
        if useRealTimeCompositing {
            // REAL-TIME COMPOSITING: Video is already done!
            // Just stop recording - the callback will handle finish
            state = .exporting  // Brief state while file is finalized
        } else {
            // Traditional: Need to export with tracer
            state = .tracking
        }
        
        cameraManager.stopRecording()
        trajectoryDetector.stop()
        
        // Unlock live detector
        if #available(iOS 15.0, *) {
            liveShotDetector.unlock()
        }
        
        if debugLogging {
            print("🛑 Recording stopped")
            if useRealTimeCompositing {
                print("   Finalizing composited video...")
            }
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
    
    // MARK: - Real-Time Recording Finished
    
    /// Handle completion of real-time composited recording
    /// The video ALREADY has the tracer baked in - no export needed!
    private func handleRealTimeRecordingFinished(url: URL) {
        self.recordedURL = url
        
        if debugLogging {
            print("═══════════════════════════════════════")
            print("✅ REAL-TIME COMPOSITED VIDEO READY!")
            print("   Tracer is ALREADY in the video")
            print("   NO POST-PROCESSING NEEDED!")
            print("   File: \(url.lastPathComponent)")
            print("═══════════════════════════════════════")
        }
        
        // The video already has the tracer - go straight to finished!
        DispatchQueue.main.async {
            self.state = .finished(videoURL: url)
            self.delegate?.shotSession(self, didFinishExportedVideo: url)
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
        // REAL-TIME COMPOSITING PIPELINE
        // 
        // At 240fps capture:
        // 1. Process EVERY frame for trajectory detection
        // 2. Composite tracer onto frames during recording
        // 3. Write composited frames to video file
        // 4. Live view uses SAME trajectory data
        // 5. Export is INSTANT - tracer already in video!
        // ═══════════════════════════════════════════════════════════════
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Get current trajectory for compositing
        var currentTrajectory: Trajectory?
        
        // Process with HIGH FRAME RATE tracker (primary)
        if let tracker = highFrameRateTracker, case .recording = state {
            let result = tracker.processFrame(
                pixelBuffer,
                timestamp: time,
                orientation: trajectoryDetector.orientation
            )
            
            if result.isTracking {
                currentTrajectory = tracker.buildTrajectory()
                finalTrajectory = currentTrajectory
            }
            
            // Update UI at display rate (every 4th frame at 240fps = 60fps UI)
            let displayUpdateInterval = max(1, Int(manager.currentFrameRate / 60))
            
            if result.isTracking && frameCounter % displayUpdateInterval == 0 {
                if let trajectory = currentTrajectory {
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
        
        // Use Vision detector trajectory if HFR tracker has none
        if currentTrajectory == nil {
            currentTrajectory = trajectoryDetector.currentTrajectory
        }
        
        // ═══════════════════════════════════════════════════════════════
        // REAL-TIME COMPOSITING: Feed frames to recording manager
        // The tracer gets baked INTO the video during recording!
        // ═══════════════════════════════════════════════════════════════
        if case .recording = state,
           useRealTimeCompositing,
           let recorder = realTimeRecordingManager,
           recorder.isRecording {
            
            // Update compositor trajectory (same data used for live view!)
            realTimeCompositor?.updateTrajectory(currentTrajectory?.projectedPoints.map { $0.normalized } ?? [])
            
            // Process and write composited frame
            recorder.processVideoFrame(sampleBuffer, trajectory: currentTrajectory)
        }
        
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
        
        // Alignment detection during alignment phase (iOS 14+)
        if #available(iOS 14.0, *), case .aligning = state {
            _ = alignmentDetector.processFrame(pixelBuffer, orientation: trajectoryDetector.orientation)
        }
    }
    
    func cameraManager(_ manager: CameraManager, didOutputAudio sampleBuffer: CMSampleBuffer) {
        // Feed audio to real-time recording manager
        if case .recording = state,
           useRealTimeCompositing,
           let recorder = realTimeRecordingManager,
           recorder.isRecording {
            recorder.processAudioSample(sampleBuffer)
        }
    }
    
    func cameraManager(_ manager: CameraManager, didFinishRecordingTo url: URL) {
        recordedURL = url
        
        if debugLogging {
            print("📹 Recording saved to: \(url.lastPathComponent)")
        }
        
        // If using real-time compositing, the callback is handled by RealTimeRecordingManager
        // Otherwise, attempt traditional export
        if !useRealTimeCompositing {
            attemptExportIfReady()
        }
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
