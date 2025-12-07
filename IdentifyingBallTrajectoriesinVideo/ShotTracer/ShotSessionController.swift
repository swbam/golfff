import AVFoundation
import UIKit

enum ShotState {
    case idle
    case aligning
    case ready
    case recording
    case tracking
    case importing
    case exporting
    case finished(videoURL: URL)
}

protocol ShotSessionControllerDelegate: AnyObject {
    func shotSession(_ controller: ShotSessionController, didUpdateState state: ShotState)
    func shotSession(_ controller: ShotSessionController, didUpdateTrajectory trajectory: Trajectory)
    func shotSession(_ controller: ShotSessionController, didUpdateMetrics metrics: ShotMetrics)
    func shotSession(_ controller: ShotSessionController, didFinishExportedVideo url: URL)
    func shotSession(_ controller: ShotSessionController, didFail error: Error)
}

final class ShotSessionController: NSObject {
    weak var delegate: ShotSessionControllerDelegate?

    let cameraManager: CameraManager
    let trajectoryDetector: TrajectoryDetector
    private let exporter = ShotExporter()
    private let distanceEstimator = DistanceEstimator()
    
    // Live shot detector for real-time swing detection (iOS 15+)
    private var _liveShotDetector: Any?
    
    @available(iOS 15.0, *)
    var liveShotDetector: LiveShotDetector {
        if _liveShotDetector == nil {
            _liveShotDetector = LiveShotDetector()
        }
        return _liveShotDetector as! LiveShotDetector
    }
    
    // Locked ball position from alignment
    private var lockedBallPosition: CGPoint?

    private var recordedURL: URL?
    private var finalTrajectory: Trajectory?
    private var finalMetrics: ShotMetrics?
    private(set) var tracerColor: UIColor = .systemRed
    
    // Keep strong reference to processor during import to prevent deallocation
    private var activeProcessor: AssetTrajectoryProcessor?

    var state: ShotState = .idle {
        didSet { delegate?.shotSession(self, didUpdateState: state) }
    }

    init(cameraManager: CameraManager, trajectoryDetector: TrajectoryDetector) {
        self.cameraManager = cameraManager
        self.trajectoryDetector = trajectoryDetector
        super.init()
        self.cameraManager.delegate = self
        self.trajectoryDetector.delegate = self
        
        // Setup live detector callbacks (iOS 15+)
        if #available(iOS 15.0, *) {
            setupLiveShotDetector()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        applyThermalSpacing()
        state = .ready
    }
    
    @available(iOS 15.0, *)
    private func setupLiveShotDetector() {
        liveShotDetector.onSwingPhaseChanged = { [weak self] phase in
            guard let self = self else { return }
            print("🏌️ Swing phase: \(phase)")
            
            if case .impact = phase {
                // Haptic feedback on impact
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
            }
        }
        
        liveShotDetector.onBallDetected = { [weak self] position in
            guard let self = self else { return }
            print("🎾 Ball at: (\(String(format: "%.3f", position.x)), \(String(format: "%.3f", position.y)))")
        }
        
        liveShotDetector.onTrajectoryUpdated = { [weak self] points in
            guard let self = self, !points.isEmpty else { return }
            
            // Create trajectory from live points
            let trajectoryPoints = points.enumerated().map { index, point in
                TrajectoryPoint(
                    time: CMTime(seconds: Double(index) * 0.033, preferredTimescale: 600),
                    normalized: point
                )
            }
            let trajectory = Trajectory(id: UUID(), points: trajectoryPoints, confidence: 0.9)
            self.finalTrajectory = trajectory
            self.delegate?.shotSession(self, didUpdateTrajectory: trajectory)
        }
    }
    
    /// Lock in position for live recording
    func lockPosition(ballPosition: CGPoint) {
        lockedBallPosition = ballPosition
        
        if #available(iOS 15.0, *) {
            liveShotDetector.lockPosition(ballPosition: ballPosition)
        }
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        print("🔒 LOCKED IN - Ball position: (\(String(format: "%.3f", ballPosition.x)), \(String(format: "%.3f", ballPosition.y)))")
    }

    func setRegionOfInterest(_ rect: CGRect) {
        trajectoryDetector.regionOfInterest = rect
    }

    func setTracerColor(_ color: UIColor) {
        tracerColor = color
    }

    func startSession() {
        // Configure will also start the session once ready
        cameraManager.configureSession()
    }

    func startRecording() {
        guard case .ready = state else { return }
        state = .recording
        finalTrajectory = nil
        finalMetrics = nil
        recordedURL = nil
        distanceEstimator.reset()
        trajectoryDetector.start()
        cameraManager.startRecording()
    }

    func stopRecording() {
        guard case .recording = state else { return }
        state = .tracking
        cameraManager.stopRecording()
        trajectoryDetector.stop()
    }

    /// Import video with auto-detection and ball position
    func importVideo(from url: URL, roi: CGRect?, ballPosition: CGPoint?) {
        state = .importing
        
        print("📥 Importing video: \(url.lastPathComponent)")
        print("   ROI: \(roi?.debugDescription ?? "full frame")")
        if let ballPos = ballPosition {
            print("   Ball: (\(String(format: "%.3f", ballPos.x)), \(String(format: "%.3f", ballPos.y)))")
        }
        
        let asset = AVAsset(url: url)
        
        // Create new processor with the ROI
        let processor = AssetTrajectoryProcessor(
            roi: roi,
            orientation: orientation(for: asset)
        )
        
        // Set ball position if provided
        if let ballPos = ballPosition {
            processor.setInitialBallPosition(ballPos)
        }
        
        self.activeProcessor = processor
        
        processor.process(asset: asset) { [weak self] result in
            guard let self else { return }
            self.activeProcessor = nil
            
            switch result {
            case .success(let trajectory):
                if let trajectory = trajectory, !trajectory.points.isEmpty {
                    print("✅ Trajectory detected: \(trajectory.points.count) points")
                    self.exportWithTrajectory(url: url, trajectory: trajectory)
                } else {
                    print("❌ No trajectory detected in video")
                    DispatchQueue.main.async {
                        self.state = .ready
                        self.delegate?.shotSession(self, didFail: ShotExportError.noTrajectoryDetected)
                    }
                }
                
            case .failure(let error):
                print("❌ Import failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.state = .ready
                    self.delegate?.shotSession(self, didFail: error)
                }
            }
        }
    }
    
    /// Import video with manual trajectory (user drew the tracer)
    func importVideoWithManualTrajectory(from url: URL, trajectory: Trajectory) {
        state = .importing
        exportWithTrajectory(url: url, trajectory: trajectory)
    }
    
    private func exportWithTrajectory(url: URL, trajectory: Trajectory?) {
        self.finalTrajectory = trajectory
        self.recordedURL = url
        self.state = .exporting
        
        self.exporter.export(videoURL: url, trajectory: trajectory, tracerColor: self.tracerColor) { [weak self] exportResult in
            guard let self else { return }
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

    @objc private func thermalStateChanged() {
        applyThermalSpacing()
    }

    private func applyThermalSpacing() {
        let spacing = desiredFrameSpacing()
        trajectoryDetector.update(frameSpacingSeconds: spacing)
    }

    private func desiredFrameSpacing() -> Double {
        switch ProcessInfo.processInfo.thermalState {
        case .critical:
            return 0.08
        case .serious:
            return 0.04
        case .fair:
            return 0.02
        default:
            return 0.0
        }
    }

    private func orientation(for asset: AVAsset) -> CGImagePropertyOrientation {
        guard let track = asset.tracks(withMediaType: .video).first else { return .up }
        let t = track.preferredTransform
        if t.a == 0, t.b == 1.0, t.c == -1.0, t.d == 0 {
            return .right
        } else if t.a == 0, t.b == -1.0, t.c == 1.0, t.d == 0 {
            return .left
        } else if t.a == 1.0, t.b == 0, t.c == 0, t.d == 1.0 {
            return .up
        } else if t.a == -1.0, t.b == 0, t.c == 0, t.d == -1.0 {
            return .down
        }
        return .up
    }

    private func attemptExportIfReady() {
        switch state {
        case .tracking, .exporting:
            break
        default:
            return
        }
        guard let url = recordedURL else { return }
        state = .exporting
        exporter.export(videoURL: url, trajectory: finalTrajectory, tracerColor: tracerColor) { [weak self] result in
            guard let self else { return }
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
}

extension ShotSessionController: CameraManagerDelegate {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        trajectoryDetector.process(sampleBuffer: sampleBuffer)
    }

    func cameraManager(_ manager: CameraManager, didFinishRecordingTo url: URL) {
        recordedURL = url
        attemptExportIfReady()
    }

    func cameraManager(_ manager: CameraManager, didFail error: Error) {
        delegate?.shotSession(self, didFail: error)
    }
}

extension ShotSessionController: TrajectoryDetectorDelegate {
    func trajectoryDetector(_ detector: TrajectoryDetector, didUpdate trajectory: Trajectory) {
        delegate?.shotSession(self, didUpdateTrajectory: trajectory)
        
        // Calculate and report metrics
        let metrics = distanceEstimator.update(with: trajectory)
        finalMetrics = metrics
        delegate?.shotSession(self, didUpdateMetrics: metrics)
    }

    func trajectoryDetectorDidFinish(_ detector: TrajectoryDetector, finalTrajectory: Trajectory?) {
        self.finalTrajectory = finalTrajectory
        attemptExportIfReady()
    }
}
